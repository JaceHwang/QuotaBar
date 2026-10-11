using System.IO.Compression;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using CodexUsageSidebar.Core;

namespace CodexUsageSidebar.Windows.Tests;

[TestClass]
public sealed class CompatibilityManagementTests
{
    [TestMethod]
    public async Task AcceptsAVerifiedNewerCatalogAndPersistsItsEtag()
    {
        using var key = ECDsa.Create(ECCurve.NamedCurves.nistP256);
        var cache = new InMemoryCompatibilityPackCache();
        var transport = new RecordingPackTransport(CreatePack(key, 7, "etag-7"));
        var updater = new CompatibilityPackUpdater(key.ExportSubjectPublicKeyInfo(), transport, cache, () => new DateTimeOffset(2026, 8, 23, 0, 0, 0, TimeSpan.Zero));

        var result = await updater.UpdateAsync(CancellationToken.None);

        Assert.AreEqual(CompatibilityPackUpdateResult.Updated, result);
        Assert.AreEqual("etag-7", cache.Current!.ETag);
        Assert.AreEqual(7, cache.Current.Sequence);
        Assert.IsTrue(SelectorProfileCatalog.TryParse(Encoding.UTF8.GetString(cache.Current.Catalog), out _));
    }

    [TestMethod]
    public async Task RejectsTamperedReplayAndOversizePacksWithoutReplacingTheCache()
    {
        using var key = ECDsa.Create(ECCurve.NamedCurves.nistP256);
        var existing = new CompatibilityPackCacheEntry(8, "old", new DateTimeOffset(2026, 8, 22, 0, 0, 0, TimeSpan.Zero), Encoding.UTF8.GetBytes(ValidCatalog));
        var cache = new InMemoryCompatibilityPackCache(existing);
        var updater = new CompatibilityPackUpdater(key.ExportSubjectPublicKeyInfo(), new RecordingPackTransport(CreatePack(key, 8, "etag-8", tamperCatalog: true)), cache, () => new DateTimeOffset(2026, 8, 23, 0, 0, 0, TimeSpan.Zero));

        Assert.AreEqual(CompatibilityPackUpdateResult.Rejected, await updater.UpdateAsync(CancellationToken.None));
        Assert.AreSame(existing, cache.Current);

        updater = new CompatibilityPackUpdater(key.ExportSubjectPublicKeyInfo(), new RecordingPackTransport(CreatePack(key, 8, "etag-8")), cache, () => new DateTimeOffset(2026, 8, 23, 0, 0, 0, TimeSpan.Zero));
        Assert.AreEqual(CompatibilityPackUpdateResult.Rejected, await updater.UpdateAsync(CancellationToken.None));
        Assert.AreSame(existing, cache.Current);

        updater = new CompatibilityPackUpdater(key.ExportSubjectPublicKeyInfo(), new RecordingPackTransport(new byte[CompatibilityPackUpdater.MaximumPackBytes + 1]), cache, () => new DateTimeOffset(2026, 8, 23, 0, 0, 0, TimeSpan.Zero));
        Assert.AreEqual(CompatibilityPackUpdateResult.Rejected, await updater.UpdateAsync(CancellationToken.None));
        Assert.AreSame(existing, cache.Current);
    }

    [TestMethod]
    public async Task UsesEtagAndDoesNotFetchAgainBeforeTheTwentyFourHourPolicyExpires()
    {
        using var key = ECDsa.Create(ECCurve.NamedCurves.nistP256);
        var now = new DateTimeOffset(2026, 8, 23, 0, 0, 0, TimeSpan.Zero);
        var cache = new InMemoryCompatibilityPackCache(new CompatibilityPackCacheEntry(2, "etag-2", now.AddHours(-23), Encoding.UTF8.GetBytes(ValidCatalog)));
        var transport = new RecordingPackTransport(CreatePack(key, 3, "etag-3"));
        var updater = new CompatibilityPackUpdater(key.ExportSubjectPublicKeyInfo(), transport, cache, () => now);

        Assert.AreEqual(CompatibilityPackUpdateResult.NotDue, await updater.UpdateAsync(CancellationToken.None));
        Assert.IsNull(transport.ObservedEtag);

        cache.Current = cache.Current! with { UpdatedAt = now.AddHours(-24) };
        Assert.AreEqual(CompatibilityPackUpdateResult.Updated, await updater.UpdateAsync(CancellationToken.None));
        Assert.AreEqual("etag-2", transport.ObservedEtag);
    }

    [TestMethod]
    public async Task RefreshesAValidCacheTimestampWhenTheServerReturnsNotModified()
    {
        using var key = ECDsa.Create(ECCurve.NamedCurves.nistP256);
        var now = new DateTimeOffset(2026, 8, 23, 0, 0, 0, TimeSpan.Zero);
        var catalog = Encoding.UTF8.GetBytes(ValidCatalog);
        var existing = new CompatibilityPackCacheEntry(2, "etag-2", now.AddHours(-24), catalog);
        var cache = new InMemoryCompatibilityPackCache(existing);
        var transport = new RecordingPackTransport(Array.Empty<byte>(), statusCode: 304);
        var updater = new CompatibilityPackUpdater(key.ExportSubjectPublicKeyInfo(), transport, cache, () => now);

        Assert.AreEqual(CompatibilityPackUpdateResult.NotModified, await updater.UpdateAsync(CancellationToken.None));
        Assert.AreEqual(now, cache.Current!.UpdatedAt);
        Assert.AreEqual(existing.Sequence, cache.Current.Sequence);
        Assert.AreEqual(existing.ETag, cache.Current.ETag);
        CollectionAssert.AreEqual(existing.Catalog, cache.Current.Catalog);

        Assert.AreEqual(CompatibilityPackUpdateResult.NotDue, await updater.UpdateAsync(CancellationToken.None));
        Assert.AreEqual(1, transport.CallCount);
    }

    [TestMethod]
    public async Task RejectsPacksWhoseEntriesExceedTheTotalUncompressedBudget()
    {
        using var key = ECDsa.Create(ECCurve.NamedCurves.nistP256);
        var existing = new CompatibilityPackCacheEntry(8, "old", new DateTimeOffset(2026, 8, 22, 0, 0, 0, TimeSpan.Zero), Encoding.UTF8.GetBytes(ValidCatalog));
        var cache = new InMemoryCompatibilityPackCache(existing);
        var updater = new CompatibilityPackUpdater(
            key.ExportSubjectPublicKeyInfo(),
            new RecordingPackTransport(CreatePack(key, 9, "etag-9", padCatalogToPackLimit: true)),
            cache,
            () => new DateTimeOffset(2026, 8, 23, 0, 0, 0, TimeSpan.Zero));

        Assert.AreEqual(CompatibilityPackUpdateResult.Rejected, await updater.UpdateAsync(CancellationToken.None));
        Assert.AreSame(existing, cache.Current);
    }

    [TestMethod]
    public void BuildsStateAwareLocalStatusWithoutLeakingSensitiveFields()
    {
        var outcome = new RuntimeStateOutcome(HostRuntimeState.Visible, new CompatibilityDecision(SemanticCompatibility.Invalid, ProfileCompatibility.FallbackLocked, SafeDockPlacement.Fallback, CompatibilityFailureCode.UiaUnavailable), new DateTimeOffset(2026, 8, 23, 1, 2, 3, TimeSpan.Zero));

        var status = WindowsControlCommands.Status(outcome, runtimeRunning: true);

        Assert.AreEqual("runtime=running state=Visible placement=Fallback reason=UiaUnavailable", status);
        Assert.IsFalse(status.Contains("C:\\", StringComparison.Ordinal));
    }

    [TestMethod]
    public async Task ExportsOnlyUserRequestedRedactedDiagnosticEntries()
    {
        var report = new WindowsProbeReport("1", new DateTimeOffset(2026, 8, 23, 0, 0, 0, TimeSpan.Zero), "Windows", true,
            new WindowsProbeHost(new RectD(0, 0, 100, 100), true, 1, "build"), "path-token",
            [new UiaProbeNode(1, "ControlType.Text", "id", "class", new RectD(1, 2, 3, 4), 12, "name-token", UiaSemanticRoles.None, "private task title")], null);
        var destination = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N"), "diagnostic.zip");
        try
        {
            await WindowsDiagnosticExporter.ExportAsync(destination, report, new RuntimeStateOutcome(HostRuntimeState.Visible, new CompatibilityDecision(SemanticCompatibility.Valid, ProfileCompatibility.Validated, SafeDockPlacement.Titlebar, CompatibilityFailureCode.None), DateTimeOffset.UtcNow), CancellationToken.None);
            using var archive = ZipFile.OpenRead(destination);
            var content = await new StreamReader(archive.GetEntry("report.json")!.Open()).ReadToEndAsync();
            var summary = await new StreamReader(archive.GetEntry("summary.json")!.Open()).ReadToEndAsync();

            Assert.IsFalse(content.Contains("private task title", StringComparison.Ordinal));
            Assert.IsFalse(content.Contains("C:\\", StringComparison.Ordinal));
            Assert.IsFalse(content.Contains("Handle", StringComparison.Ordinal));
            StringAssert.Contains(summary, "Visible");
            Assert.AreEqual(2, archive.Entries.Count);
        }
        finally
        {
            var directory = Path.GetDirectoryName(destination)!;
            if (Directory.Exists(directory)) Directory.Delete(directory, recursive: true);
        }
    }

    [TestMethod]
    public void TrayPolicyOmitsTheUnsafeSafeDockToggle()
    {
        var state = new RuntimeStateOutcome(HostRuntimeState.Visible,
            new CompatibilityDecision(SemanticCompatibility.Invalid, ProfileCompatibility.FallbackLocked, SafeDockPlacement.Fallback, CompatibilityFailureCode.UiaUnavailable),
            DateTimeOffset.UtcNow);

        var actions = WindowsTrayActions.For(state);

        CollectionAssert.AreEquivalent(
            new[] { WindowsTrayAction.ShowStatus, WindowsTrayAction.ExportDiagnostics, WindowsTrayAction.Exit },
            actions.ToArray());
    }

    private const string ValidCatalog = "{\"schemaVersion\":2,\"profiles\":[{\"buildIdentities\":[],\"markerAliases\":{}}]}";

    private static byte[] CreatePack(ECDsa key, long sequence, string etag, bool tamperCatalog = false, bool padCatalogToPackLimit = false)
    {
        var catalog = Encoding.UTF8.GetBytes(ValidCatalog);
        if (padCatalogToPackLimit) catalog = Encoding.UTF8.GetBytes(ValidCatalog + new string(' ', CompatibilityPackUpdater.MaximumPackBytes - catalog.Length));
        var manifest = Encoding.UTF8.GetBytes(JsonSerializer.Serialize(new { sequence, etag, catalogSha256 = Convert.ToHexString(SHA256.HashData(catalog)).ToLowerInvariant() }));
        var signature = key.SignData(CompatibilityPackUpdater.SignaturePayload(manifest, catalog), HashAlgorithmName.SHA256);
        if (tamperCatalog) catalog[0] = (byte)'[';
        using var stream = new MemoryStream();
        using (var archive = new ZipArchive(stream, ZipArchiveMode.Create, leaveOpen: true))
        {
            Write(archive, "manifest.json", manifest);
            Write(archive, "selectors.json", catalog);
            Write(archive, "signature.sig", signature);
        }
        return stream.ToArray();
    }

    private static void Write(ZipArchive archive, string name, byte[] content)
    {
        using var entry = archive.CreateEntry(name).Open();
        entry.Write(content);
    }

    private sealed class RecordingPackTransport(byte[] response) : ICompatibilityPackTransport
    {
        private readonly int statusCode = 200;
        public string? ObservedEtag { get; private set; }
        public int CallCount { get; private set; }
        public ValueTask<CompatibilityPackResponse> GetAsync(string? etag, CancellationToken cancellationToken)
        {
            CallCount++;
            ObservedEtag = etag;
            return ValueTask.FromResult(new CompatibilityPackResponse(statusCode, "new-etag", response));
        }

        public RecordingPackTransport(byte[] response, int statusCode) : this(response) => this.statusCode = statusCode;
    }

    private sealed class InMemoryCompatibilityPackCache(CompatibilityPackCacheEntry? current = null) : ICompatibilityPackCache
    {
        public CompatibilityPackCacheEntry? Current { get; set; } = current;
        public ValueTask<CompatibilityPackCacheEntry?> LoadAsync(CancellationToken cancellationToken) => ValueTask.FromResult(Current);
        public ValueTask ReplaceAsync(CompatibilityPackCacheEntry entry, CancellationToken cancellationToken) { Current = entry; return ValueTask.CompletedTask; }
    }
}
