using System.Text.Json;

namespace CodexUsageSidebar.Core;

public static class AccountIdentityDecoder
{
    public static AccountIdentity DecodeResponse(string json)
    {
        using var document = JsonDocument.Parse(json);
        var root = document.RootElement;
        var account = root.TryGetProperty("result", out var result)
            && result.ValueKind == JsonValueKind.Object
            && result.TryGetProperty("account", out var accountValue)
                ? accountValue
                : default;
        if (account.ValueKind != JsonValueKind.Object)
        {
            return new AccountIdentity(null, null, null);
        }

        var profile = account.TryGetProperty("profile", out var profileValue)
            && profileValue.ValueKind == JsonValueKind.Object
                ? profileValue
                : default;
        var displayName = FirstString(account, profile, "displayName", "display_name", "name");
        var email = FirstString(account, profile, "email");
        var avatar = FirstString(
            account,
            profile,
            "avatarUrl",
            "avatarURL",
            "avatar_url",
            "imageUrl",
            "image_url");
        return new AccountIdentity(
            displayName,
            email,
            Uri.TryCreate(avatar, UriKind.Absolute, out var uri) ? uri : null);
    }

    private static string? FirstString(
        JsonElement account,
        JsonElement profile,
        params string[] names)
    {
        foreach (var name in names)
        {
            if (TryString(account, name) is { } accountValue) return accountValue;
        }
        foreach (var name in names)
        {
            if (TryString(profile, name) is { } profileValue) return profileValue;
        }
        return null;
    }

    private static string? TryString(JsonElement value, string name) =>
        value.ValueKind == JsonValueKind.Object
        && value.TryGetProperty(name, out var property)
        && property.ValueKind == JsonValueKind.String
            ? property.GetString()
            : null;
}
