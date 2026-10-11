using CodexUsageSidebar.Core;
using System.Runtime.InteropServices;

namespace CodexUsageSidebar.Windows.Tests;

[TestClass]
public sealed class Win32CodexWindowLocatorTests
{
    [TestMethod]
    public void KeepsPerMonitorV2WindowRectInPhysicalScreenPixels()
    {
        var bounds = WindowsCoordinateSpace.ToPhysicalBounds(
            left: -7,
            top: -7,
            right: 1506,
            bottom: 958,
            dpiScale: 2);

        Assert.AreEqual(new RectD(-7, -7, 1513, 965), bounds);
    }

    [TestMethod]
    public void PreservesOnlyAUniqueVerifiedCaptionContainerBounds()
    {
        var host = new RectD(-1600, 100, 1000, 700);
        var caption = new RectD(-1600, 100, 1000, 50);

        Assert.AreEqual(caption, HostWindowGeometry.TryResolveVerifiedCaptionBounds(host, [caption]));
        Assert.IsNull(HostWindowGeometry.TryResolveVerifiedCaptionBounds(host, [caption, caption]));
        Assert.IsNull(HostWindowGeometry.TryResolveVerifiedCaptionBounds(host, [new RectD(-1601, 100, 1000, 50)]));
    }

    [TestMethod]
    public void DoesNotPreserveAnUnverifiedCaptionContainer()
    {
        var host = new RectD(-1600, 100, 1000, 700);
        var caption = new RectD(-1600, 100, 1000, 50);

        Assert.IsNull(HostWindowGeometry.TryResolveVerifiedCaptionBounds(
            host,
            [new HostWindowGeometry.CaptionBoundsCandidate(caption, IsVerified: false)],
            dpiScale: 1.25));
    }

    [TestMethod]
    public async Task FindAsyncComposesPhysicalGeometryAndVerifiedCaptionFromItsAcquisition()
    {
        var acquisition = new StubWindowLocatorAcquisition(
            new WindowLocatorCandidate(
                Handle: new IntPtr(42),
                Left: -1600,
                Top: 100,
                Right: -600,
                Bottom: 800,
                DpiScale: 1.25,
                BuildIdentity: "0.3.3"),
            workArea: new RectD(-1920, 0, 1920, 1080),
            captionCandidates: [new HostWindowGeometry.CaptionBoundsCandidate(
                new RectD(-1600, 100, 1000, 50),
                IsVerified: true)]);

        var snapshot = await new Win32CodexWindowLocator(acquisition).FindAsync(CancellationToken.None);

        Assert.IsNotNull(snapshot);
        Assert.AreEqual(new RectD(-1600, 100, 1000, 700), snapshot.Bounds);
        Assert.AreEqual(new RectD(-1920, 0, 1920, 1080), snapshot.WorkArea);
        Assert.AreEqual(new RectD(-1600, 100, 1000, 50), snapshot.CaptionBounds);
    }

    [TestMethod]
    public async Task FindAsyncReusesVerifiedCaptionForUnchangedWindowGeometry()
    {
        var acquisition = new StubWindowLocatorAcquisition(
            new WindowLocatorCandidate(new IntPtr(42), -1600, 100, -600, 800, 1.25, "0.3.3"),
            workArea: new RectD(-1920, 0, 1920, 1080),
            captionCandidates:
            [new HostWindowGeometry.CaptionBoundsCandidate(
                new RectD(-1600, 100, 1000, 50), IsVerified: true)]);
        var locator = new Win32CodexWindowLocator(acquisition);

        var first = await locator.FindAsync(CancellationToken.None);
        var second = await locator.FindAsync(CancellationToken.None);

        Assert.IsNotNull(first);
        Assert.IsNotNull(second);
        Assert.AreEqual(first.CaptionBounds, second.CaptionBounds);
        Assert.AreEqual(1, acquisition.CaptionCandidateQueries);
    }

    [DataTestMethod]
    [DataRow(CaptionOutcome.Ambiguous)]
    [DataRow(CaptionOutcome.Unavailable)]
    [DataRow(CaptionOutcome.ProviderFailure)]
    public async Task FindAsyncContinuesWithNoCaptionWhenUiaCaptionAcquisitionIsUnsafe(CaptionOutcome outcome)
    {
        var acquisition = new StubWindowLocatorAcquisition(
            new WindowLocatorCandidate(new IntPtr(42), -1600, 100, -600, 800, 1.25, "0.3.3"),
            workArea: new RectD(-1920, 0, 1920, 1080),
            captionCandidates: () => outcome switch
            {
                CaptionOutcome.Ambiguous =>
                [
                    new HostWindowGeometry.CaptionBoundsCandidate(new RectD(-1600, 100, 1000, 50), IsVerified: true),
                    new HostWindowGeometry.CaptionBoundsCandidate(new RectD(-1600, 100, 1000, 50), IsVerified: true)
                ],
                CaptionOutcome.Unavailable => null,
                CaptionOutcome.ProviderFailure => throw new COMException("UIA provider failure"),
                _ => throw new ArgumentOutOfRangeException(nameof(outcome))
            });

        var snapshot = await new Win32CodexWindowLocator(acquisition).FindAsync(CancellationToken.None);

        Assert.IsNotNull(snapshot);
        Assert.AreEqual(new RectD(-1600, 100, 1000, 700), snapshot.Bounds);
        Assert.AreEqual(new RectD(-1920, 0, 1920, 1080), snapshot.WorkArea);
        Assert.IsNull(snapshot.CaptionBounds);
    }

    private sealed class StubWindowLocatorAcquisition : IWindowLocatorAcquisition
    {
        private readonly WindowLocatorCandidate candidate;
        private readonly RectD workArea;
        private readonly Func<IReadOnlyList<HostWindowGeometry.CaptionBoundsCandidate>?> captionCandidates;

        public StubWindowLocatorAcquisition(
            WindowLocatorCandidate candidate,
            RectD workArea,
            IReadOnlyList<HostWindowGeometry.CaptionBoundsCandidate>? captionCandidates)
            : this(candidate, workArea, () => captionCandidates)
        {
        }

        public StubWindowLocatorAcquisition(
            WindowLocatorCandidate candidate,
            RectD workArea,
            Func<IReadOnlyList<HostWindowGeometry.CaptionBoundsCandidate>?> captionCandidates)
        {
            this.candidate = candidate;
            this.workArea = workArea;
            this.captionCandidates = captionCandidates;
        }

        public IntPtr ForegroundWindow => candidate.Handle;
        public int CaptionCandidateQueries { get; private set; }

        public IEnumerable<WindowLocatorCandidate> EnumerateCandidates() => [candidate];

        public RectD? WorkAreaFor(IntPtr handle) => workArea;

        public IReadOnlyList<HostWindowGeometry.CaptionBoundsCandidate>? CaptionCandidatesFor(IntPtr handle)
        {
            CaptionCandidateQueries++;
            return captionCandidates();
        }
    }

    public enum CaptionOutcome
    {
        Ambiguous,
        Unavailable,
        ProviderFailure
    }
}
