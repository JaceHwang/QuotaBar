namespace CodexUsageSidebar.Windows;

public sealed class ValidatedTitlebarCache
{
    private readonly object gate = new();
    private readonly Func<long> timestamp;
    private readonly long lifetimeTicks;
    private readonly long retentionTicks;
    private CacheEntry? entry;

    public ValidatedTitlebarCache(
        Func<long>? timestamp = null,
        long? timestampFrequency = null,
        TimeSpan? lifetime = null,
        TimeSpan? retentionLifetime = null)
    {
        this.timestamp = timestamp ?? System.Diagnostics.Stopwatch.GetTimestamp;
        var resolvedLifetime = lifetime ?? TimeSpan.FromSeconds(30);
        var resolvedRetention = retentionLifetime ?? TimeSpan.FromMinutes(5);
        var resolvedFrequency = timestampFrequency ?? System.Diagnostics.Stopwatch.Frequency;
        if (resolvedFrequency <= 0) throw new ArgumentOutOfRangeException(nameof(timestampFrequency));
        if (resolvedLifetime <= TimeSpan.Zero) throw new ArgumentOutOfRangeException(nameof(lifetime));
        if (resolvedRetention < resolvedLifetime) throw new ArgumentOutOfRangeException(nameof(retentionLifetime));
        lifetimeTicks = checked((long)Math.Ceiling(resolvedLifetime.TotalSeconds * resolvedFrequency));
        retentionTicks = checked((long)Math.Ceiling(resolvedRetention.TotalSeconds * resolvedFrequency));
    }

    public TitlebarSnapshot? TryGetRetained(HostWindowSnapshot host)
    {
        var key = CacheKey.For(host);
        lock (gate)
        {
            return entry is not null
                && entry.Key == key
                && timestamp() - entry.ValidatedAt < retentionTicks
                    ? entry.Snapshot
                    : null;
        }
    }

    public TitlebarSnapshot? TryGet(HostWindowSnapshot host)
    {
        var key = CacheKey.For(host);
        lock (gate)
        {
            return entry is not null
                && entry.Key == key
                && timestamp() - entry.ValidatedAt < lifetimeTicks
                    ? entry.Snapshot
                    : null;
        }
    }

    public void Store(HostWindowSnapshot host, TitlebarSnapshot snapshot)
    {
        lock (gate)
        {
            entry = new CacheEntry(CacheKey.For(host), snapshot, timestamp());
        }
    }

    public void Invalidate()
    {
        lock (gate)
        {
            entry = null;
        }
    }

    private sealed record CacheEntry(
        CacheKey Key,
        TitlebarSnapshot Snapshot,
        long ValidatedAt);

    private readonly record struct CacheKey(
        IntPtr Handle,
        CodexUsageSidebar.Core.RectD Bounds,
        double DpiScale,
        string BuildIdentity)
    {
        internal static CacheKey For(HostWindowSnapshot host) => new(
            host.Handle,
            host.Bounds,
            host.DpiScale,
            host.BuildIdentity);
    }
}
