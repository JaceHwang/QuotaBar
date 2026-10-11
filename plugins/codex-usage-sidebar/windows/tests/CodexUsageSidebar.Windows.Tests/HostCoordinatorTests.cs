using CodexUsageSidebar.Core;

namespace CodexUsageSidebar.Windows.Tests;

[TestClass]
public sealed class HostCoordinatorTests
{
    [TestMethod]
    public async Task HidesWhenAnotherApplicationBecomesForegroundAndRestoresWhenCodexReturns()
    {
        var window = Window("fixture");
        var overlay = new RecordingOverlay();
        var coordinator = new WindowsHostCoordinator(
            new SequencedLocator(window, window with { IsForeground = false }, window),
            new StubScanner(), overlay);

        Assert.AreEqual(HostRuntimeState.Visible, await coordinator.ReconcileAsync(Snapshot(), CancellationToken.None));
        Assert.AreEqual(HostRuntimeState.Hidden, await coordinator.ReconcileAsync(Snapshot(), CancellationToken.None));
        Assert.AreEqual(HostRuntimeState.Visible, await coordinator.ReconcileAsync(Snapshot(), CancellationToken.None));
        CollectionAssert.AreEqual(new[] { "show", "hide", "show" }, overlay.Events.ToArray());
    }

    [TestMethod]
    public async Task CompanionFocusPreservesVisibilityButDoesNotOverrideMissingHostOrStaleData()
    {
        var window = Window("fixture") with { IsForeground = false };
        var overlay = new RecordingOverlay { HasForegroundWindow = true };
        var coordinator = new WindowsHostCoordinator(new StubLocator(window), new StubScanner(), overlay);
        Assert.AreEqual(HostRuntimeState.Visible, await coordinator.ReconcileAsync(Snapshot(), CancellationToken.None));
        Assert.AreEqual(HostRuntimeState.Hidden, await coordinator.ReconcileAsync(
            Snapshot() with { ReceivedAt = DateTimeOffset.UnixEpoch }, CancellationToken.None));
        var missing = new WindowsHostCoordinator(new StubLocator(null), new StubScanner(), overlay);
        Assert.AreEqual(HostRuntimeState.WaitingForCodex, await missing.ReconcileAsync(Snapshot(), CancellationToken.None));
        Assert.IsNull(overlay.LastPresentation);
    }

    [TestMethod]
    public async Task HidesOverlayWhenTheHostScannerIdentifiesSettings()
    {
        var overlay = new RecordingOverlay();
        var coordinator = new WindowsHostCoordinator(
            new StubLocator(Window("fixture")), new SettingsPageScanner(), overlay);

        var result = await coordinator.ReconcileAsync(Snapshot(), CancellationToken.None);

        Assert.AreEqual(HostRuntimeState.Hidden, result);
        Assert.AreEqual(1, overlay.HideCount);
        Assert.IsNull(overlay.LastPresentation);
    }

    [DataTestMethod]
    [DataRow("返回应用")]
    [DataRow("返回應用")]
    [DataRow("Back to app")]
    public void SettingsNavigationLabelsAreRecognizedAcrossSupportedLanguages(string label)
    {
        var host = new RectD(0, 0, 1600, 1000);
        Assert.IsTrue(HostPagePolicy.IsSettingsNavigation(
            new HostPageControl(new RectD(16, 48, 132, 36), label), host, allowStructuralMatch: false));
        Assert.IsTrue(HostPagePolicy.IsSettingsNavigation(
            new HostPageControl(new RectD(16, 48, 132, 36), "アプリに戻る"), host, allowStructuralMatch: true));
        Assert.IsFalse(HostPagePolicy.IsSettingsNavigation(
            new HostPageControl(new RectD(700, 48, 132, 36), label), host, allowStructuralMatch: true));
    }

    [TestMethod]
    public async Task PlacementUsesTheRenderedIndicatorWidthIncludingItsLogoAndBothRows()
    {
        var overlay = new MeasuredOverlay();
        var coordinator = new WindowsHostCoordinator(new StubLocator(Window("fixture")), new StubScanner(), overlay);
        await coordinator.ReconcileAsync(Snapshot(), CancellationToken.None);
        Assert.IsNotNull(overlay.LastPresentation);
        Assert.AreEqual(275d, overlay.LastPresentation.Placement.Frame.Width);
    }

    private sealed class MeasuredOverlay : IOverlaySurface, IIndicatorSizeProvider
    {
        public OverlayPresentation? LastPresentation { get; private set; }
        public double MeasureIndicatorWidth(AllowanceSnapshot snapshot, DisplayLanguage language, double height) => 275;
        public ValueTask HideAsync(CancellationToken cancellationToken) => ValueTask.CompletedTask;
        public ValueTask ShowAsync(OverlayPresentation presentation, CancellationToken cancellationToken)
        { LastPresentation = presentation; return ValueTask.CompletedTask; }
    }

    private sealed class SettingsPageScanner : ITitlebarScanner
    {
        public ValueTask<TitlebarSnapshot> ScanAsync(HostWindowSnapshot host, CancellationToken cancellationToken) =>
            ValueTask.FromException<TitlebarSnapshot>(new HostSettingsPageDetectedException());
        public void Invalidate() { }
    }

    [TestMethod]
    public async Task FallbackAlsoReservesTheMeasuredIndicatorWidth()
    {
        var overlay = new MeasuredOverlay();
        var coordinator = new WindowsHostCoordinator(new StubLocator(Window("fixture")), new RejectingScanner(), overlay,
            safeDockPreferences: SafeDockPreferences.Default with { FallbackLocked = true });
        await coordinator.ReconcileAsync(Snapshot(), CancellationToken.None);
        Assert.IsNotNull(overlay.LastPresentation);
        Assert.AreEqual(PlacementMode.SafeDock, overlay.LastPresentation.Mode);
        Assert.AreEqual(275d, overlay.LastPresentation.Placement.Frame.Width);
    }

    [TestMethod]
    public async Task HidesOverlayWhenCodexWindowDoesNotExist()
    {
        var overlay = new RecordingOverlay();
        var coordinator = new WindowsHostCoordinator(
            new StubLocator(null), new StubScanner(), overlay);

        var result = await coordinator.ReconcileAsync(Snapshot(), CancellationToken.None);

        Assert.AreEqual(HostRuntimeState.WaitingForCodex, result);
        Assert.AreEqual(1, overlay.HideCount);
        Assert.IsNull(overlay.LastPresentation);
    }

    [TestMethod]
    public async Task ShowsSnapshotInCollisionFreeContentSlot()
    {
        var window = new HostWindowSnapshot(
            new IntPtr(42), new RectD(0, 0, 2048, 1100), true, 2, "codex-build-a");
        var scanner = new StubScanner(new TitlebarSnapshot(1500, new[]
        {
            new RectD(1516, 1052, 116, 36),
            new RectD(1900, 1052, 132, 36),
        },
        new RectD(400, 80, 1600, 92),
        new RectD(1500, 98, 180, 56),
        new RectD(420, 98, 300, 56)));
        var overlay = new RecordingOverlay();
        var coordinator = new WindowsHostCoordinator(new StubLocator(window), scanner, overlay);

        var result = await coordinator.ReconcileAsync(Snapshot(), CancellationToken.None);

        Assert.AreEqual(HostRuntimeState.Visible, result);
        Assert.AreEqual(PlacementSurface.Content, overlay.LastPresentation?.Placement.Surface);
        Assert.IsTrue(Math.Abs(overlay.LastPresentation!.Placement.Frame.X - 1062.6666666666667) < 0.0001);
        Assert.AreEqual(8 * window.DpiScale, 1500 - overlay.LastPresentation.Placement.Frame.Right, 0.0001);
        Assert.AreEqual(98, overlay.LastPresentation?.Placement.Frame.Y);
        Assert.IsTrue(Math.Abs(overlay.LastPresentation!.Placement.Frame.Width - 421.3333333333333) < 0.0001);
        Assert.AreEqual(56, overlay.LastPresentation?.Placement.Frame.Height);
        Assert.AreEqual(76, overlay.LastPresentation?.Snapshot.RemainingPercent);
    }

    [TestMethod]
    public async Task PublishesAndPersistsATitlebarCompatibilityDecisionAfterSafeReconciliation()
    {
        var store = new RecordingRuntimeStateStore();
        var coordinator = new WindowsHostCoordinator(
            new StubLocator(Window("codex-build-a")),
            new StubScanner(),
            new RecordingOverlay(),
            runtimeStateStore: store);

        var result = await coordinator.ReconcileAsync(Snapshot(), CancellationToken.None);

        Assert.AreEqual(HostRuntimeState.Visible, result);
        Assert.AreEqual(
            new CompatibilityDecision(
                SemanticCompatibility.Valid,
                ProfileCompatibility.Validated,
                SafeDockPlacement.Titlebar,
                CompatibilityFailureCode.None),
            coordinator.LastCompatibilityDecision);
        Assert.IsNotNull(store.LastOutcome);
        Assert.AreEqual(HostRuntimeState.Visible, store.LastOutcome.RuntimeState);
        Assert.AreEqual(coordinator.LastCompatibilityDecision, store.LastOutcome.Decision);
    }

    [TestMethod]
    public async Task ShowsSafeDockAfterThreeUnresolvedLiveQuotaReconciliations()
    {
        var now = DateTimeOffset.Now;
        var overlay = new RecordingOverlay();
        var coordinator = new WindowsHostCoordinator(
            new StubLocator(Window("codex-build-a")),
            new RejectingScanner(),
            overlay,
            () => now);

        await coordinator.ReconcileAsync(Snapshot(), CancellationToken.None);
        now = now.AddMilliseconds(500);
        await coordinator.ReconcileAsync(Snapshot(), CancellationToken.None);
        now = now.AddMilliseconds(500);
        var result = await coordinator.ReconcileAsync(Snapshot(), CancellationToken.None);

        Assert.AreEqual(HostRuntimeState.Visible, result);
        Assert.AreEqual(PlacementMode.SafeDock, overlay.LastPresentation?.Mode);
        Assert.AreEqual(SafeDockPlacement.Fallback, coordinator.LastCompatibilityDecision?.Placement);
    }

    [TestMethod]
    public async Task SafeDockUsesPhysicalHostCaptionAndWorkAreaAtOneHundredTwentyFivePercent()
    {
        var now = DateTimeOffset.Now;
        var host = new HostWindowSnapshot(
            new IntPtr(42),
            new RectD(-1600, 100, 1000, 700),
            true,
            1.25,
            "codex-build-a",
            WorkArea: new RectD(-1920, 0, 1920, 1040),
            CaptionBounds: new RectD(-1600, 100, 1000, 50));
        var overlay = new RecordingOverlay();
        var coordinator = new WindowsHostCoordinator(
            new StubLocator(host), new RejectingScanner(), overlay, () => now);

        await coordinator.ReconcileAsync(Snapshot(), CancellationToken.None);
        now = now.AddMilliseconds(500);
        await coordinator.ReconcileAsync(Snapshot(), CancellationToken.None);
        now = now.AddMilliseconds(500);
        await coordinator.ReconcileAsync(Snapshot(), CancellationToken.None);

        var frame = overlay.LastPresentation!.Placement.Frame;
        Assert.IsTrue(frame.X >= host.Bounds.X && frame.Right <= host.Bounds.Right);
        Assert.IsTrue(frame.X >= host.WorkArea!.Value.X && frame.Right <= host.WorkArea.Value.Right);
        Assert.IsTrue(frame.Y >= host.CaptionBounds!.Value.Bottom + 10);
        Assert.IsTrue(frame.Bottom <= host.WorkArea.Value.Bottom);
    }

    [TestMethod]
    public async Task RecoversFromSafeDockOnlyAfterThreeValidatedTitlebarReconciliations()
    {
        var now = DateTimeOffset.Now;
        var scanner = new SwitchableScanner { Reject = true };
        var overlay = new RecordingOverlay();
        var coordinator = new WindowsHostCoordinator(
            new StubLocator(Window("codex-build-a")), scanner, overlay, () => now);

        await coordinator.ReconcileAsync(Snapshot(), CancellationToken.None);
        now = now.AddMilliseconds(500);
        await coordinator.ReconcileAsync(Snapshot(), CancellationToken.None);
        now = now.AddMilliseconds(500);
        await coordinator.ReconcileAsync(Snapshot(), CancellationToken.None);

        scanner.Reject = false;
        now = now.AddSeconds(1);
        await coordinator.ReconcileAsync(Snapshot(), CancellationToken.None);
        now = now.AddMilliseconds(500);
        await coordinator.ReconcileAsync(Snapshot(), CancellationToken.None);
        now = now.AddMilliseconds(500);
        await coordinator.ReconcileAsync(Snapshot(), CancellationToken.None);

        Assert.AreEqual(PlacementMode.Titlebar, overlay.LastPresentation?.Mode);
        Assert.AreEqual(SafeDockPlacement.Titlebar, coordinator.LastCompatibilityDecision?.Placement);
    }

    [TestMethod]
    public async Task UserFallbackLockKeepsAValidatedTitlebarInSafeDock()
    {
        var overlay = new RecordingOverlay();
        var coordinator = new WindowsHostCoordinator(
            new StubLocator(Window("codex-build-a")),
            new StubScanner(),
            overlay,
            safeDockPreferences: SafeDockPreferences.Default with { FallbackLocked = true });

        await coordinator.ReconcileAsync(Snapshot(), CancellationToken.None);

        Assert.AreEqual(PlacementMode.SafeDock, overlay.LastPresentation?.Mode);
        Assert.AreEqual(SafeDockPlacement.Fallback, coordinator.LastCompatibilityDecision?.Placement);
    }

    [TestMethod]
    public async Task DragUpdatedPreferencesArePersistedAndAppliedToTheNextReconciliation()
    {
        var overlay = new PreferenceOverlay();
        var store = new RecordingSafeDockPreferencesStore();
        var coordinator = new WindowsHostCoordinator(
            new StubLocator(Window("codex-build-a")),
            new StubScanner(),
            overlay,
            safeDockPreferencesStore: store);
        var locked = SafeDockPreferences.Default with { FallbackLocked = true, Anchor = SafeDockAnchor.Left };

        await overlay.PublishPreferencesAsync(locked, CancellationToken.None);
        await coordinator.ReconcileAsync(Snapshot(), CancellationToken.None);

        Assert.AreEqual(locked, store.LastSaved);
        Assert.AreEqual(PlacementMode.SafeDock, overlay.LastPresentation?.Mode);
    }

    [TestMethod]
    public async Task CarriesTokenUsageAndAccountIdentityIntoTheOverlayPresentation()
    {
        var window = new HostWindowSnapshot(
            new IntPtr(42), new RectD(0, 0, 2048, 1100), true, 2, "codex-build-a");
        var scanner = new StubScanner(new TitlebarSnapshot(
            1500,
            Array.Empty<RectD>(),
            new RectD(400, 80, 1600, 92),
            new RectD(1500, 98, 180, 56),
            new RectD(420, 98, 300, 56)));
        var overlay = new RecordingOverlay();
        var coordinator = new WindowsHostCoordinator(new StubLocator(window), scanner, overlay);
        var usage = new TokenUsageSnapshot(
            DateTimeOffset.UnixEpoch,
            Array.Empty<TokenUsageDay>(),
            null,
            TokenUsageAvailability.Unsupported);
        var account = new AccountIdentity("Jace", "jace@example.com", null);

        await coordinator.ReconcileAsync(
            Snapshot(),
            DisplayLanguage.English,
            CancellationToken.None,
            usage,
            account);

        Assert.AreSame(usage, overlay.LastPresentation?.TokenUsage);
        Assert.AreSame(account, overlay.LastPresentation?.Account);
        var version = System.Reflection.CustomAttributeExtensions.GetCustomAttribute<System.Reflection.AssemblyInformationalVersionAttribute>(
            typeof(WindowsHostCoordinator).Assembly)!.InformationalVersion.Split('+')[0];
        Assert.AreEqual(version, overlay.LastPresentation?.Version);
    }

    [TestMethod]
    public async Task KeepsOverlayAttachedWhenFocusMovesToTheCompanion()
    {
        var window = Window("codex-build-a") with { IsForeground = false };
        var overlay = new RecordingOverlay { HasForegroundWindow = true };
        var coordinator = new WindowsHostCoordinator(
            new StubLocator(window), new StubScanner(), overlay);

        var result = await coordinator.ReconcileAsync(Snapshot(), CancellationToken.None);

        Assert.AreEqual(HostRuntimeState.Visible, result);
        Assert.IsNotNull(overlay.LastPresentation);
        Assert.AreEqual(window.Handle, overlay.LastPresentation.OwnerHandle);
    }

    [TestMethod]
    public async Task HostBuildChangeInvalidatesScannerBeforeNextSnapshot()
    {
        var locator = new SequencedLocator(
            Window("codex-build-a"), Window("codex-build-b"));
        var scanner = new StubScanner(new TitlebarSnapshot(1000, Array.Empty<RectD>()));
        var coordinator = new WindowsHostCoordinator(locator, scanner, new RecordingOverlay());

        await coordinator.ReconcileAsync(Snapshot(), CancellationToken.None);
        await coordinator.ReconcileAsync(Snapshot(), CancellationToken.None);

        Assert.AreEqual(1, scanner.InvalidateCount);
    }

    [TestMethod]
    public async Task LanguageChangeInvalidatesCachedTitlebarAndRepositionsTheIndicator()
    {
        var window = new HostWindowSnapshot(
            new IntPtr(42), new RectD(-13, -13, 3026, 1930), true, 2, "151.0.7922.76");
        var scanner = new LanguageSensitiveScanner(
            new TitlebarSnapshot(
                2620,
                [new RectD(2620, 88, 182, 56)],
                new RectD(478, 70, 2522, 92),
                new RectD(2620, 88, 182, 56),
                new RectD(494, 88, 542, 56)),
            new TitlebarSnapshot(
                2021,
                [new RectD(2021, 88, 183, 56)],
                new RectD(478, 70, 2522, 92),
                new RectD(2021, 88, 183, 56),
                new RectD(494, 88, 542, 56)));
        var overlay = new RecordingOverlay();
        var coordinator = new WindowsHostCoordinator(new StubLocator(window), scanner, overlay);

        await coordinator.ReconcileAsync(Snapshot(), DisplayLanguage.SimplifiedChinese, CancellationToken.None);
        var simplifiedFrame = overlay.LastPresentation!.Placement.Frame;
        await coordinator.ReconcileAsync(Snapshot(), DisplayLanguage.English, CancellationToken.None);

        Assert.AreEqual(1, scanner.InvalidateCount);
        Assert.AreEqual(DisplayLanguage.English, overlay.LastPresentation?.Language);
        Assert.AreNotEqual(simplifiedFrame, overlay.LastPresentation?.Placement.Frame);
        Assert.IsTrue(Math.Abs(overlay.LastPresentation!.Placement.Frame.X - 1583.6666666666667) < 0.0001);
        Assert.IsTrue(Math.Abs(overlay.LastPresentation.Placement.Frame.Width - 421.3333333333333) < 0.0001);
    }

    [TestMethod]
    public async Task UnverifiedUiaTreeHidesOverlayAndReportsDeviceValidationRequirement()
    {
        var overlay = new RecordingOverlay();
        var coordinator = new WindowsHostCoordinator(
            new StubLocator(Window("unknown-build")),
            new RejectingScanner(),
            overlay);

        var result = await coordinator.ReconcileAsync(Snapshot(), CancellationToken.None);

        Assert.AreEqual(HostRuntimeState.DeviceValidationRequired, result);
        Assert.AreEqual(1, overlay.HideCount);
    }

    [TestMethod]
    public async Task InvalidCatalogFailureIsPublishedAsInvalidCatalog()
    {
        var overlay = new RecordingOverlay();
        var coordinator = new WindowsHostCoordinator(
            new StubLocator(Window("build-a")),
            new InvalidCatalogScanner(),
            overlay);

        var result = await coordinator.ReconcileAsync(Snapshot(), CancellationToken.None);

        Assert.AreEqual(HostRuntimeState.DeviceValidationRequired, result);
        Assert.AreEqual(CompatibilityFailureCode.InvalidCatalog, coordinator.LastCompatibilityDecision?.FailureCode);
        Assert.AreEqual(1, overlay.HideCount);
    }

    [TestMethod]
    public async Task KnownBuildWithoutAResolvedTitlebarFailsClosedInsteadOfUsingCoordinates()
    {
        var window = new HostWindowSnapshot(
            new IntPtr(42), new RectD(-13, -13, 3026, 1930), true, 2, "151.0.7922.76");
        var overlay = new RecordingOverlay();
        var coordinator = new WindowsHostCoordinator(
            new StubLocator(window),
            new RejectingScanner(),
            overlay);

        var result = await coordinator.ReconcileAsync(Snapshot(), CancellationToken.None);

        Assert.AreEqual(HostRuntimeState.DeviceValidationRequired, result);
        Assert.AreEqual(CompatibilityFailureCode.UiaUnavailable, coordinator.LastCompatibilityDecision?.FailureCode);
        Assert.AreEqual(SafeDockPlacement.None, coordinator.LastCompatibilityDecision?.Placement);
        Assert.AreEqual(1, overlay.HideCount);
        Assert.IsNull(overlay.LastPresentation);
    }

    [TestMethod]
    public async Task UnresolvedTitlebarDoesNotInspectFallbackGeometry()
    {
        var window = new HostWindowSnapshot(
            new IntPtr(42), new RectD(0, 0, 100, 200), true, 1, "151.0.7922.76");
        var coordinator = new WindowsHostCoordinator(
            new StubLocator(window),
            new RejectingScanner(),
            new RecordingOverlay());

        var result = await coordinator.ReconcileAsync(Snapshot(), CancellationToken.None);

        Assert.AreEqual(HostRuntimeState.DeviceValidationRequired, result);
        Assert.AreEqual(CompatibilityFailureCode.UiaUnavailable, coordinator.LastCompatibilityDecision?.FailureCode);
    }

    [TestMethod]
    public async Task UnresolvedTitlebarWithOverflowingBoundsFailsClosedWithoutShowingOverlay()
    {
        var window = new HostWindowSnapshot(
            new IntPtr(42), new RectD(double.MaxValue, 0, double.MaxValue, 900), true, 1, "151.0.7922.76");
        var overlay = new RecordingOverlay();
        var coordinator = new WindowsHostCoordinator(
            new StubLocator(window),
            new RejectingScanner(),
            overlay);

        var result = await coordinator.ReconcileAsync(Snapshot(), CancellationToken.None);

        Assert.AreEqual(HostRuntimeState.DeviceValidationRequired, result);
        Assert.AreEqual(CompatibilityFailureCode.UiaUnavailable, coordinator.LastCompatibilityDecision?.FailureCode);
        Assert.AreEqual(1, overlay.HideCount);
        Assert.IsNull(overlay.LastPresentation);
    }

    [TestMethod]
    public async Task UnknownBuildStillHidesWhenUiaIsUnavailable()
    {
        var overlay = new RecordingOverlay();
        var coordinator = new WindowsHostCoordinator(
            new StubLocator(Window("151.0.7922.77")),
            new RejectingScanner(),
            overlay);

        var result = await coordinator.ReconcileAsync(Snapshot(), CancellationToken.None);

        Assert.AreEqual(HostRuntimeState.DeviceValidationRequired, result);
        Assert.AreEqual(1, overlay.HideCount);
    }

    [TestMethod]
    [DataRow(false)]
    [DataRow(true)]
    public async Task ShowsDefaultFrameWhenNoCollisionFreeTitlebarSlotExists(bool defaultOccupied)
    {
        var overlay = new RecordingOverlay();
        var scanner = new StubScanner(new TitlebarSnapshot(
            300,
            [new RectD(300, 60, 80, 28), new RectD(defaultOccupied ? 50 : 300, 69, 80, 28)],
            new RectD(0, 60, 400, 46),
            new RectD(300, 69, 80, 28),
            new RectD(8, 69, 280, 28)));
        var coordinator = new WindowsHostCoordinator(
            new StubLocator(new HostWindowSnapshot(
                new IntPtr(42), new RectD(0, 0, 400, 800), true, 1, "codex-build-a")),
            scanner,
            overlay);

        var result = await coordinator.ReconcileAsync(Snapshot(), CancellationToken.None);

        Assert.AreEqual(HostRuntimeState.Visible, result);
        Assert.AreEqual(0, overlay.HideCount);
        Assert.IsNotNull(overlay.LastPresentation);
        Assert.AreEqual(defaultOccupied, overlay.LastPresentation.SwitchToFree);
    }

    [TestMethod]
    public async Task UsesValidatedRightToolbarWhenTheMeasuredLocalGapIsTooNarrow()
    {
        var window = new HostWindowSnapshot(
            new IntPtr(42), new RectD(-13, -13, 3026, 1930), true, 2, "codex-build-a");
        var scanner = new StubScanner(new TitlebarSnapshot(
            1069,
            [new RectD(1069, 88, 183, 56), new RectD(1251, 88, 47, 56)],
            new RectD(478, 70, 2522, 92),
            new RectD(1069, 88, 183, 56),
            new RectD(494, 88, 533, 56),
            new RectD(1395, 70, 1461, 92),
            [new RectD(2856, 88, 56, 56)]));
        var overlay = new RecordingOverlay();
        var coordinator = new WindowsHostCoordinator(new StubLocator(window), scanner, overlay);

        var result = await coordinator.ReconcileAsync(Snapshot(), CancellationToken.None);

        Assert.AreEqual(HostRuntimeState.Visible, result);
        Assert.AreEqual(PlacementSurface.RightToolbar, overlay.LastPresentation?.Placement.Surface);
        Assert.IsTrue(Math.Abs(overlay.LastPresentation!.Placement.Frame.X - 2239.6666666666665) < 0.0001);
        Assert.IsTrue(Math.Abs(overlay.LastPresentation.Placement.Frame.Width - 421.3333333333333) < 0.0001);
        Assert.AreEqual(window.Bounds.Right - 176 * window.DpiScale,
            overlay.LastPresentation.Placement.Frame.Right, 0.0001);
        Assert.IsTrue(2856 - overlay.LastPresentation.Placement.Frame.Right >= 8 * window.DpiScale);
    }

    [TestMethod]
    public async Task ScannerFailureHidesOverlayInsteadOfEscapingTheUiLoop()
    {
        var overlay = new RecordingOverlay();
        var coordinator = new WindowsHostCoordinator(
            new StubLocator(Window("codex-build-a")),
            new FailingScanner(),
            overlay);

        var result = await coordinator.ReconcileAsync(Snapshot(), CancellationToken.None);

        Assert.AreEqual(HostRuntimeState.DeviceValidationRequired, result);
        Assert.AreEqual(1, overlay.HideCount);
    }

    [TestMethod]
    public async Task ScalesIndicatorGeometryInThePhysicalPixelCoordinateSpace()
    {
        var window = new HostWindowSnapshot(
            new IntPtr(42), new RectD(-3000, 0, 4096, 2200), true, 2, "codex-build-a");
        var scanner = new StubScanner(new TitlebarSnapshot(
            500,
            [],
            new RectD(-2600, 70, 3600, 92),
            new RectD(500, 88, 183, 56),
            new RectD(-2500, 88, 500, 56)));
        var overlay = new RecordingOverlay();
        var coordinator = new WindowsHostCoordinator(new StubLocator(window), scanner, overlay);

        var result = await coordinator.ReconcileAsync(Snapshot(), CancellationToken.None);

        Assert.AreEqual(HostRuntimeState.Visible, result);
        Assert.IsTrue(Math.Abs(overlay.LastPresentation!.Placement.Frame.Width - 421.3333333333333) < 0.0001);
        Assert.AreEqual(56, overlay.LastPresentation?.Placement.Frame.Height);
        Assert.AreEqual(88, overlay.LastPresentation?.Placement.Frame.Y);
    }

    [TestMethod]
    public async Task HidesSnapshotsAtTheFreshnessDeadlineBeforeScanningUia()
    {
        var scanner = new StubScanner();
        var overlay = new RecordingOverlay();
        var now = DateTimeOffset.UnixEpoch.AddSeconds(300);
        var coordinator = new WindowsHostCoordinator(
            new StubLocator(Window("codex-build-a")), scanner, overlay, () => now);
        var stale = Snapshot() with { ReceivedAt = DateTimeOffset.UnixEpoch };

        var result = await coordinator.ReconcileAsync(stale, CancellationToken.None);

        Assert.AreEqual(HostRuntimeState.Hidden, result);
        Assert.AreEqual(0, scanner.ScanCount);
        Assert.AreEqual(1, overlay.HideCount);
    }

    [TestMethod]
    public async Task MarksSnapshotsDimmedAfterTwoMinutes()
    {
        var now = DateTimeOffset.UnixEpoch.AddSeconds(120);
        var overlay = new RecordingOverlay();
        var coordinator = new WindowsHostCoordinator(
            new StubLocator(Window("codex-build-a")), new StubScanner(), overlay, () => now);
        var snapshot = Snapshot() with { ReceivedAt = DateTimeOffset.UnixEpoch };

        await coordinator.ReconcileAsync(snapshot, CancellationToken.None);

        Assert.AreEqual(SnapshotFreshness.Dimmed, overlay.LastPresentation?.Freshness);
    }

    [TestMethod]
    public void AppServerLaunchPlanUsesFixedArgumentsAndIsolatedCodexHome()
    {
        var plan = AppServerLaunchPlan.Create(
            @"C:\Program Files\Codex\codex.exe",
            @"C:\Users\fixture\AppData\Local\CodexUsageSidebar\CodexHome");

        CollectionAssert.AreEqual(new[] { "app-server", "--stdio" }, plan.Arguments.ToArray());
        Assert.AreEqual(@"C:\Users\fixture\AppData\Local\CodexUsageSidebar\CodexHome", plan.Environment["CODEX_HOME"]);
        Assert.ThrowsException<ArgumentException>(() => AppServerLaunchPlan.Create("codex.exe", @"C:\isolated"));
    }

    [TestMethod]
    public void HostArgumentsAcceptTheExactHookContract()
    {
        if (!OperatingSystem.IsWindows()) Assert.Inconclusive("Windows absolute-path semantics require Windows.");
        var result = WindowsHostArguments.TryParse([
            "--background",
            "--plugin-root", @"C:\fixture\plugin",
            "--plugin-data", @"C:\fixture\data",
        ]);

        Assert.IsNotNull(result);
        Assert.IsTrue(result.Background);
        Assert.AreEqual(@"C:\fixture\plugin", result.PluginRoot);
        Assert.AreEqual(@"C:\fixture\data", result.PluginData);
    }

    [TestMethod]
    public void HostArgumentsRejectUnknownDuplicateAndIncompleteOptions()
    {
        Assert.IsNull(WindowsHostArguments.TryParse(["--unknown"]));
        Assert.IsNull(WindowsHostArguments.TryParse(["--plugin-root"]));
        Assert.IsNull(WindowsHostArguments.TryParse([
            "--plugin-data", @"C:\one", "--plugin-data", @"C:\two",
        ]));
    }

    [TestMethod]
    public void OverlayVisualMetricsMatchTheDualQuotaTitlebarBaseline()
    {
        Assert.AreEqual(192, OverlayVisualMetrics.IndicatorContentWidth, 0.000001);
        Assert.AreEqual(168, OverlayVisualMetrics.IndicatorTextWidth, 0.000001);
        Assert.AreEqual(20, OverlayVisualMetrics.IndicatorLogoSize, 0.000001);
        Assert.AreEqual(4, OverlayVisualMetrics.IndicatorLogoTextGap, 0.000001);
        Assert.AreEqual(192 + (2 * (28d / 3d)), OverlayVisualMetrics.IndicatorWidth, 0.000001);
        Assert.AreEqual(192 + (2 * (56d / 3d)), OverlayVisualMetrics.IndicatorWidthForHeight(56), 0.000001);
        Assert.AreEqual(28d / 3d, OverlayVisualMetrics.IndicatorHorizontalPadding, 0.000001);
        Assert.AreEqual(360, OverlayVisualMetrics.DetailWidth);
        Assert.AreEqual(18, OverlayVisualMetrics.HeaderTitleFontSize);
        Assert.AreEqual(9, OverlayVisualMetrics.VersionBadgeFontSize);
        Assert.AreEqual(18, OverlayVisualMetrics.VersionBadgeHeight);
        Assert.AreEqual(26, OverlayVisualMetrics.DetailLockButtonSize);
        Assert.AreEqual(6, OverlayVisualMetrics.DetailLockButtonBadgeGap);
        Assert.AreEqual(20, OverlayVisualMetrics.DetailLockButtonHoverAlpha);
        Assert.AreEqual(31, OverlayVisualMetrics.DetailLockButtonActiveAlpha);
        Assert.AreEqual(14, OverlayVisualMetrics.DetailResizeHitHeight);
        Assert.AreEqual(20, OverlayVisualMetrics.DetailResizeHandleWidth);
        Assert.AreEqual(3, OverlayVisualMetrics.DetailResizeHandleHeight);
        Assert.AreEqual(28, OverlayVisualMetrics.RemainingPercentFontSize);
        Assert.AreEqual(13, OverlayVisualMetrics.DetailValueFontSize);
        Assert.AreEqual(16, OverlayVisualMetrics.CountdownDigitFontSize);
        Assert.AreEqual(11, OverlayVisualMetrics.CountdownUnitFontSize);
        Assert.AreEqual(4, OverlayVisualMetrics.ProgressTrackHeight);
    }

    [TestMethod]
    public void DetailPopupPrefersTheIndicatorLeftEdgeAndClampsToTheWorkArea()
    {
        var aligned = OverlayDetailLayout.LeftForIndicator(
            new RectD(600, 100, 333, 56),
            new RectD(0, 0, 1600, 900),
            720d);
        var clamped = OverlayDetailLayout.LeftForIndicator(
            new RectD(1400, 100, 333, 56),
            new RectD(0, 0, 1600, 900),
            720d);

        Assert.AreEqual(600, aligned, 0.000001);
        Assert.AreEqual(880, clamped, 0.000001);
        Assert.AreEqual(28, OverlayDetailLayout.LogoSize, 0.000001);
        Assert.AreEqual(1, OverlayDetailLayout.RowSeparatorHeight, 0.000001);
    }

    [TestMethod]
    public void DetailCardReservesTwoFullWidthSectionSeparators()
    {
        var separatorCount = typeof(OverlayDetailLayout)
            .GetField("FullWidthSectionSeparatorCount")
            ?.GetValue(null);
        var separatorHeight = typeof(OverlayDetailLayout)
            .GetField("SectionSeparatorHeight")
            ?.GetValue(null);
        var horizontalMargin = typeof(OverlayDetailLayout)
            .GetField("SectionSeparatorHorizontalMargin")
            ?.GetValue(null);

        Assert.IsNotNull(separatorCount);
        Assert.IsNotNull(separatorHeight);
        Assert.IsNotNull(horizontalMargin);
        Assert.AreEqual(2, (int)separatorCount!);
        Assert.AreEqual(1d, (double)separatorHeight!, 0.000001);
        Assert.AreEqual(0d, (double)horizontalMargin!, 0.000001);
    }

    [TestMethod]
    public void PassiveOverlayReassertsNativeVisibilityWithoutActivation()
    {
        Assert.AreEqual(0x0250u, OverlayWindowPolicy.PositionFlags);
    }

    [TestMethod]
    public void PassiveOverlayPointerHitTestingUsesPhysicalWindowRectangles()
    {
        var indicator = new RectD(2591, 88, 264, 56);
        var detail = new RectD(2240, 156, 600, 400);

        Assert.IsTrue(OverlayPointerPolicy.IsInside(new PointD(2676, 116), indicator));
        Assert.IsTrue(OverlayPointerPolicy.IsInside(new PointD(2300, 200), detail));
        Assert.IsFalse(OverlayPointerPolicy.IsInside(new PointD(2511, 116), indicator));
        Assert.IsFalse(OverlayPointerPolicy.IsInside(new PointD(2856, 116), indicator));
        Assert.IsFalse(OverlayPointerPolicy.IsInside(new PointD(double.NaN, 116), indicator));
    }

    [TestMethod]
    public void OverlayThemeFollowsTheValidatedTitlebarPixelAndHighContrastOverride()
    {
        Assert.AreEqual(OverlayThemeKind.Dark, OverlayThemePolicy.Resolve(6, 4, 1, highContrast: false));
        Assert.AreEqual(OverlayThemeKind.Light, OverlayThemePolicy.Resolve(248, 248, 248, highContrast: false));
        Assert.AreEqual(OverlayThemeKind.HighContrast, OverlayThemePolicy.Resolve(248, 248, 248, highContrast: true));
    }

    [TestMethod]
    public void HostSingletonRefusesASecondLeaseUntilTheFirstIsDisposed()
    {
        var identity = $"test-{Guid.NewGuid():N}";
        using var first = PerUserHostSingleton.TryAcquire(identity);

        Assert.IsNotNull(first);
        Assert.IsNull(PerUserHostSingleton.TryAcquire(identity));

        first.Dispose();
        using var afterRelease = PerUserHostSingleton.TryAcquire(identity);
        Assert.IsNotNull(afterRelease);
    }

    [TestMethod]
    public void ValidatedTitlebarCacheKeepsAStableHostSnapshotFreshForThirtySeconds()
    {
        long timestamp = 10_000;
        var cache = new ValidatedTitlebarCache(
            () => timestamp,
            timestampFrequency: 1_000);
        var host = new HostWindowSnapshot(
            new IntPtr(9), new RectD(-2000, 0, 1600, 1200), true, 1.5, "build-a");
        var snapshot = new TitlebarSnapshot(-500, []);
        cache.Store(host, snapshot);

        Assert.AreSame(snapshot, cache.TryGet(host));
        Assert.IsNull(cache.TryGet(host with { Bounds = host.Bounds with { X = -1999 } }));
        Assert.IsNull(cache.TryGet(host with { DpiScale = 2 }));
        Assert.IsNull(cache.TryGet(host with { BuildIdentity = "build-b" }));

        timestamp += 29_999;
        Assert.AreSame(snapshot, cache.TryGet(host));

        timestamp += 1;
        Assert.IsNull(cache.TryGet(host));
        Assert.AreSame(snapshot, cache.TryGetRetained(host));

        timestamp += 270_000;
        Assert.IsNull(cache.TryGetRetained(host));

        cache.Invalidate();
        Assert.IsNull(cache.TryGet(host));
    }

    [TestMethod]
    public async Task RevalidatesAnExpiredUiaStructureWithoutHidingAVisibleOverlayFirst()
    {
        var overlay = new RecordingOverlay();
        var scanner = new StubScanner { ValidationCurrent = false };
        var coordinator = new WindowsHostCoordinator(
            new StubLocator(Window("codex-build-a")), scanner, overlay);

        await coordinator.ReconcileAsync(Snapshot(), CancellationToken.None);

        CollectionAssert.AreEqual(new[] { "show" }, overlay.Events.ToArray());
    }

    [TestMethod]
    public async Task RetainsTheLastSafePlacementDuringATransientUiaFailure()
    {
        var window = Window("codex-build-a");
        var retained = new TitlebarSnapshot(
            1000,
            [],
            new RectD(200, 60, 1100, 46),
            new RectD(1000, 69, 180, 28),
            new RectD(220, 69, 300, 28));
        var overlay = new RecordingOverlay();
        var coordinator = new WindowsHostCoordinator(
            new StubLocator(window),
            new RetainingFailingScanner(retained),
            overlay);

        var result = await coordinator.ReconcileAsync(Snapshot(), CancellationToken.None);

        Assert.AreEqual(HostRuntimeState.Visible, result);
        CollectionAssert.AreEqual(new[] { "show" }, overlay.Events.ToArray());
    }

    private static HostWindowSnapshot Window(string build) =>
        new(new IntPtr(42), new RectD(0, 0, 1400, 900), true, 1, build);

    private static AllowanceSnapshot Snapshot() => new(
        24, 76, DateTimeOffset.FromUnixTimeSeconds(1_785_628_824), DateTimeOffset.Now);

    private sealed class StubLocator(HostWindowSnapshot? value) : IHostWindowLocator
    {
        public ValueTask<HostWindowSnapshot?> FindAsync(CancellationToken cancellationToken) => ValueTask.FromResult(value);
    }

    private sealed class SequencedLocator(params HostWindowSnapshot[] values) : IHostWindowLocator
    {
        private int index;
        public ValueTask<HostWindowSnapshot?> FindAsync(CancellationToken cancellationToken) =>
            ValueTask.FromResult<HostWindowSnapshot?>(values[Math.Min(index++, values.Length - 1)]);
    }

    private sealed class StubScanner(TitlebarSnapshot? value = null) : ITitlebarScanner
    {
        public bool ValidationCurrent { get; set; } = true;
        public int InvalidateCount { get; private set; }
        public int ScanCount { get; private set; }
        public ValueTask<TitlebarSnapshot> ScanAsync(HostWindowSnapshot host, CancellationToken cancellationToken)
        {
            ScanCount++;
            return ValueTask.FromResult(value ?? SnapshotFor(host));
        }
        public TitlebarSnapshot? TryGetCurrent(HostWindowSnapshot host) => ValidationCurrent
            ? value ?? SnapshotFor(host)
            : null;
        public void Invalidate() => InvalidateCount++;

        private static TitlebarSnapshot SnapshotFor(HostWindowSnapshot host) => new(
            host.Bounds.Right - 100,
            Array.Empty<RectD>(),
            new RectD(host.Bounds.X, host.Bounds.Y + 60, host.Bounds.Width, 46 * host.DpiScale),
            new RectD(
                host.Bounds.Right - 100,
                host.Bounds.Y + 69,
                80,
                28 * host.DpiScale),
            new RectD(
                host.Bounds.X + 8,
                host.Bounds.Y + 69,
                200,
                28 * host.DpiScale));
    }

    private sealed class LanguageSensitiveScanner(params TitlebarSnapshot[] snapshots) : ITitlebarScanner
    {
        private int index;
        private TitlebarSnapshot? cached;
        public int InvalidateCount { get; private set; }

        public TitlebarSnapshot? TryGetCurrent(HostWindowSnapshot host) => cached;

        public ValueTask<TitlebarSnapshot> ScanAsync(HostWindowSnapshot host, CancellationToken cancellationToken)
        {
            cached = snapshots[Math.Min(index++, snapshots.Length - 1)];
            return ValueTask.FromResult(cached);
        }

        public void Invalidate()
        {
            InvalidateCount++;
            cached = null;
        }
    }

    private sealed class RejectingScanner : ITitlebarScanner
    {
        public ValueTask<TitlebarSnapshot> ScanAsync(HostWindowSnapshot host, CancellationToken cancellationToken) =>
            ValueTask.FromException<TitlebarSnapshot>(new WindowsDeviceValidationRequiredException(host.BuildIdentity));
        public void Invalidate() { }
    }

    private sealed class InvalidCatalogScanner : ITitlebarScanner
    {
        public ValueTask<TitlebarSnapshot> ScanAsync(HostWindowSnapshot host, CancellationToken cancellationToken) =>
            ValueTask.FromException<TitlebarSnapshot>(new InvalidSelectorCatalogException());
        public void Invalidate() { }
    }

    private sealed class FailingScanner : ITitlebarScanner
    {
        public ValueTask<TitlebarSnapshot> ScanAsync(HostWindowSnapshot host, CancellationToken cancellationToken) =>
            ValueTask.FromException<TitlebarSnapshot>(new InvalidOperationException("UIA unavailable"));
        public void Invalidate() { }
    }

    private sealed class RetainingFailingScanner(TitlebarSnapshot retained) : ITitlebarScanner
    {
        public TitlebarSnapshot? TryGetRetained(HostWindowSnapshot host) => retained;
        public ValueTask<TitlebarSnapshot> ScanAsync(HostWindowSnapshot host, CancellationToken cancellationToken) =>
            ValueTask.FromException<TitlebarSnapshot>(new WindowsDeviceValidationRequiredException(host.BuildIdentity));
        public void Invalidate() { }
    }

    private sealed class SwitchableScanner : ITitlebarScanner
    {
        public bool Reject { get; set; }

        public TitlebarSnapshot? TryGetCurrent(HostWindowSnapshot host) => null;

        public ValueTask<TitlebarSnapshot> ScanAsync(HostWindowSnapshot host, CancellationToken cancellationToken) =>
            Reject
                ? ValueTask.FromException<TitlebarSnapshot>(new WindowsDeviceValidationRequiredException(host.BuildIdentity))
                : ValueTask.FromResult(new TitlebarSnapshot(
                    host.Bounds.Right - 100,
                    Array.Empty<RectD>(),
                    new RectD(host.Bounds.X, host.Bounds.Y + 60, host.Bounds.Width, 46 * host.DpiScale),
                    new RectD(host.Bounds.Right - 100, host.Bounds.Y + 69, 80, 28 * host.DpiScale),
                    new RectD(host.Bounds.X + 8, host.Bounds.Y + 69, 200, 28 * host.DpiScale)));

        public void Invalidate() { }
    }

    private sealed class RecordingOverlay : IOverlaySurface
    {
        public bool HasForegroundWindow { get; set; }
        public List<string> Events { get; } = new();
        public int HideCount { get; private set; }
        public OverlayPresentation? LastPresentation { get; private set; }
        public ValueTask HideAsync(CancellationToken cancellationToken) { Events.Add("hide"); HideCount++; LastPresentation = null; return ValueTask.CompletedTask; }
        public ValueTask ShowAsync(OverlayPresentation presentation, CancellationToken cancellationToken) { Events.Add("show"); LastPresentation = presentation; return ValueTask.CompletedTask; }
    }

    private sealed class PreferenceOverlay : ISafeDockOverlaySurface
    {
        public event Func<SafeDockPreferences, CancellationToken, ValueTask>? SafeDockPreferencesChanged;
        public OverlayPresentation? LastPresentation { get; private set; }

        public ValueTask HideAsync(CancellationToken cancellationToken)
        {
            LastPresentation = null;
            return ValueTask.CompletedTask;
        }

        public ValueTask ShowAsync(OverlayPresentation presentation, CancellationToken cancellationToken)
        {
            LastPresentation = presentation;
            return ValueTask.CompletedTask;
        }

        public async ValueTask PublishPreferencesAsync(SafeDockPreferences preferences, CancellationToken cancellationToken)
        {
            if (SafeDockPreferencesChanged is null) return;
            foreach (Func<SafeDockPreferences, CancellationToken, ValueTask> handler in SafeDockPreferencesChanged.GetInvocationList())
            {
                await handler(preferences, cancellationToken);
            }
        }
    }

    private sealed class RecordingSafeDockPreferencesStore : ISafeDockPreferencesStore
    {
        public SafeDockPreferences? LastSaved { get; private set; }

        public ValueTask<SafeDockPreferences> LoadAsync(CancellationToken cancellationToken) =>
            ValueTask.FromResult(SafeDockPreferences.Default);

        public ValueTask SaveAsync(SafeDockPreferences preferences, CancellationToken cancellationToken)
        {
            LastSaved = preferences;
            return ValueTask.CompletedTask;
        }
    }

    private sealed class RecordingRuntimeStateStore : IRuntimeStateStore
    {
        public RuntimeStateOutcome? LastOutcome { get; private set; }

        public ValueTask WriteAsync(RuntimeStateOutcome outcome, CancellationToken cancellationToken)
        {
            LastOutcome = outcome;
            return ValueTask.CompletedTask;
        }
    }
}
