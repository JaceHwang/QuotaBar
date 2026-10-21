using System.Globalization;
using System.Text.Json;

namespace QuotaBar.Core;

public sealed record QuotaWindow(double UsedPercent, int RemainingPercent, DateTimeOffset ResetsAt, int? WindowMinutes);
public sealed record CreditBalance(bool HasCredits, bool Unlimited, string? Balance);
public sealed record BankCredit(string? Status, DateTimeOffset? GrantedAt, DateTimeOffset? ExpiresAt, string? Title, string? Description, string? Id=null, string? ResetType=null);
public sealed record BankSummary(int AvailableCount, IReadOnlyList<BankCredit>? Credits);
public sealed record QuotaSnapshot(QuotaWindow Primary, QuotaWindow? Secondary, string? Plan, CreditBalance? Credits, BankSummary? Bank, DateTimeOffset ReceivedAt) {
    public QuotaSnapshot MergeSupplementary(QuotaSnapshot? old) => this with {
        Plan=Plan??old?.Plan, Credits=Credits??old?.Credits, Bank=Bank??old?.Bank,
        Secondary=Secondary??old?.Secondary,
        Primary=Primary with { WindowMinutes=Primary.WindowMinutes??old?.Primary.WindowMinutes }
    };
}
public sealed record TokenDay(DateOnly Date, long Tokens);
public sealed record TokenUsage(IReadOnlyList<TokenDay> Days, long? LifetimeTokens, long? PeakDailyTokens, long? LongestTurnSeconds, long? CurrentStreakDays, long? LongestStreakDays);
public sealed record AccountIdentity(string? Name, string? Email, string? AvatarUrl) {
    public string? PreferredName => string.IsNullOrWhiteSpace(Name) ? Email : Name;
}

internal static class JsonValue {
    public static JsonElement Get(this JsonElement e,string key) => e.ValueKind==JsonValueKind.Object && e.TryGetProperty(key,out var v) ? v : default;
    public static string? String(this JsonElement e) => e.ValueKind==JsonValueKind.String ? e.GetString() : null;
    public static double? Number(this JsonElement e) => e.ValueKind==JsonValueKind.Number && e.TryGetDouble(out var v) && double.IsFinite(v) ? v : null;
    public static long? Integer(this JsonElement e) {
        if(e.ValueKind!=JsonValueKind.Number) return null;
        if(e.TryGetInt64(out var value)) return value;
        return e.TryGetDecimal(out var number) && decimal.Truncate(number)==number && number>=long.MinValue && number<=long.MaxValue ? (long)number : null;
    }
    public static DateTimeOffset? Timestamp(this JsonElement e) {
        if(e.Number() is not double t || t<=0 || t>253402300799) return null;
        return DateTimeOffset.UnixEpoch.AddSeconds(t);
    }
    public static bool Boolean(this JsonElement e) => e.ValueKind==JsonValueKind.True;
    public static bool HasValue(this JsonElement e) => e.ValueKind is not (JsonValueKind.Null or JsonValueKind.Undefined);
}

public static class QuotaDecoder {
    public static QuotaSnapshot Decode(string json,bool notification=false,DateTimeOffset? receivedAt=null) {
        try {
            using var doc=JsonDocument.Parse(json); var root=doc.RootElement;
            var container=notification ? root.Get("params") : root.Get("result");
            if(!container.HasValue()) container=root;
            var bucket=container.Get("rateLimitsByLimitId").Get("codex");
            if(!bucket.HasValue()) {
                bucket=container.Get("rateLimits");
                if(bucket.Get("limitId").String() is string id && id!="codex") throw new FormatException("Missing codex quota");
            }
            if(!bucket.HasValue() && container.Get("primary").HasValue()) bucket=container;
            var primary=Window(bucket.Get("primary")) ?? throw new FormatException("Missing valid primary quota");
            var secondary=Window(bucket.Get("secondary"));
            var credits=bucket.Get("credits");
            var balance=credits.ValueKind==JsonValueKind.Object ? new CreditBalance(credits.Get("hasCredits").Boolean(),credits.Get("unlimited").Boolean(),credits.Get("balance").String()) : null;
            var bank=container.Get("rateLimitResetCredits"); BankSummary? summary=null;
            if(bank.Get("availableCount").Integer() is long count && count<=int.MaxValue) {
                var list=bank.Get("credits");
                summary=new((int)Math.Max(0,count),list.ValueKind==JsonValueKind.Array ? list.EnumerateArray().Where(x=>x.ValueKind==JsonValueKind.Object).Select(x=>new BankCredit(x.Get("status").String(),x.Get("grantedAt").Timestamp(),x.Get("expiresAt").Timestamp(),x.Get("title").String(),x.Get("description").String(),x.Get("id").String(),x.Get("resetType").String())).ToArray() : null);
            }
            return new(primary,secondary,bucket.Get("planType").String(),balance,summary,receivedAt??DateTimeOffset.UtcNow);
        } catch(JsonException e) { throw new FormatException("Invalid quota JSON",e); }
    }
    private static QuotaWindow? Window(JsonElement w) {
        if(w.Get("usedPercent").Number() is not double used || w.Get("resetsAt").Timestamp() is not DateTimeOffset reset) return null;
        var duration=w.Get("windowDurationMins").Integer();
        return new(used,(int)Math.Round(Math.Clamp(100-used,0,100),MidpointRounding.AwayFromZero),reset,duration is >0 and <=int.MaxValue ? (int)duration : null);
    }
}

public static class TokenDecoder {
    public static TokenUsage Decode(string json) {
        try {
            using var doc=JsonDocument.Parse(json); var root=doc.RootElement;
            if(root.Get("error").HasValue()) throw new FormatException("Token usage unavailable");
            var result=root.Get("result"); if(!result.HasValue()) result=root;
            var buckets=result.Get("dailyUsageBuckets"); var days=new List<TokenDay>();
            if(buckets.HasValue()) {
                if(buckets.ValueKind!=JsonValueKind.Array) throw new FormatException("Invalid token buckets");
                foreach(var b in buckets.EnumerateArray()) {
                    if(!DateOnly.TryParseExact(b.Get("startDate").String(),"yyyy-MM-dd",CultureInfo.InvariantCulture,DateTimeStyles.None,out var date) || b.Get("tokens").Integer() is not long n || n<0) throw new FormatException("Invalid token day");
                    days.Add(new(date,n));
                }
            }
            var s=result.Get("summary");
            return new(days,Nonnegative(s.Get("lifetimeTokens")),Nonnegative(s.Get("peakDailyTokens")),Nonnegative(s.Get("longestRunningTurnSec")),Nonnegative(s.Get("currentStreakDays")),Nonnegative(s.Get("longestStreakDays")));
        } catch(JsonException e) { throw new FormatException("Invalid token JSON",e); }
    }
    private static long? Nonnegative(JsonElement v) => !v.HasValue() ? null : v.Integer() is long n && n>=0 ? n : throw new FormatException("Invalid token summary");
}

public static class AccountDecoder {
    public static AccountIdentity? Decode(JsonElement result) {
        var account=result.Get("account"); var profile=account.Get("profile");
        string? Find(params string[] keys) => keys.Select(k=>account.Get(k).String()??profile.Get(k).String()).FirstOrDefault(x=>!string.IsNullOrWhiteSpace(x));
        var identity=new AccountIdentity(Find("displayName","display_name","name"),Find("email"),Find("avatarUrl","avatarURL","avatar_url","imageUrl","image_url"));
        return identity.PreferredName is not null || identity.AvatarUrl is not null ? identity : null;
    }
}
