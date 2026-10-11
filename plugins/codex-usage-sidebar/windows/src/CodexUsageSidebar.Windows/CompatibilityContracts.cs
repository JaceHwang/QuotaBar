namespace CodexUsageSidebar.Windows;

public enum SemanticCompatibility
{
    Unknown,
    Valid,
    Invalid,
}

public enum ProfileCompatibility
{
    Unknown,
    Validated,
    FallbackLocked,
    Invalid,
}

public enum SafeDockPlacement
{
    None,
    Titlebar,
    Fallback,
}

public enum CompatibilityFailureCode
{
    None,
    MissingCodexWindow,
    MissingQuotaSnapshot,
    UiaUnavailable,
    InvalidCaptionControls,
    MissingToolbar,
    AmbiguousToolbar,
    MissingTitle,
    AmbiguousTitle,
    MissingAnchor,
    AmbiguousAnchor,
    InvalidGeometry,
    NoCollisionFreeSlot,
    InvalidCatalog,
    HostNotForeground,
}

public sealed record CompatibilityDecision(
    SemanticCompatibility Semantic,
    ProfileCompatibility Profile,
    SafeDockPlacement Placement,
    CompatibilityFailureCode FailureCode);

public readonly record struct CompatibilitySize(double Width, double Height);

public enum CompatibilityPlacementAnchor
{
    TrailingEdge,
    LeadingEdge,
    Center,
}

public sealed record CompatibilityPreferences(
    bool FallbackLocked,
    CompatibilitySize FallbackSize,
    CompatibilityPlacementAnchor PlacementAnchor,
    PointD PlacementOffset);

public sealed record RuntimeStateOutcome(
    HostRuntimeState RuntimeState,
    CompatibilityDecision Decision,
    DateTimeOffset RecordedAt);

public interface IRuntimeStateStore
{
    ValueTask WriteAsync(RuntimeStateOutcome outcome, CancellationToken cancellationToken);
}
