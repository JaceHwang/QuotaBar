using System.Text.Json;
using System.Text.Json.Serialization;

namespace CodexUsageSidebar.Windows;

public static class RuntimeStateReader
{
    private static readonly JsonSerializerOptions Options = new() { Converters = { new JsonStringEnumConverter() } };

    public static async ValueTask<RuntimeStateOutcome?> LoadAsync(string path, CancellationToken cancellationToken)
    {
        if (!File.Exists(path)) return null;
        try
        {
            await using var stream = File.OpenRead(path);
            var outcome = await JsonSerializer.DeserializeAsync<RuntimeStateOutcome>(stream, Options, cancellationToken).ConfigureAwait(false);
            // The host writes every reconciliation. A historical file must not
            // masquerade as live diagnostics after a crash or a failed write.
            if (outcome?.Decision is null) return null;
            var age = DateTimeOffset.UtcNow - outcome.RecordedAt;
            return age >= TimeSpan.FromSeconds(-2) && age <= TimeSpan.FromSeconds(10)
                ? outcome : null;
        }
        catch (JsonException) { return null; }
        catch (IOException) { return null; }
        catch (UnauthorizedAccessException) { return null; }
    }
}
