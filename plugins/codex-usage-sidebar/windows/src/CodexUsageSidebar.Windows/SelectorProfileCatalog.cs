using System.Text.Json;
using System.Text;
using CodexUsageSidebar.Core;

namespace CodexUsageSidebar.Windows;

public sealed class SelectorProfileCatalog
{
    private const int SchemaVersion = 2;
    private const int HardMaximumWrapperDepth = 4;
    public const int MaximumCatalogBytes = 512 * 1024;
    public const int MaximumProfileCount = 32;
    public const int MaximumBuildIdentityCount = 16;
    public const int MaximumAliasesPerMarker = 16;
    public const int MaximumMarkerLength = 128;
    private static readonly HashSet<string> AllowedAliasMarkers = new(StringComparer.Ordinal)
    {
        "captionContainer", "captionButton", "toolbar", "toolbarPosition", "contentGroup",
        "titleGroup", "titleText", "rightPane", "rightPaneShrink", "rightToolbar",
        "rightToolbarOverflow", "composer", "openLocationEnd", "titleAction", "titleActionCursor",
    };

    private readonly IReadOnlyList<SelectorProfile> profiles;

    private SelectorProfileCatalog(IReadOnlyList<SelectorProfile> profiles) => this.profiles = profiles;

    public static SelectorProfileCatalog Default { get; } = new([SelectorProfile.Default]);

    internal IReadOnlyList<SelectorProfile> ProfilesFor(string buildIdentity)
    {
        var matching = profiles.Where(profile => profile.BuildIdentities.Contains(buildIdentity, StringComparer.Ordinal)).ToArray();
        return matching.Length == 0
            ? profiles
            : matching.Concat(profiles.Except(matching)).ToArray();
    }

    public static bool TryParse(string json, out SelectorProfileCatalog catalog)
    {
        catalog = Default;
        if (json is null || Encoding.UTF8.GetByteCount(json) > MaximumCatalogBytes) return false;
        try
        {
            using var document = JsonDocument.Parse(json);
            var root = document.RootElement;
            if (root.ValueKind != JsonValueKind.Object
                || !HasOnlyProperties(root, "schemaVersion", "profiles")
                || !root.TryGetProperty("schemaVersion", out var version)
                || version.ValueKind != JsonValueKind.Number
                || version.GetInt32() != SchemaVersion
                || !root.TryGetProperty("profiles", out var profileElements)
                || profileElements.ValueKind != JsonValueKind.Array
                || profileElements.GetArrayLength() == 0
                || profileElements.GetArrayLength() > MaximumProfileCount)
            {
                return false;
            }

            var parsed = new List<SelectorProfile>();
            foreach (var element in profileElements.EnumerateArray())
            {
                if (!TryParseProfile(element, out var profile)) return false;
                parsed.Add(profile);
            }
            catalog = new SelectorProfileCatalog(parsed);
            return true;
        }
        catch (JsonException)
        {
            return false;
        }
        catch (FormatException)
        {
            return false;
        }
    }

    internal static bool TryLoadRuntime(out SelectorProfileCatalog catalog)
    {
        var path = Path.Combine(AppContext.BaseDirectory, "selectors.json");
        if (!File.Exists(path))
        {
            catalog = Default;
            return true;
        }
        try
        {
            if (new FileInfo(path).Length > MaximumCatalogBytes)
            {
                catalog = Default;
                return false;
            }
            return TryParse(File.ReadAllText(path), out catalog);
        }
        catch (IOException)
        {
            catalog = Default;
            return false;
        }
        catch (UnauthorizedAccessException)
        {
            catalog = Default;
            return false;
        }
    }

    private static bool TryParseProfile(JsonElement element, out SelectorProfile profile)
    {
        profile = SelectorProfile.Default;
        if (element.ValueKind != JsonValueKind.Object
            || !HasOnlyProperties(element, "buildIdentities", "markerAliases", "maxWrapperDepth", "depthTolerance"))
        {
            return false;
        }

        var identities = Array.Empty<string>();
        if (element.TryGetProperty("buildIdentities", out var identityElements))
        {
            if (identityElements.ValueKind != JsonValueKind.Array) return false;
            if (identityElements.GetArrayLength() > MaximumBuildIdentityCount) return false;
            identities = identityElements.EnumerateArray()
                .Select(value => value.ValueKind == JsonValueKind.String ? value.GetString() : null)
                .ToArray()!;
            if (identities.Any(value => string.IsNullOrWhiteSpace(value) || value.Length > 200)) return false;
        }

        var aliases = new Dictionary<string, IReadOnlyList<string>>(StringComparer.Ordinal);
        if (element.TryGetProperty("markerAliases", out var aliasElements))
        {
            if (aliasElements.ValueKind != JsonValueKind.Object) return false;
            foreach (var property in aliasElements.EnumerateObject())
            {
                if (!AllowedAliasMarkers.Contains(property.Name)
                    || property.Name.Length > MaximumMarkerLength
                    || property.Value.ValueKind != JsonValueKind.Array
                    || property.Value.GetArrayLength() > MaximumAliasesPerMarker)
                {
                    return false;
                }
                var values = property.Value.EnumerateArray()
                    .Select(value => value.ValueKind == JsonValueKind.String ? value.GetString() : null)
                    .ToArray()!;
                if (values.Length == 0 || values.Any(value => !IsSafeClassToken(value))) return false;
                aliases[property.Name] = values!;
            }
        }

        var depth = 1;
        foreach (var name in new[] { "maxWrapperDepth", "depthTolerance" })
        {
            if (!element.TryGetProperty(name, out var value)) continue;
            if (value.ValueKind != JsonValueKind.Number || !value.TryGetInt32(out var configured)
                || configured < 0 || configured > HardMaximumWrapperDepth)
            {
                return false;
            }
            depth = Math.Max(depth, configured + 1);
        }

        profile = new SelectorProfile(identities, aliases, depth);
        return true;
    }

    private static bool HasOnlyProperties(JsonElement element, params string[] names) =>
        element.EnumerateObject().All(property => names.Contains(property.Name, StringComparer.Ordinal));

    private static bool IsSafeClassToken(string? value) => !string.IsNullOrWhiteSpace(value)
        && value.Length <= MaximumMarkerLength
        && value.All(character => char.IsLetterOrDigit(character)
            || character is '-' or '_' or '[' or ']' or ':' or '/');
}

internal sealed record SelectorProfile(
    IReadOnlyList<string> BuildIdentities,
    IReadOnlyDictionary<string, IReadOnlyList<string>> Aliases,
    int MaximumDepthDelta)
{
    internal static SelectorProfile Default { get; } = new(
        Array.Empty<string>(),
        new Dictionary<string, IReadOnlyList<string>>(StringComparer.Ordinal),
        3);

    internal bool HasMarker(string className, string marker, string canonicalTokens)
    {
        var tokens = className.Split(' ', StringSplitOptions.RemoveEmptyEntries).ToHashSet(StringComparer.Ordinal);
        if (canonicalTokens.Split(' ', StringSplitOptions.RemoveEmptyEntries).All(tokens.Contains)) return true;
        return Aliases.TryGetValue(marker, out var aliases) && aliases.Any(tokens.Contains);
    }
}

public sealed class InvalidSelectorCatalogException : Exception
{
    internal InvalidSelectorCatalogException() : base("selectors.json is not a valid schema-v2 selector catalog.") { }
}

internal static class AdaptiveTitlebarResolver
{
    private static readonly string[] RequiredCaptionButtonIds = ["view_1", "view_2", "view_3", "view_4"];

    internal static TitlebarSnapshot? TryResolve(
        double dpiScale,
        RectD hostBounds,
        IReadOnlyList<UiaStructureNode> nodes,
        SelectorProfile profile)
    {
        if (!double.IsFinite(dpiScale) || dpiScale <= 0 || !IsUsable(hostBounds)) return null;

        var containers = nodes.Where(node => node.ControlType == "ControlType.Pane"
            && node.AutomationId.Length == 0
            && profile.HasMarker(node.ClassName, "captionContainer", "ChromeNodeCaptionButtonContainer")).ToArray();
        if (containers.Length != 1) return null;
        var container = containers[0];
        var titlebarBottom = hostBounds.Y + Math.Min(64 * dpiScale, hostBounds.Height);
        if (!Contains(hostBounds, container.Bounds)
            || container.Bounds.Y < hostBounds.Y - (2 * dpiScale)
            || container.Bounds.Bottom > titlebarBottom) return null;

        var captionBounds = Expand(container.Bounds, 2 * dpiScale);
        foreach (var automationId in RequiredCaptionButtonIds)
        {
            var matches = nodes.Where(node => node.ControlType == "ControlType.Button"
                && node.AutomationId == automationId
                && profile.HasMarker(node.ClassName, "captionButton", "ChromeNodeCaptionButton")
                && IsDescendant(container, node, profile)
                && Contains(captionBounds, node.Bounds)).ToArray();
            if (matches.Length != 1) return null;
        }

        var toolbars = nodes.Where(node => node.ControlType == "ControlType.Group"
            && profile.HasMarker(node.ClassName, "toolbar", "fixed z-30 flex h-toolbar")
            && profile.HasMarker(node.ClassName, "toolbarPosition", "top-toolbar-sm")
            && Contains(hostBounds, node.Bounds)).ToArray();
        if (toolbars.Length != 1) return null;
        var toolbar = toolbars[0];

        var contentGroups = nodes.Where(node => node.ControlType == "ControlType.Group"
            && profile.HasMarker(node.ClassName, "contentGroup", "flex h-full min-w-0 flex-1")
            && !profile.HasMarker(node.ClassName, "rightToolbar", "hide-scrollbar flex h-full min-w-0 flex-1")
            && IsDescendant(toolbar, node, profile)
            && Contains(toolbar.Bounds, node.Bounds)).ToArray();
        if (contentGroups.Length != 1) return null;
        var content = contentGroups[0];

        var titleGroups = nodes.Where(node => node.ControlType == "ControlType.Group"
            && profile.HasMarker(node.ClassName, "titleGroup", "text-md flex min-w-0 items-center")
            && IsDescendant(content, node, profile)
            && Contains(content.Bounds, node.Bounds)).ToArray();
        var titleBounds = titleGroups.Length switch
        {
            0 => TryResolveTitleChildren(nodes, content, profile, dpiScale),
            1 => TryResolveTitleChildren(nodes, titleGroups[0], profile, dpiScale),
            _ => null,
        };
        if (titleBounds is null) return null;

        var anchors = nodes.Where(node => node.ControlType == "ControlType.Button"
            && IsToolbarButton(node, profile)
            && (profile.HasMarker(node.ClassName, "openLocationEnd", "rounded-e-none")
                || profile.HasMarker(node.ClassName, "composerSquare", "aspect-square"))
            && IsDescendant(content, node, profile)
            && Contains(content.Bounds, node.Bounds)
            && node.Bounds.X >= titleBounds.Value.Right
            && IsAligned(node.Bounds, titleBounds.Value, dpiScale)).OrderBy(node => node.Bounds.X).ToArray();
        if (anchors.Length == 0) return null;
        var anchor = anchors[0];
        var obstacleRegion = anchor.ClassName.Split(' ').Contains("button-toolbar")
            ? toolbar.Bounds : content.Bounds;

        var obstacles = nodes.Where(node => node.ControlType == "ControlType.Button"
            && IsToolbarButton(node, profile)
            && node.Bounds.X >= anchor.Bounds.X
            && Contains(obstacleRegion, node.Bounds)).OrderBy(node => node.Bounds.X).Select(node => node.Bounds).ToArray();
        if (obstacles.Length == 0 || obstacles[0] != anchor.Bounds) return null;

        var rightPanes = nodes.Where(node => node.ControlType == "ControlType.Group"
            && profile.HasMarker(node.ClassName, "rightPane", "relative z-[41] h-full")
            && profile.HasMarker(node.ClassName, "rightPaneShrink", "min-w-0 shrink-0 overflow-visible")
            && Contains(hostBounds, node.Bounds)).ToArray();
        if (rightPanes.Length > 1) return null;

        var rightToolbarBounds = default(RectD);
        IReadOnlyList<RectD> rightObstacles = Array.Empty<RectD>();
        if (rightPanes.Length == 1)
        {
            var rightPane = rightPanes[0];
            var rightToolbars = nodes.Where(node => node.ControlType == "ControlType.Group"
                && profile.HasMarker(node.ClassName, "rightToolbar", "hide-scrollbar flex h-full min-w-0 flex-1")
                && profile.HasMarker(node.ClassName, "rightToolbarOverflow", "overflow-x-auto overflow-y-hidden")
                && Contains(rightPane.Bounds, node.Bounds)
                && Contains(toolbar.Bounds, node.Bounds)).ToArray();
            if (rightToolbars.Length != 1) return null;
            var rightToolbar = rightToolbars[0];
            var aligned = nodes.Where(node => node.ControlType == "ControlType.Button"
                && profile.HasMarker(node.ClassName, "composer", "h-token-button-composer")
                && profile.HasMarker(node.ClassName, "composerSquare", "aspect-square")
                && IsAtMostDepthBelow(rightToolbar, node, profile)
                && Contains(rightPane.Bounds, node.Bounds)
                && IsAligned(node.Bounds, anchor.Bounds, dpiScale)).OrderBy(node => node.Bounds.X).ToArray();
            if (aligned.Length == 0) return null;
            rightToolbarBounds = rightToolbar.Bounds;
            rightObstacles = aligned.Select(node => node.Bounds).ToArray();
        }

        var allInteractive = nodes.Where(node => DiagnosticTitlebarScope.IsInteractiveControlType(node.ControlType)
            && IsUsable(node.Bounds) && node.Bounds.Width <= 420 * dpiScale && node.Bounds.Height <= 64 * dpiScale
            && node.Bounds.X >= toolbar.Bounds.X && node.Bounds.Right <= toolbar.Bounds.Right
            && node.Bounds.Y < anchor.Bounds.Bottom && node.Bounds.Bottom > anchor.Bounds.Y)
            .Select(node => node.Bounds).Distinct().ToArray();
        return new TitlebarSnapshot(anchor.Bounds.X, obstacles, toolbar.Bounds, anchor.Bounds,
            titleBounds.Value, rightToolbarBounds, rightObstacles, allInteractive);
    }

    private static RectD? TryResolveTitleChildren(
        IReadOnlyList<UiaStructureNode> nodes, UiaStructureNode parent, SelectorProfile profile, double dpiScale)
    {
        var bounds = Expand(parent.Bounds, 2 * dpiScale);
        var titleTexts = nodes.Where(node => node.ControlType == "ControlType.Group"
            && profile.HasMarker(node.ClassName, "titleText", "max-w-[320px] min-w-0 truncate")
            && IsDescendant(parent, node, profile) && Contains(bounds, node.Bounds)).ToArray();
        if (titleTexts.Length != 1) return null;
        var title = titleTexts[0];
        var leading = nodes.Where(node => node.ControlType == "ControlType.Button"
            && IsToolbarButton(node, profile)
            && profile.HasMarker(node.ClassName, "composerSquare", "aspect-square")
            && IsDescendant(parent, node, profile) && Contains(bounds, node.Bounds)
            && node.Bounds.Right <= title.Bounds.X && title.Bounds.X - node.Bounds.Right <= 4 * dpiScale).ToArray();
        var clickableTitles = nodes.Where(node => node.ControlType == "ControlType.Button"
            && profile.HasMarker(node.ClassName, "clickableTitle", "text-start truncate leading-6")
            && IsDescendant(title, node, profile)
            && Contains(Expand(title.Bounds, 2 * dpiScale), node.Bounds)).ToArray();
        if (leading.Length == 1 && clickableTitles.Length == 1
            && leading[0].ClassName.Split(' ').Contains("button-toolbar"))
        {
            return Union(leading[0].Bounds, title.Bounds, clickableTitles[0].Bounds);
        }
        var actions = nodes.Where(node => node.ControlType == "ControlType.Button"
            && profile.HasMarker(node.ClassName, "titleAction", "rounded-full")
            && profile.HasMarker(node.ClassName, "titleActionCursor", "cursor-interaction")
            && !profile.HasMarker(node.ClassName, "composer", "h-token-button-composer")
            && IsDescendant(parent, node, profile) && Contains(bounds, node.Bounds)
            && node.Bounds.X >= title.Bounds.Right - dpiScale && node.Bounds.X - title.Bounds.Right <= 2 * dpiScale).ToArray();
        if (leading.Length != 1 || actions.Length != 1
            || leading[0].Bounds.Right > title.Bounds.Right || title.Bounds.Right > actions[0].Bounds.Right) return null;
        return Union(leading[0].Bounds, title.Bounds, actions[0].Bounds);
    }

    private static bool IsToolbarButton(UiaStructureNode node, SelectorProfile profile) =>
        profile.HasMarker(node.ClassName, "composer", "h-token-button-composer")
        || node.ClassName.Split(' ', StringSplitOptions.RemoveEmptyEntries).Contains("button-toolbar");

    private static bool IsDescendant(UiaStructureNode parent, UiaStructureNode child, SelectorProfile profile) =>
        child.Depth > parent.Depth && child.Depth - parent.Depth <= profile.MaximumDepthDelta;

    private static bool IsAtMostDepthBelow(UiaStructureNode parent, UiaStructureNode child, SelectorProfile profile) =>
        child.Depth >= parent.Depth && child.Depth - parent.Depth <= profile.MaximumDepthDelta;

    private static bool IsAligned(RectD first, RectD second, double dpiScale) =>
        Math.Abs(first.Y - second.Y) <= 2 * dpiScale && Math.Abs(first.Height - second.Height) <= 2 * dpiScale;

    private static bool IsUsable(RectD bounds) => double.IsFinite(bounds.X) && double.IsFinite(bounds.Y)
        && double.IsFinite(bounds.Width) && double.IsFinite(bounds.Height) && double.IsFinite(bounds.Right)
        && double.IsFinite(bounds.Bottom) && bounds.Width > 0 && bounds.Height > 0;

    private static bool Contains(RectD container, RectD child) => IsUsable(container) && IsUsable(child)
        && child.X >= container.X && child.Y >= container.Y
        && child.Right <= container.Right && child.Bottom <= container.Bottom;

    private static RectD Expand(RectD bounds, double amount) => new(
        bounds.X - amount, bounds.Y - amount, bounds.Width + (2 * amount), bounds.Height + (2 * amount));

    private static RectD Union(params RectD[] bounds)
    {
        var left = bounds.Min(item => item.X);
        var top = bounds.Min(item => item.Y);
        var right = bounds.Max(item => item.Right);
        var bottom = bounds.Max(item => item.Bottom);
        return new RectD(left, top, right - left, bottom - top);
    }
}
