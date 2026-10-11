using System.Text.Json;

namespace CodexUsageSidebar.Core;

public static class TokenUsageDecoder
{
    public static TokenUsageSnapshot DecodeResponse(string json, DateTimeOffset? receivedAt = null)
    {
        using var document = JsonDocument.Parse(json);
        var root = document.RootElement;
        var timestamp = receivedAt ?? DateTimeOffset.Now;
        if (root.TryGetProperty("error", out var error))
        {
            var code = error.TryGetProperty("code", out var codeElement)
                && codeElement.ValueKind == JsonValueKind.Number
                && codeElement.TryGetInt32(out var parsedCode)
                    ? parsedCode
                    : 0;
            return Empty(timestamp, code == -32601
                ? TokenUsageAvailability.Unsupported
                : TokenUsageAvailability.Unavailable);
        }

        var container = root.TryGetProperty("result", out var result)
            ? result
            : root;
        if (container.ValueKind != JsonValueKind.Object)
        {
            return Empty(timestamp, TokenUsageAvailability.Unavailable);
        }

        var buckets = DecodeBuckets(container, out var bucketsValid);
        if (!bucketsValid)
        {
            return Empty(timestamp, TokenUsageAvailability.Unavailable);
        }
        var summary = DecodeSummary(container, out var summaryValid);
        if (!summaryValid) return Empty(timestamp, TokenUsageAvailability.Unavailable);
        return new TokenUsageSnapshot(
            timestamp,
            buckets,
            summary,
            TokenUsageAvailability.Available);
    }

    private static IReadOnlyList<TokenUsageDay> DecodeBuckets(JsonElement container, out bool valid)
    {
        valid = true;
        if (!container.TryGetProperty("dailyUsageBuckets", out var value)
            || value.ValueKind == JsonValueKind.Null)
        {
            return Array.Empty<TokenUsageDay>();
        }
        if (value.ValueKind != JsonValueKind.Array)
        {
            valid = false;
            return Array.Empty<TokenUsageDay>();
        }

        var buckets = new List<TokenUsageDay>();
        foreach (var item in value.EnumerateArray())
        {
            if (item.ValueKind != JsonValueKind.Object
                || !item.TryGetProperty("startDate", out var dateElement)
                || dateElement.ValueKind != JsonValueKind.String
                || !DateOnly.TryParseExact(
                    dateElement.GetString(),
                    "yyyy-MM-dd",
                    System.Globalization.CultureInfo.InvariantCulture,
                    System.Globalization.DateTimeStyles.None,
                    out var date)
                || !item.TryGetProperty("tokens", out var tokensElement)
                || tokensElement.ValueKind != JsonValueKind.Number
                || !tokensElement.TryGetInt64(out var tokens)
                || tokens < 0)
            {
                valid = false;
                return Array.Empty<TokenUsageDay>();
            }
            buckets.Add(new TokenUsageDay(date, tokens));
        }
        return buckets
            .GroupBy(bucket => bucket.Date)
            .Select(group => new TokenUsageDay(group.Key, group.Sum(bucket => bucket.Tokens)))
            .OrderBy(bucket => bucket.Date)
            .ToArray();
    }

    private static TokenUsageSummary? DecodeSummary(JsonElement container, out bool valid)
    {
        valid = true;
        if (!container.TryGetProperty("summary", out var value)
            || value.ValueKind == JsonValueKind.Null)
        {
            return null;
        }
        if (value.ValueKind != JsonValueKind.Object)
        {
            valid = false;
            return null;
        }
        foreach (var field in new[] { "lifetimeTokens", "peakDailyTokens", "longestRunningTurnSec", "currentStreakDays", "longestStreakDays" })
        {
            if (!value.TryGetProperty(field, out var property) || property.ValueKind == JsonValueKind.Null) continue;
            if (property.ValueKind != JsonValueKind.Number || !property.TryGetInt64(out var number)
                || number < 0 || (field is not ("lifetimeTokens" or "peakDailyTokens") && number > int.MaxValue))
            {
                valid = false;
                return null;
            }
        }

        return new TokenUsageSummary(
            OptionalNonNegativeInt64(value, "lifetimeTokens"),
            OptionalNonNegativeInt64(value, "peakDailyTokens"),
            OptionalNonNegativeInt(value, "longestRunningTurnSec"),
            OptionalNonNegativeInt(value, "currentStreakDays"),
            OptionalNonNegativeInt(value, "longestStreakDays"));
    }

    private static long? OptionalNonNegativeInt64(JsonElement value, string name) =>
        value.TryGetProperty(name, out var property)
        && property.ValueKind == JsonValueKind.Number
        && property.TryGetInt64(out var result)
        && result >= 0
            ? result
            : null;

    private static int? OptionalNonNegativeInt(JsonElement value, string name) =>
        OptionalNonNegativeInt64(value, name) is { } result
        && result <= int.MaxValue
            ? (int)result
            : null;

    private static TokenUsageSnapshot Empty(
        DateTimeOffset receivedAt,
        TokenUsageAvailability availability) =>
        new(receivedAt, Array.Empty<TokenUsageDay>(), null, availability);
}
