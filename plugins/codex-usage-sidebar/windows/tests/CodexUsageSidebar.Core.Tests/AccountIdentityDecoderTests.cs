using CodexUsageSidebar.Core;

namespace CodexUsageSidebar.Core.Tests;

[TestClass]
public sealed class AccountIdentityDecoderTests
{
    [TestMethod]
    public void AccountFieldsTakePrecedenceOverProfileAliases()
    {
        var account = AccountIdentityDecoder.DecodeResponse("""
            {"result":{"account":{"name":"Account name","image_url":"https://example.com/account.png",
              "profile":{"displayName":"Profile name","avatarUrl":"https://example.com/profile.png"}}}}
            """);
        Assert.AreEqual("Account name", account.DisplayName);
        Assert.AreEqual(new Uri("https://example.com/account.png"), account.AvatarUrl);
    }
    [TestMethod]
    public void DecodesDisplayNameEmailAndAvatarFromAccountResponse()
    {
        var identity = AccountIdentityDecoder.DecodeResponse(
            File.ReadAllText(ContractPath("account", "read-response.json")));

        Assert.AreEqual("Jace", identity.DisplayName);
        Assert.AreEqual("jace@example.com", identity.Email);
        Assert.AreEqual("https://example.com/avatar.png", identity.AvatarUrl?.ToString());
        Assert.AreEqual("Jace", identity.PreferredName);
    }

    [TestMethod]
    public void FallsBackToEmailWhenDisplayNameIsMissing()
    {
        var identity = AccountIdentityDecoder.DecodeResponse(
            "{\"result\":{\"account\":{\"email\":\"jace@example.com\"}}}");

        Assert.AreEqual("jace@example.com", identity.PreferredName);
    }

    private static string ContractPath(params string[] parts) =>
        Path.Combine(new[] { AppContext.BaseDirectory, "contracts" }.Concat(parts).ToArray());
}
