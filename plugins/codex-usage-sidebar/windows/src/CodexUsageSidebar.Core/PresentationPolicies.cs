namespace CodexUsageSidebar.Core;

public enum DisplayLanguage
{
    SimplifiedChinese,
    TraditionalChinese,
    English,
}

public enum DisplayLanguageSource
{
    Configuration,
    Process,
    Preferences,
    System,
}

public readonly record struct ResolvedDisplayLanguage(
    DisplayLanguage Language,
    DisplayLanguageSource Source);

public static class LanguageResolver
{
    public static DisplayLanguage Resolve(string? localeIdentifier)
    {
        var normalized = (localeIdentifier ?? string.Empty).Replace('_', '-').ToLowerInvariant();
        if (!normalized.StartsWith("zh", StringComparison.Ordinal))
        {
            return DisplayLanguage.English;
        }
        var components = normalized.Split('-', StringSplitOptions.RemoveEmptyEntries);
        if (components.Contains("hant")) return DisplayLanguage.TraditionalChinese;
        if (components.Contains("hans")) return DisplayLanguage.SimplifiedChinese;
        return components.Any(component => component is "tw" or "hk" or "mo")
            ? DisplayLanguage.TraditionalChinese
            : DisplayLanguage.SimplifiedChinese;
    }

    public static ResolvedDisplayLanguage? Resolve(
        string? configurationLocale = null,
        string? processLocale = null,
        string? preferencesLocale = null,
        string? systemLocale = null)
    {
        foreach (var (locale, source) in new[]
        {
            (configurationLocale, DisplayLanguageSource.Configuration),
            (processLocale, DisplayLanguageSource.Process),
            (preferencesLocale, DisplayLanguageSource.Preferences),
            (systemLocale, DisplayLanguageSource.System),
        })
        {
            if (string.IsNullOrWhiteSpace(locale))
            {
                continue;
            }
            return new ResolvedDisplayLanguage(Resolve(locale), source);
        }
        return null;
    }
}

public static class CodexConfigurationLanguageParser
{
    public static string? LocaleIdentifier(string contents)
    {
        string? section = null;
        foreach (var rawLine in contents.Split(["\r\n", "\n"], StringSplitOptions.None))
        {
            var line = StripInlineComment(rawLine).Trim();
            if (line.StartsWith("[", StringComparison.Ordinal)
                && line.EndsWith("]", StringComparison.Ordinal))
            {
                section = line[1..^1].Trim();
                continue;
            }
            if (section is not null && section != "desktop")
            {
                continue;
            }
            var parts = line.Split('=', 2);
            if (parts.Length != 2
                || parts[0].Trim() != "localeOverride")
            {
                continue;
            }

            var value = parts[1].Trim();
            if (value.Length < 2
                || (value[0] != '"' && value[0] != '\'')
                || value[^1] != value[0])
            {
                return null;
            }
            var locale = value[1..^1].Trim();
            return locale.Length == 0 ? null : locale;
        }
        return null;
    }

    private static string StripInlineComment(string line)
    {
        char? quote = null;
        var escaped = false;
        for (var index = 0; index < line.Length; index++)
        {
            var character = line[index];
            if (quote == '"' && character == '\\' && !escaped)
            {
                escaped = true;
                continue;
            }
            if (character is '"' or '\'')
            {
                if (quote == character && !escaped)
                {
                    quote = null;
                }
                else if (quote is null)
                {
                    quote = character;
                }
            }
            else if (character == '#' && quote is null)
            {
                return line[..index];
            }
            escaped = false;
        }
        return line;
    }
}

public sealed class RuntimeLanguageState
{
    public RuntimeLanguageState(DisplayLanguage initial = DisplayLanguage.English)
    {
        Language = initial;
    }

    public DisplayLanguage Language { get; private set; }
    public DisplayLanguageSource? Source { get; private set; }

    public bool Apply(ResolvedDisplayLanguage? resolved)
    {
        if (resolved is null)
        {
            return false;
        }
        var changed = Language != resolved.Value.Language;
        Language = resolved.Value.Language;
        Source = resolved.Value.Source;
        return changed;
    }
}

public readonly record struct RelativeIntervalSegment(string Text, bool IsEmphasized);

public static class RelativeIntervalFormatter
{
    public static IReadOnlyList<RelativeIntervalSegment> Format(TimeSpan interval, DisplayLanguage language)
    {
        var value = interval < TimeSpan.Zero ? TimeSpan.Zero : interval;
        var totalHours = (int)Math.Floor(value.TotalHours);
        var days = totalHours / 24;
        var hours = totalHours % 24;
        var dayUnit = language switch
        {
            DisplayLanguage.SimplifiedChinese => "天",
            DisplayLanguage.TraditionalChinese => "天",
            _ => "d",
        };
        var hourUnit = language switch
        {
            DisplayLanguage.SimplifiedChinese => "小时",
            DisplayLanguage.TraditionalChinese => "小時",
            _ => "h",
        };
        return new[]
        {
            new RelativeIntervalSegment(days.ToString(System.Globalization.CultureInfo.InvariantCulture), true),
            new RelativeIntervalSegment(dayUnit, false),
            new RelativeIntervalSegment(hours.ToString(System.Globalization.CultureInfo.InvariantCulture), true),
            new RelativeIntervalSegment(hourUnit, false),
        };
    }
}

public readonly record struct HsbColor(double Hue, double Saturation, double Brightness);

public static class QuotaColorScale
{
    private static readonly HsbColor Green = new(0.36, 0.78, 0.82);
    private static readonly HsbColor Orange = new(0.078, 0.96, 1);
    private static readonly HsbColor Red = new(0, 0.86, 1);
    private static readonly HsbColor CriticalRed = new(0, 0.96, 0.76);

    public static HsbColor ForRemainingPercent(int remainingPercent)
    {
        var value = Math.Clamp(remainingPercent, 0, 100);
        if (value >= 49) return Interpolate(Orange, Green, (value - 49d) / 51d);
        if (value >= 10) return Interpolate(Red, Orange, (value - 10d) / 39d);
        return Interpolate(CriticalRed, Red, value / 10d);
    }

    private static HsbColor Interpolate(HsbColor start, HsbColor end, double amount)
    {
        var value = Math.Clamp(amount, 0, 1);
        return new HsbColor(
            start.Hue + ((end.Hue - start.Hue) * value),
            start.Saturation + ((end.Saturation - start.Saturation) * value),
            start.Brightness + ((end.Brightness - start.Brightness) * value));
    }
}

public static class IndicatorHitTestPolicy
{
    public static byte BackgroundAlpha(bool highlighted) => highlighted ? (byte)18 : (byte)1;
}

public enum IndicatorClickAction
{
    None,
    ToggleDetails,
    SwitchToAutomaticPlacement,
}

public static class IndicatorClickPolicy
{
    public static IndicatorClickAction Resolve(int clickCount, bool dragged)
    {
        if (dragged || clickCount <= 0) return IndicatorClickAction.None;
        return clickCount == 2
            ? IndicatorClickAction.SwitchToAutomaticPlacement
            : IndicatorClickAction.ToggleDetails;
    }
}

public static class QuotaDetailLockCopy
{
    public static string Label(DisplayLanguage language, bool isLockedOpen) => (language, isLockedOpen) switch
    {
        (DisplayLanguage.SimplifiedChinese, false) => "固定浮窗",
        (DisplayLanguage.SimplifiedChinese, true) => "取消固定浮窗",
        (DisplayLanguage.TraditionalChinese, false) => "固定浮窗",
        (DisplayLanguage.TraditionalChinese, true) => "取消固定浮窗",
        (DisplayLanguage.English, false) => "Keep popover open",
        _ => "Stop keeping popover open",
    };
}

public readonly record struct DetailInteractionState(
    bool IsPinned,
    bool IsPointerInside,
    bool SuppressHoverUntilExit,
    bool IsLockedOpen)
{
    public static DetailInteractionState Initial => new(false, false, false, false);
    public bool ShouldShowDetail => IsLockedOpen || IsPinned || (IsPointerInside && !SuppressHoverUntilExit);

    public DetailInteractionState PointerChanged(bool inside) =>
        this with { IsPointerInside = inside, SuppressHoverUntilExit = inside && SuppressHoverUntilExit };

    public DetailInteractionState PointerPressed(bool insideOverlay, bool insideMenu) =>
        insideOverlay || insideMenu
            ? this
            : this with { IsPinned = false, IsPointerInside = false, SuppressHoverUntilExit = false };

    public DetailInteractionState TogglePinned(bool pointerInside) => IsPinned
        ? this with { IsPinned = false, IsPointerInside = pointerInside, SuppressHoverUntilExit = pointerInside }
        : this with { IsPinned = true, IsPointerInside = pointerInside, SuppressHoverUntilExit = false };

    public DetailInteractionState ToggleLockedOpen(bool pointerInside) => IsLockedOpen
        ? this with { IsLockedOpen = false, IsPointerInside = pointerInside, SuppressHoverUntilExit = false }
        : this with { IsLockedOpen = true, IsPinned = false, IsPointerInside = pointerInside, SuppressHoverUntilExit = false };
}

public enum SnapshotFreshness { Fresh, Dimmed, Hidden }

public static class RefreshPolicy
{
    public static TimeSpan Interval(bool isHostForeground) => TimeSpan.FromSeconds(isHostForeground ? 1 : 5);

    public static SnapshotFreshness Freshness(DateTimeOffset receivedAt, DateTimeOffset now)
    {
        var age = now - receivedAt;
        if (age >= TimeSpan.FromSeconds(300)) return SnapshotFreshness.Hidden;
        if (age >= TimeSpan.FromSeconds(120)) return SnapshotFreshness.Dimmed;
        return SnapshotFreshness.Fresh;
    }
}
