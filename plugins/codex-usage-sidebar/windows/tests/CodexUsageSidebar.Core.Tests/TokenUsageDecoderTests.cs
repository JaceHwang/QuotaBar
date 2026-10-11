using CodexUsageSidebar.Core;

namespace CodexUsageSidebar.Core.Tests;

[TestClass]
public sealed class TokenUsageDecoderTests
{
    [TestMethod]
    [DataRow("{\"summary\":42}")]
    [DataRow("{\"summary\":{\"lifetimeTokens\":-1}}")]
    [DataRow("{\"summary\":{\"peakDailyTokens\":1.5}}")]
    [DataRow("{\"summary\":{\"currentStreakDays\":true}}")]
    public void RejectsInvalidSummaryInsteadOfPresentingTheResponseAsAvailable(string result)
    {
        var snapshot = TokenUsageDecoder.DecodeResponse("{\"result\":" + result + "}", DateTimeOffset.UnixEpoch);
        Assert.AreEqual(TokenUsageAvailability.Unavailable, snapshot.Availability);
    }

    [TestMethod]
    public void DecodesCurrentCycleDailyBucketsAndSummary()
    {
        var receivedAt = new DateTimeOffset(2026, 8, 22, 12, 0, 0, TimeSpan.Zero);
        var snapshot = TokenUsageDecoder.DecodeResponse(
            File.ReadAllText(ContractPath("usage", "read-response.json")),
            receivedAt);

        Assert.AreEqual(TokenUsageAvailability.Available, snapshot.Availability);
        Assert.AreEqual(2, snapshot.DailyBuckets.Count);
        Assert.AreEqual(new DateOnly(2026, 8, 20), snapshot.DailyBuckets[0].Date);
        Assert.AreEqual(166_026_932L, snapshot.DailyBuckets[0].Tokens);
        Assert.AreEqual(1_240_000_000L, snapshot.Summary?.LifetimeTokens);
        Assert.AreEqual(receivedAt, snapshot.ReceivedAt);
    }

    [TestMethod]
    public void ClassifiesMethodNotFoundAsUnsupported()
    {
        var snapshot = TokenUsageDecoder.DecodeResponse(
            "{\"id\":2,\"error\":{\"code\":-32601,\"message\":\"Method not found\"}}",
            DateTimeOffset.UnixEpoch);

        Assert.AreEqual(TokenUsageAvailability.Unsupported, snapshot.Availability);
        Assert.AreEqual(0, snapshot.DailyBuckets.Count);
    }

    [TestMethod]
    public void ClassifiesOtherRpcErrorsAsUnavailable()
    {
        var snapshot = TokenUsageDecoder.DecodeResponse(
            "{\"id\":2,\"error\":{\"code\":-32000,\"message\":\"temporary\"}}",
            DateTimeOffset.UnixEpoch);

        Assert.AreEqual(TokenUsageAvailability.Unavailable, snapshot.Availability);
    }

    [TestMethod]
    public void ClassifiesMalformedUsagePayloadAsUnavailable()
    {
        var snapshot = TokenUsageDecoder.DecodeResponse(
            "{\"id\":2,\"result\":{\"dailyUsageBuckets\":[{\"startDate\":\"not-a-date\",\"tokens\":1}]}}",
            DateTimeOffset.UnixEpoch);

        Assert.AreEqual(TokenUsageAvailability.Unavailable, snapshot.Availability);
        Assert.AreEqual(0, snapshot.DailyBuckets.Count);
    }

    private static string ContractPath(params string[] parts) =>
        Path.Combine(new[] { AppContext.BaseDirectory, "contracts" }.Concat(parts).ToArray());
}
