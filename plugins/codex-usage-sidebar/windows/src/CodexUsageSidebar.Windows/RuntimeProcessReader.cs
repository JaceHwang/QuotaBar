using System.ComponentModel;
using System.Diagnostics;

namespace CodexUsageSidebar.Windows;

public sealed record RuntimeProcessIdentity(int ProcessId, DateTimeOffset StartedAt)
{
    public RuntimeStateOutcome? CurrentOutcome(RuntimeStateOutcome? outcome) =>
        outcome is not null && outcome.RecordedAt >= StartedAt ? outcome : null;
}

public static class RuntimeProcessReader
{
    public static RuntimeProcessIdentity? Find(string executablePath)
    {
        var expected = Path.GetFullPath(executablePath);
        var candidates = Process.GetProcessesByName(Path.GetFileNameWithoutExtension(expected));
        try
        {
            foreach (var process in candidates)
            {
                try
                {
                    if (!process.HasExited && process.MainModule?.FileName is { } actual
                        && string.Equals(Path.GetFullPath(actual), expected, StringComparison.OrdinalIgnoreCase))
                    {
                        return new RuntimeProcessIdentity(process.Id, process.StartTime.ToUniversalTime());
                    }
                }
                catch (Exception error) when (error is Win32Exception or InvalidOperationException or NotSupportedException)
                {
                    // A process may exit or become inaccessible during enumeration.
                }
            }
            return null;
        }
        finally
        {
            foreach (var process in candidates) process.Dispose();
        }
    }
}
