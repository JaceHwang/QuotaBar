namespace CodexUsageSidebar.Core;

public enum IndicatorPlacementMode { Automatic, Free, Locked }

public sealed record IndicatorManualPlacement(double NormalizedX, double NormalizedY)
{
    public static IndicatorManualPlacement Capture(RectD frame, RectD workArea) => new(
        Normalize(frame.X - workArea.X, workArea.Width - frame.Width),
        Normalize(frame.Y - workArea.Y, workArea.Height - frame.Height));

    public RectD Resolve(RectD workArea, double width, double height) => new(
        workArea.X + Math.Max(0, workArea.Width - width) * Clamp(NormalizedX),
        workArea.Y + Math.Max(0, workArea.Height - height) * Clamp(NormalizedY), width, height);

    private static double Normalize(double value, double range) => range > 0 ? Clamp(value / range) : 0;
    private static double Clamp(double value) => double.IsFinite(value) ? Math.Clamp(value, 0, 1) : 0;
}

public sealed class IndicatorPlacementPreferences
{
    public IndicatorPlacementMode Mode { get; set; }
    public string? ActiveDisplayId { get; set; }
    public Dictionary<string, IndicatorManualPlacement> Placements { get; set; } = new();

    public bool SwitchToFreeFallback(string displayId, RectD frame, RectD workArea)
    {
        if (Mode != IndicatorPlacementMode.Automatic) return false;
        Capture(displayId, frame, workArea);
        Mode = IndicatorPlacementMode.Free;
        return true;
    }

    public void Capture(string displayId, RectD frame, RectD workArea)
    {
        Placements[displayId] = IndicatorManualPlacement.Capture(frame, workArea);
        ActiveDisplayId = displayId;
    }

    public RectD Resolve(string displayId, RectD workArea, RectD automaticFrame) =>
        Mode != IndicatorPlacementMode.Automatic && Placements.TryGetValue(displayId, out var placement)
            ? placement.Resolve(workArea, automaticFrame.Width, automaticFrame.Height)
            : automaticFrame;
}

/// All coordinates are physical screen pixels. A moving window's client
/// coordinates must never be fed back as the next drag origin.
public sealed class IndicatorDragSession
{
    private (double X, double Y, RectD Frame, double Threshold)? origin;
    public bool IsDragging { get; private set; }
    public bool IsActive => origin.HasValue;

    public void Begin(double screenX, double screenY, RectD frame, double dpiScale = 1)
    {
        origin = (screenX, screenY, frame, 4 * (double.IsFinite(dpiScale) && dpiScale > 0 ? dpiScale : 1));
        IsDragging = false;
    }

    public RectD? Update(double screenX, double screenY, IndicatorPlacementMode mode)
    {
        if (origin is not { } start || mode != IndicatorPlacementMode.Free
            || !double.IsFinite(screenX) || !double.IsFinite(screenY)) return null;
        var dx = screenX - start.X;
        var dy = screenY - start.Y;
        if (!IsDragging && Math.Sqrt(dx * dx + dy * dy) < start.Threshold) return null;
        IsDragging = true;
        return start.Frame with { X = start.Frame.X + dx, Y = start.Frame.Y + dy };
    }

    public bool End()
    {
        var didDrag = IsDragging;
        origin = null;
        IsDragging = false;
        return didDrag;
    }
}
