namespace CodexUsageSidebar.Core;

public readonly record struct RectD(double X, double Y, double Width, double Height)
{
    public double Right => X + Width;
    public double Bottom => Y + Height;
}

public enum PlacementSurface { Content, RightToolbar }

public readonly record struct PlacementResult(PlacementSurface Surface, RectD Frame);

public static class PlacementResolver
{
    public static (PlacementResult Placement, bool SwitchToFree)? ResolveAutomatic(
        RectD hostBounds, RectD toolbarBounds, RectD anchorBounds, RectD titleBounds,
        double indicatorWidth, double dpiScale, IReadOnlyList<RectD> interactiveObstacles)
    {
        var interactive = interactiveObstacles.Append(anchorBounds).ToArray();
        var fallback = ResolveDefaultFallback(hostBounds, toolbarBounds, anchorBounds,
            indicatorWidth, dpiScale, interactive);
        if (fallback is null || !IsUsable(titleBounds) || !Contains(toolbarBounds, titleBounds)) return null;
        var gap = 8 * dpiScale;
        var obstacles = interactive.Append(titleBounds).ToArray();
        var minimumX = Math.Max(toolbarBounds.X, hostBounds.X + gap);
        var maximumRight = Math.Min(toolbarBounds.Right, hostBounds.Right - gap);
        var preferred = fallback.Value.Placement.Frame with
        {
            X = Math.Clamp(anchorBounds.X - gap - indicatorWidth,
                hostBounds.X + gap, hostBounds.Right - indicatorWidth - gap)
        };
        bool Fits(RectD frame) => frame.X >= minimumX && frame.Right <= maximumRight
            && !IntersectsAny(frame, obstacles, gap);
        if (Fits(preferred)) return (new(PlacementSurface.Content, preferred), false);
        if (Fits(fallback.Value.Placement.Frame)) return (fallback.Value.Placement, false);
        var edges = obstacles.Where(obstacle => IsUsable(obstacle)
                && obstacle.Bottom > preferred.Y && obstacle.Y < preferred.Bottom)
            .Select(obstacle => obstacle.X - gap).Append(maximumRight).Distinct().OrderByDescending(x => x);
        foreach (var edge in edges)
        {
            var frame = preferred with { X = edge - indicatorWidth };
            if (Fits(frame)) return (new(PlacementSurface.Content, frame), false);
        }
        return fallback;
    }

    public static (PlacementResult Placement, bool SwitchToFree)? ResolveDefaultFallback(
        RectD hostBounds, RectD toolbarBounds, RectD anchorBounds, double indicatorWidth,
        double dpiScale, IReadOnlyList<RectD> interactiveObstacles)
    {
        if (!IsUsable(hostBounds) || !IsUsable(toolbarBounds) || !IsUsable(anchorBounds)
            || !Contains(hostBounds, toolbarBounds) || !Contains(toolbarBounds, anchorBounds)
            || !double.IsFinite(dpiScale) || dpiScale <= 0
            || !double.IsFinite(indicatorWidth) || indicatorWidth <= 0
            || indicatorWidth > hostBounds.Width - 16 * dpiScale) return null;
        var frame = new RectD(Math.Max(hostBounds.X + 8 * dpiScale,
            hostBounds.Right - 176 * dpiScale - indicatorWidth), anchorBounds.Y, indicatorWidth, anchorBounds.Height);
        return (new PlacementResult(PlacementSurface.Content, frame),
            IntersectsAny(frame, interactiveObstacles, 8 * dpiScale));
    }

    public static PlacementResult? ResolveResponsive(
        RectD toolbarBounds,
        RectD openLocationBounds,
        RectD titleBounds,
        double indicatorWidth,
        double gap,
        IReadOnlyList<RectD> localObstacles,
        RectD rightToolbarBounds,
        IReadOnlyList<RectD> rightObstacles,
        double? rightGap = null)
    {
        var fallbackGap = rightGap ?? gap;
        if (!IsUsable(toolbarBounds)
            || !IsUsable(openLocationBounds)
            || !IsUsable(titleBounds)
            || !double.IsFinite(indicatorWidth)
            || indicatorWidth <= 0
            || !double.IsFinite(gap)
            || gap < 0
            || !double.IsFinite(fallbackGap)
            || fallbackGap < 0
            || !Contains(toolbarBounds, openLocationBounds)
            || !Contains(toolbarBounds, titleBounds))
        {
            return null;
        }

        // Keep the indicator in the middle titlebar whenever the title has
        // enough room. The right page is only the overflow fallback when the
        // middle titlebar cannot contain a collision-free frame.
        var local = new RectD(
            openLocationBounds.X - gap - indicatorWidth,
            openLocationBounds.Y,
            indicatorWidth,
            openLocationBounds.Height);
        var candidates = localObstacles
            .Where(obstacle => IsUsable(obstacle)
                && local.Y < obstacle.Bottom && local.Bottom > obstacle.Y)
            .Select(obstacle => obstacle.X - gap - indicatorWidth)
            .Append(local.X)
            .Where(x => x <= local.X)
            .Distinct()
            .OrderByDescending(x => x);
        foreach (var x in candidates)
        {
            var candidate = local with { X = x };
            if (Contains(toolbarBounds, candidate)
                && candidate.X >= titleBounds.Right + gap
                && !IntersectsAny(candidate, localObstacles, gap))
            {
                return new PlacementResult(PlacementSurface.Content, candidate);
            }
        }

        if (IsUsable(rightToolbarBounds)
            && rightObstacles.Count > 0
            && Contains(toolbarBounds, rightToolbarBounds)
            && rightObstacles.All(IsUsable))
        {
            var trailingObstacle = rightObstacles.OrderBy(obstacle => obstacle.X).First();
            var fallback = new RectD(
                trailingObstacle.X - fallbackGap - indicatorWidth,
                openLocationBounds.Y,
                indicatorWidth,
                openLocationBounds.Height);
            if (Contains(rightToolbarBounds, fallback)
                && !IntersectsAny(fallback, rightObstacles, fallbackGap))
            {
                return new PlacementResult(PlacementSurface.RightToolbar, fallback);
            }
        }
        return null;
    }

    private static bool IntersectsAny(RectD candidate, IReadOnlyList<RectD> obstacles, double gap) =>
        obstacles.Any(obstacle => IsUsable(obstacle)
            && candidate.X < obstacle.Right + gap
            && candidate.Right > obstacle.X - gap
            && candidate.Y < obstacle.Bottom
            && candidate.Bottom > obstacle.Y);

    private static bool Contains(RectD container, RectD child) =>
        child.X >= container.X
        && child.Y >= container.Y
        && child.Right <= container.Right
        && child.Bottom <= container.Bottom;

    private static bool IsUsable(RectD bounds) =>
        double.IsFinite(bounds.X)
        && double.IsFinite(bounds.Y)
        && double.IsFinite(bounds.Width)
        && double.IsFinite(bounds.Height)
        && double.IsFinite(bounds.Right)
        && double.IsFinite(bounds.Bottom)
        && bounds.Width > 0
        && bounds.Height > 0;
}
