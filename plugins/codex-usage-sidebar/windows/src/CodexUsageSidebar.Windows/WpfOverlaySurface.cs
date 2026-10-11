#if WINDOWS
using System.Runtime.InteropServices;
using System.ComponentModel;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using System.Diagnostics;
using CodexUsageSidebar.Core;

namespace CodexUsageSidebar.Windows;

public sealed partial class WpfOverlaySurface : IOverlaySurface, IIndicatorSizeProvider
{
    private const int ExtendedWindowStyle = -20;
    private const int NoActivateStyle = 0x08000000;
    private const int ToolWindowStyle = 0x00000080;
    private const int MouseActivateMessage = 0x0021;
    private const int MouseActivateNoActivate = 3;
    private readonly TimeZoneInfo timeZone;
    private readonly Window indicator;
    private readonly Window detail;
    private readonly Border indicatorSurface;
    private readonly Image indicatorLogo;
    private readonly Grid indicatorText;
    private readonly DispatcherTimer hoverTimer;
    private DetailInteractionState interaction = DetailInteractionState.Initial;
    private OverlayPresentation? latestPresentation;
    private QuotaDetailContent? latestContent;
    private WpfOverlayPalette palette = WpfOverlayPalette.Light;
    private Uri? accountAvatarURL;
    private ImageSource? accountAvatarSource;
    private readonly IndicatorDragSession indicatorDrag = new();
    private bool suppressNextIndicatorRelease;
    private readonly IndicatorPlacementPreferences placementPreferences;
    private readonly IndicatorPreferencesStore? placementStore;
    private OverlayPresentation? automaticPresentation;
    private QuotaDetailContent? renderedContent;
    private WpfOverlayPalette? renderedPalette;
    private ImageSource? renderedAvatar;
    private ScrollViewer? detailRows;
    private double requestedRowViewportHeight = QuotaDetailViewportPolicy.DefaultRowViewportHeight;
    private bool isResizingDetail;
    private double resizeStartCursorY;
    private double resizeStartRowHeight;

    public WpfOverlaySurface(DisplayLanguage language, TimeZoneInfo timeZone,
        IndicatorPlacementPreferences? placementPreferences = null,
        IndicatorPreferencesStore? placementStore = null)
    {
        this.timeZone = timeZone;
        this.placementPreferences = placementPreferences ?? new();
        this.placementStore = placementStore;
        indicatorText = new Grid
        {
            VerticalAlignment = VerticalAlignment.Center,
        };
        indicatorLogo = new Image
        {
            Source = LoadThemeIconSource(palette),
            Width = OverlayVisualMetrics.IndicatorLogoSize,
            Height = OverlayVisualMetrics.IndicatorLogoSize,
            Stretch = Stretch.Uniform,
            VerticalAlignment = VerticalAlignment.Center,
        };
        var indicatorContent = new Grid
        {
            HorizontalAlignment = HorizontalAlignment.Stretch,
            VerticalAlignment = VerticalAlignment.Center,
        };
        indicatorContent.ColumnDefinitions.Add(new ColumnDefinition
        {
            Width = new GridLength(OverlayVisualMetrics.IndicatorLogoSize),
        });
        indicatorContent.ColumnDefinitions.Add(new ColumnDefinition
        {
            Width = new GridLength(OverlayVisualMetrics.IndicatorLogoTextGap),
        });
        indicatorContent.ColumnDefinitions.Add(new ColumnDefinition
        {
            Width = new GridLength(1, GridUnitType.Star),
        });
        Grid.SetColumn(indicatorLogo, 0);
        Grid.SetColumn(indicatorText, 2);
        indicatorContent.Children.Add(indicatorLogo);
        indicatorContent.Children.Add(indicatorText);
        var indicatorColor = SystemColors.WindowTextColor;
        indicatorSurface = new Border
        {
            Background = new SolidColorBrush(Color.FromArgb(
                IndicatorHitTestPolicy.BackgroundAlpha(highlighted: false),
                indicatorColor.R,
                indicatorColor.G,
                indicatorColor.B)),
            CornerRadius = new CornerRadius(10),
            HorizontalAlignment = HorizontalAlignment.Right,
            Padding = new Thickness(
                OverlayVisualMetrics.IndicatorHorizontalPadding,
                0,
                OverlayVisualMetrics.IndicatorHorizontalPadding,
                0),
            Child = indicatorContent,
        };
        indicator = CreatePassiveWindow(indicatorSurface);
        indicator.Width = OverlayVisualMetrics.IndicatorWidth;
        detail = CreatePassiveWindow(new Border());
        detail.Width = OverlayVisualMetrics.DetailWidth;
        detail.IsVisibleChanged += (_, _) =>
        {
            if (!detail.IsVisible && settingsMenu is not null) settingsMenu.IsOpen = false;
            UpdateOutsideClickMonitor();
        };
        indicator.Closed += (_, _) => outsideClickMonitor?.Dispose();
        indicator.MouseLeftButtonDown += async (_, eventArgs) =>
        {
            if (eventArgs is null) return;
            if (eventArgs.ChangedButton != MouseButton.Left) return;
            var clickAction = IndicatorClickPolicy.Resolve(eventArgs.ClickCount, dragged: false);
            if (clickAction == IndicatorClickAction.SwitchToAutomaticPlacement && CanDragIndicator())
            {
                suppressNextIndicatorRelease = true;
                interaction = DetailInteractionState.Initial;
                detail.Hide();
                await SetPlacementModeAsync(IndicatorPlacementMode.Automatic);
                eventArgs.Handled = true;
                return;
            }
            if (!CanDragIndicator()
                || !GetCursorPos(out var cursor)) return;
            indicatorDrag.Begin(cursor.X, cursor.Y, latestPresentation!.Placement.Frame, latestPresentation.DpiScale);
            indicator.CaptureMouse();
            eventArgs.Handled = true;
        };
        indicator.MouseMove += (_, eventArgs) =>
        {
            if (!indicatorDrag.IsActive || eventArgs.LeftButton != MouseButtonState.Pressed
                || !GetCursorPos(out var cursor) || latestPresentation is not { } presentation) return;
            var frame = indicatorDrag.Update(cursor.X, cursor.Y,
                this.placementPreferences.Mode);
            if (frame is null) return;
            latestPresentation = presentation with { Placement = presentation.Placement with { Frame = frame.Value } };
            PositionPhysical(indicator, frame.Value);
            detail.Hide();
            eventArgs.Handled = true;
        };
        indicator.MouseLeftButtonUp += async (_, eventArgs) =>
        {
            if (eventArgs is null) return;
            if (eventArgs.ChangedButton != MouseButton.Left) return;
            var dragged = indicatorDrag.End();
            if (indicator.IsMouseCaptured) indicator.ReleaseMouseCapture();
            if (suppressNextIndicatorRelease)
            {
                suppressNextIndicatorRelease = false;
                eventArgs.Handled = true;
                return;
            }
            if (dragged && latestPresentation is { } presentation)
            {
                CaptureManualPlacement(presentation.Placement.Frame);
                await SavePlacementAsync();
                eventArgs.Handled = true;
                return;
            }
            var clickAction = IndicatorClickPolicy.Resolve(eventArgs.ClickCount, dragged);
            if (clickAction != IndicatorClickAction.ToggleDetails) return;
            interaction = interaction.TogglePinned(IsPointerInsideOverlay());
            RefreshInteraction();
        };
        indicator.MouseRightButtonUp += (_, eventArgs) =>
        {
            if (eventArgs.ChangedButton != MouseButton.Right) return;
            ShowPositionMenu(indicatorSurface);
            eventArgs.Handled = true;
        };
        indicator.LostMouseCapture += (_, _) => indicatorDrag.End();
        hoverTimer = new DispatcherTimer(
            TimeSpan.FromMilliseconds(100),
            DispatcherPriority.Input,
            (_, _) => PollPointer(),
            indicator.Dispatcher);
    }

    public bool HasForegroundWindow
    {
        get
        {
            var foreground = GetForegroundWindow();
            if (foreground == IntPtr.Zero) return false;
            _ = GetWindowThreadProcessId(foreground, out var processId);
            return processId == Environment.ProcessId;
        }
    }

    [DllImport("user32.dll")]
    private static extern IntPtr GetForegroundWindow();

    public async ValueTask ShowAsync(
        OverlayPresentation presentation,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        Task persistence = Task.CompletedTask;
        await OnUiAsync(() =>
        {
            // Incoming quota/titlebar observations cannot move the control
            // underneath an active captured screen-coordinate drag.
            if (indicatorDrag.IsActive) return;
            automaticPresentation = presentation;
            var frame = presentation.Placement.Frame;
            if (presentation.Mode == PlacementMode.SafeDock
                && presentation.SafeDockRequest is { } request)
            {
                request = request with { WorkArea = UsableWorkArea(request.WorkArea)
                    ? request.WorkArea
                    : WorkAreaFor(presentation.OwnerHandle) ?? request.WorkArea };
                var resolved = SafeDockPlacementResolver.Resolve(request);
                if (resolved.Frame is null)
                {
                    indicator.Hide();
                    return;
                }
                frame = resolved.Frame.Value;
                presentation = presentation with
                {
                    Placement = presentation.Placement with { Frame = frame },
                    SafeDockSize = resolved.Size,
                    SafeDockRequest = request,
                };
            }
            if (presentation.SwitchToFree && placementPreferences.Mode == IndicatorPlacementMode.Automatic)
            {
                var fallbackScreen = System.Windows.Forms.Screen.FromPoint(new System.Drawing.Point(
                    (int)Math.Round(frame.X + frame.Width / 2), (int)Math.Round(frame.Y + frame.Height / 2)));
                if (placementPreferences.SwitchToFreeFallback(fallbackScreen.DeviceName, frame, ScreenWorkArea(fallbackScreen)))
                    persistence = SavePlacementAsync();
            }
            if (this.placementPreferences.Mode != IndicatorPlacementMode.Automatic)
            {
                var screen = System.Windows.Forms.Screen.AllScreens.FirstOrDefault(
                    screen => screen.DeviceName == this.placementPreferences.ActiveDisplayId)
                    ?? System.Windows.Forms.Screen.FromHandle(presentation.OwnerHandle);
                var work = ScreenWorkArea(screen);
                var scale = ScaleForScreen(screen, presentation.DpiScale);
                var manualSize = frame with
                {
                    Width = frame.Width / presentation.DpiScale * scale,
                    Height = frame.Height / presentation.DpiScale * scale,
                };
                if (!this.placementPreferences.Placements.ContainsKey(screen.DeviceName))
                    this.placementPreferences.Capture(screen.DeviceName, manualSize, work);
                frame = this.placementPreferences.Resolve(screen.DeviceName, work, manualSize);
                presentation = presentation with { DpiScale = scale, Placement = presentation.Placement with { Frame = frame } };
            }
            latestPresentation = presentation;
            palette = ResolvePalette(presentation.ThemeProbePoint);
            indicatorLogo.Source = LoadThemeIconSource(palette);
            indicator.Opacity = presentation.Freshness == SnapshotFreshness.Dimmed ? 0.58 : 1;
            detail.Opacity = presentation.Freshness == SnapshotFreshness.Dimmed ? 0.58 : 1;
            latestContent = QuotaDetailFormatter.Format(
                presentation.Snapshot,
                DateTimeOffset.Now,
                presentation.Language,
                timeZone,
                presentation.TokenUsage,
                presentation.Account,
                presentation.Version);
            UpdateAccountAvatar(presentation.Account?.AvatarUrl);
            SetOwner(indicator, presentation.OwnerHandle);
            SetOwner(detail, presentation.OwnerHandle);
            UpdateIndicator(
                presentation.Snapshot,
                presentation.Language,
                presentation.Mode == PlacementMode.SafeDock && presentation.SafeDockSize == SafeDockSize.Compact);
            indicator.Width = frame.Width / presentation.DpiScale;
            indicator.Height = frame.Height / presentation.DpiScale;
            var horizontalPadding = OverlayVisualMetrics.IndicatorHorizontalPaddingForHeight(indicator.Height);
            indicatorSurface.Padding = new Thickness(horizontalPadding, 0, horizontalPadding, 0);
            if (!indicator.IsVisible) new WindowInteropHelper(indicator).EnsureHandle();
            PositionPhysical(indicator, frame);
            if (!indicator.IsVisible) indicator.Show();
            hoverTimer.Start();
            RefreshInteraction();
        });
        await persistence;
    }

    public ValueTask HideAsync(CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        return OnUiAsync(() =>
        {
            latestPresentation = null;
            latestContent = null;
            interaction = DetailInteractionState.Initial;
            indicatorDrag.End();
            if (indicator.IsMouseCaptured) indicator.ReleaseMouseCapture();
            hoverTimer.Stop();
            detail.Hide();
            indicator.Hide();
        });
    }

    private void PollPointer()
    {
        var inside = IsPointerInsideOverlay();
        var updated = interaction.PointerChanged(inside);
        if (updated == interaction) return;
        interaction = updated;
        RefreshInteraction();
    }

    private void RefreshInteraction()
    {
        UpdateOutsideClickMonitor();
        if (indicatorDrag.IsDragging || settingsMenu?.IsOpen == true) return;
        var highlighted = IsPointerInside(indicator) || interaction.IsPinned || interaction.IsLockedOpen;
        var color = palette.PrimaryColor;
        indicatorSurface.Background = new SolidColorBrush(Color.FromArgb(
            IndicatorHitTestPolicy.BackgroundAlpha(highlighted),
            color.R,
            color.G,
            color.B));
        if (QuotaDetailViewportPolicy.ShouldKeepDetailVisible(isResizingDetail, interaction)
            && latestPresentation is not null
            && latestContent is not null)
        {
            ShowDetail(latestPresentation, latestContent);
        }
        else
        {
            detail.Hide();
        }
    }

    private bool IsPointerInsideOverlay() =>
        IsPointerInside(indicator) || IsPointerInside(detail);

    private static bool IsPointerInside(Window window)
    {
        if (!window.IsVisible || !GetCursorPos(out var cursor))
        {
            return false;
        }
        var handle = new WindowInteropHelper(window).Handle;
        if (handle == IntPtr.Zero || !GetWindowRect(handle, out var bounds))
        {
            return false;
        }
        return OverlayPointerPolicy.IsInside(
            new PointD(cursor.X, cursor.Y),
            new RectD(
                bounds.Left,
                bounds.Top,
                bounds.Right - bounds.Left,
                bounds.Bottom - bounds.Top));
    }

    private bool CanDragIndicator() =>
        latestPresentation is not null && placementPreferences.Mode == IndicatorPlacementMode.Free;

    private async Task SetPlacementModeAsync(IndicatorPlacementMode mode)
    {
        if (!Enum.IsDefined(mode)) return;
        if (latestPresentation is { } current && mode != IndicatorPlacementMode.Automatic)
            CaptureManualPlacement(current.Placement.Frame);
        placementPreferences.Mode = mode;
        indicatorDrag.End();
        if (indicator.IsMouseCaptured) indicator.ReleaseMouseCapture();
        await SavePlacementAsync();
        if (automaticPresentation is { } automatic) await ShowAsync(automatic, CancellationToken.None);
        if (mode == IndicatorPlacementMode.Automatic) TitlebarRefreshRequested?.Invoke();
    }

    private void CaptureManualPlacement(RectD frame)
    {
        var screen = System.Windows.Forms.Screen.FromPoint(new System.Drawing.Point(
            (int)Math.Round(frame.X + frame.Width / 2), (int)Math.Round(frame.Y + frame.Height / 2)));
        placementPreferences.Capture(screen.DeviceName, frame, ScreenWorkArea(screen));
    }

    private async Task SavePlacementAsync()
    {
        if (placementStore is null) return;
        try { await placementStore.SaveAsync(placementPreferences, CancellationToken.None); }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        { Trace.TraceWarning("Unable to save indicator placement: {0}", error.GetType().Name); }
    }

    private static RectD ScreenWorkArea(System.Windows.Forms.Screen screen) => new(
        screen.WorkingArea.X, screen.WorkingArea.Y, screen.WorkingArea.Width, screen.WorkingArea.Height);

    private static double ScaleForScreen(System.Windows.Forms.Screen screen, double fallback)
    {
        var monitor = MonitorFromPoint(new NativePoint { X = screen.Bounds.X + screen.Bounds.Width / 2,
            Y = screen.Bounds.Y + screen.Bounds.Height / 2 }, 2);
        return monitor != IntPtr.Zero && GetDpiForMonitor(monitor, 0, out var dpiX, out _) == 0 && dpiX > 0
            ? dpiX / 96d : fallback;
    }

    private void ShowDetail(OverlayPresentation presentation, QuotaDetailContent content)
    {
        if (!QuotaDetailContentComparer.Equivalent(renderedContent, content)
            || !ReferenceEquals(renderedPalette, palette) || !ReferenceEquals(renderedAvatar, accountAvatarSource))
        {
            var scrollOffset = detailRows?.VerticalOffset ?? 0;
            detail.Content = BuildDetailCard(content, palette, accountAvatarSource);
            renderedContent = content;
            renderedPalette = palette;
            renderedAvatar = accountAvatarSource;
            detail.UpdateLayout();
            detailRows?.ScrollToVerticalOffset(scrollOffset);
        }
        detail.SizeToContent = SizeToContent.Height;
        detail.UpdateLayout();
        PositionDetail(presentation);
    }

    private void PositionDetail(OverlayPresentation presentation)
    {
        var indicatorFrame = presentation.Placement.Frame;
        var workArea = WorkAreaFor(new WindowInteropHelper(indicator).Handle);
        if (workArea is null)
        {
            detail.Hide();
            return;
        }
        var detailWidth = detail.Width * presentation.DpiScale;
        var left = OverlayDetailLayout.LeftForIndicator(
            indicatorFrame,
            workArea.Value,
            detailWidth);
        var gap = 6 * presentation.DpiScale;
        double detailHeight;
        double top;
        if (placementPreferences.Mode == IndicatorPlacementMode.Free && detailRows is not null)
        {
            detailRows.Height = requestedRowViewportHeight;
            detail.UpdateLayout();
            var fixedChromeHeight = Math.Max(0, detail.ActualHeight - detailRows.ActualHeight);
            var minimumHeight = (fixedChromeHeight + QuotaDetailViewportPolicy.MinimumRowViewportHeight)
                * presentation.DpiScale;
            var freePlacement = OverlayDetailLayout.ResolveFreeDetailPlacement(
                indicatorFrame, workArea.Value, minimumHeight, gap);
            if (freePlacement is null)
            {
                detail.Hide();
                return;
            }
            var rowViewportHeight = QuotaDetailViewportPolicy.ResolveViewportWithinAvailableHeight(
                requestedRowViewportHeight,
                freePlacement.Value.AvailableHeight / presentation.DpiScale,
                fixedChromeHeight);
            if (rowViewportHeight is null)
            {
                detail.Hide();
                return;
            }
            detailRows.Height = rowViewportHeight.Value;
            detail.UpdateLayout();
            detailHeight = detail.ActualHeight * presentation.DpiScale;
            top = freePlacement.Value.IsAbove
                ? indicatorFrame.Y - detailHeight - gap
                : indicatorFrame.Bottom + gap;
        }
        else
        {
            detailHeight = detail.ActualHeight * presentation.DpiScale;
            var below = indicatorFrame.Bottom + gap;
            var above = indicatorFrame.Y - detailHeight - gap;
            top = below + detailHeight <= workArea.Value.Bottom
                ? below
                : Math.Max(workArea.Value.Y, above);
        }
        if (!detail.IsVisible) new WindowInteropHelper(detail).EnsureHandle();
        PositionPhysical(detail, new RectD(left, top, detailWidth, detailHeight));
        if (!detail.IsVisible) detail.Show();
    }

    private Border BuildDetailCard(
        QuotaDetailContent content,
        WpfOverlayPalette palette,
        ImageSource? accountAvatarSource)
    {
        var accent = WpfQuotaColors.ForRemainingPercent(content.RemainingPercent);
        var body = new StackPanel();
        var header = new Grid { Margin = new Thickness(16, 13, 16, 9) };
        header.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(32) });
        header.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        header.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        header.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        header.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var icon = BuildThemeIcon(palette);
        Grid.SetColumn(icon, 0);
        header.Children.Add(icon);
        var title = new TextBlock
        {
            Text = content.Title,
            FontFamily = new FontFamily("Segoe UI"),
            FontSize = OverlayVisualMetrics.HeaderTitleFontSize,
            FontWeight = FontWeights.SemiBold,
            MaxWidth = OverlayVisualMetrics.HeaderTitleMaximumWidth,
            VerticalAlignment = VerticalAlignment.Center,
            TextTrimming = TextTrimming.CharacterEllipsis,
            Foreground = palette.Primary,
        };
        Grid.SetColumn(title, 1);
        header.Children.Add(title);
        var lockButton = BuildDetailLockButton(content, palette);
        Grid.SetColumn(lockButton, 3);
        header.Children.Add(lockButton);
        var highlight = palette.BadgeColor;
        var badge = new Border
        {
            BorderBrush = new SolidColorBrush(Color.FromArgb(110, highlight.R, highlight.G, highlight.B)),
            BorderThickness = new Thickness(0.75),
            CornerRadius = new CornerRadius(8),
            Margin = new Thickness(0, 0, 8, 0),
            Padding = new Thickness(5, 0, 5, 0),
            Height = OverlayVisualMetrics.VersionBadgeHeight,
            VerticalAlignment = VerticalAlignment.Center,
            Child = new TextBlock
            {
                Text = $"v{content.Version}",
                FontFamily = new FontFamily("Segoe UI"),
                FontSize = OverlayVisualMetrics.VersionBadgeFontSize,
                FontWeight = FontWeights.Medium,
                Foreground = palette.Badge,
                TextWrapping = TextWrapping.NoWrap,
                VerticalAlignment = VerticalAlignment.Center,
            },
        };
        Grid.SetColumn(badge, 4);
        header.Children.Add(badge);
        body.Children.Add(header);
        var quotaWindows = content.QuotaWindows ??
            [new QuotaWindowPresentation(string.Empty, content.RemainingPercent)];
        foreach (var window in quotaWindows)
        {
            var quotaHeader = new Grid { Margin = new Thickness(16, 6, 16, 3) };
            quotaHeader.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            quotaHeader.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            quotaHeader.Children.Add(new TextBlock
            {
                Text = window.Label,
                FontSize = 14,
                FontWeight = FontWeights.SemiBold,
                Foreground = palette.Primary,
                VerticalAlignment = VerticalAlignment.Center,
            });
            var remaining = new TextBlock
            {
                Text = $"{window.RemainingPercent}%",
                FontSize = OverlayVisualMetrics.RemainingPercentFontSize,
                FontWeight = FontWeights.SemiBold,
                Foreground = new SolidColorBrush(WpfQuotaColors.ForRemainingPercent(window.RemainingPercent)),
                VerticalAlignment = VerticalAlignment.Center,
            };
            Grid.SetColumn(remaining, 1);
            quotaHeader.Children.Add(remaining);
            body.Children.Add(quotaHeader);
            body.Children.Add(new WpfQuotaProgressBar
            {
                Height = OverlayVisualMetrics.ProgressTrackHeight,
                Margin = new Thickness(16, 0, 16, 13),
                RemainingPercent = window.RemainingPercent,
                TrackBrush = palette.Track,
            });
        }
        body.Children.Add(BuildFullWidthSeparator(palette));

        if (content.TokenUsage is { } tokenUsage)
        {
            body.Children.Add(BuildTokenUsageBand(tokenUsage, accent, palette));
            body.Children.Add(new Border { Height = 1, Background = palette.Border, Opacity = 0.6 });
        }

        var rows = new StackPanel { Margin = new Thickness(16, 8, 16, 8) };
        for (var index = 0; index < content.Rows.Count; index++)
        {
            if (index > 0)
            {
                rows.Children.Add(new Border
                {
                    Height = OverlayDetailLayout.RowSeparatorHeight,
                    Background = palette.Border,
                    Opacity = 0.6,
                });
            }

            var row = content.Rows[index];
            var grid = new Grid { MinHeight = row.Value.Contains('\n') ? 46 : 32 };
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(126) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            grid.Children.Add(new TextBlock
            {
                Text = row.Label,
                FontFamily = new FontFamily("Segoe UI"),
                FontSize = 13,
                Foreground = palette.Primary,
                FontWeight = FontWeights.SemiBold,
                VerticalAlignment = VerticalAlignment.Center,
                TextWrapping = TextWrapping.Wrap,
            });
            var rowAccent = WpfQuotaColors.ForRemainingPercent(row.AccentRemainingPercent ?? content.RemainingPercent);
            var value = BuildDetailValue(row.Value, rowAccent, palette, row.EmphasizeCountdown);
            value.VerticalAlignment = VerticalAlignment.Center;
            Grid.SetColumn(value, 1);
            grid.Children.Add(value);
            rows.Children.Add(grid);
        }
        detailRows = new ScrollViewer
        {
            Content = rows,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled,
            Height = requestedRowViewportHeight,
        };
        body.Children.Add(detailRows);
        body.Children.Add(BuildDetailResizeHandle(palette));
        body.Children.Add(BuildFullWidthSeparator(palette));
        body.Children.Add(BuildFooter(content, palette, accountAvatarSource));
        return new Border
        {
            Width = OverlayVisualMetrics.DetailWidth,
            Background = palette.Surface,
            BorderBrush = palette.Border,
            BorderThickness = new Thickness(0.5),
            CornerRadius = new CornerRadius(12),
            Child = body,
        };
    }

    internal Border BuildDetailCardForVisualFixture(
        QuotaDetailContent content,
        WpfOverlayPalette palette) =>
        BuildDetailCard(content, palette, accountAvatarSource: null);

    private FrameworkElement BuildDetailResizeHandle(WpfOverlayPalette palette)
    {
        var grip = new Border
        {
            Width = OverlayVisualMetrics.DetailResizeHandleWidth,
            Height = OverlayVisualMetrics.DetailResizeHandleHeight,
            CornerRadius = new CornerRadius(OverlayVisualMetrics.DetailResizeHandleHeight / 2),
            Background = palette.Secondary,
            Opacity = 0.72,
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center,
        };
        var handle = new Border
        {
            Height = OverlayVisualMetrics.DetailResizeHitHeight,
            Background = Brushes.Transparent,
            Cursor = Cursors.SizeNS,
            ToolTip = QuotaDetailViewportPolicy.ResizeHint(
                latestPresentation?.Language ?? DisplayLanguage.English),
            Child = grip,
        };
        ToolTipService.SetInitialShowDelay(handle, 0);
        ToolTipService.SetBetweenShowDelay(handle, 0);
        System.Windows.Automation.AutomationProperties.SetName(
            handle,
            QuotaDetailViewportPolicy.ResizeHint(latestPresentation?.Language ?? DisplayLanguage.English));
        handle.MouseLeftButtonDown += (_, eventArgs) =>
        {
            if (detailRows is null || !GetCursorPos(out var cursor)) return;
            isResizingDetail = true;
            resizeStartCursorY = cursor.Y;
            resizeStartRowHeight = detailRows.ActualHeight;
            grip.Background = new SolidColorBrush(palette.BadgeColor);
            grip.Opacity = 0.9;
            handle.CaptureMouse();
            eventArgs.Handled = true;
        };
        handle.MouseMove += (_, eventArgs) =>
        {
            if (!isResizingDetail || eventArgs.LeftButton != MouseButtonState.Pressed
                || detailRows is null || latestPresentation is not { } presentation
                || !GetCursorPos(out var cursor)) return;
            var workArea = WorkAreaFor(new WindowInteropHelper(indicator).Handle);
            if (workArea is null) return;
            var fixedChromeHeight = Math.Max(0, detail.ActualHeight - detailRows.ActualHeight);
            var availablePanelHeight = workArea.Value.Height / presentation.DpiScale;
            requestedRowViewportHeight = QuotaDetailViewportPolicy.ResolveRowViewportHeight(
                resizeStartRowHeight + cursor.Y - resizeStartCursorY,
                availablePanelHeight,
                fixedChromeHeight);
            detailRows.Height = requestedRowViewportHeight;
            detail.UpdateLayout();
            PositionDetail(presentation);
            eventArgs.Handled = true;
        };
        handle.MouseLeftButtonUp += (_, eventArgs) =>
        {
            if (!isResizingDetail) return;
            isResizingDetail = false;
            if (handle.IsMouseCaptured) handle.ReleaseMouseCapture();
            grip.Background = palette.Secondary;
            grip.Opacity = handle.IsMouseOver ? 0.9 : 0.72;
            eventArgs.Handled = true;
        };
        handle.MouseEnter += (_, _) => grip.Opacity = 0.9;
        handle.MouseLeave += (_, _) => { if (!isResizingDetail) grip.Opacity = 0.72; };
        handle.LostMouseCapture += (_, _) =>
        {
            isResizingDetail = false;
            grip.Background = palette.Secondary;
            grip.Opacity = handle.IsMouseOver ? 0.9 : 0.72;
        };
        return handle;
    }

    private ToggleButton BuildDetailLockButton(QuotaDetailContent content, WpfOverlayPalette palette)
    {
        var button = new ToggleButton
        {
            Width = OverlayVisualMetrics.DetailLockButtonSize,
            Height = OverlayVisualMetrics.DetailLockButtonSize,
            Margin = new Thickness(0, 0, OverlayVisualMetrics.DetailLockButtonBadgeGap, 0),
            Padding = new Thickness(0),
            BorderThickness = new Thickness(0),
            Background = Brushes.Transparent,
            Foreground = palette.Secondary,
            Cursor = Cursors.Hand,
            Focusable = false,
            IsChecked = interaction.IsLockedOpen,
            VerticalAlignment = VerticalAlignment.Center,
            Content = new TextBlock
            {
                Text = "\uE718",
                FontFamily = new FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets"),
                FontSize = 13,
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center,
            },
        };
        var chrome = new FrameworkElementFactory(typeof(Border));
        chrome.Name = "LockChrome";
        chrome.SetValue(Border.BackgroundProperty, Brushes.Transparent);
        chrome.SetValue(Border.CornerRadiusProperty,
            new CornerRadius(OverlayVisualMetrics.DetailLockButtonSize / 2));
        var presenter = new FrameworkElementFactory(typeof(ContentPresenter));
        presenter.SetValue(ContentPresenter.HorizontalAlignmentProperty, HorizontalAlignment.Center);
        presenter.SetValue(ContentPresenter.VerticalAlignmentProperty, VerticalAlignment.Center);
        chrome.AppendChild(presenter);
        var template = new ControlTemplate(typeof(ToggleButton)) { VisualTree = chrome };
        var hover = new Trigger { Property = ToggleButton.IsMouseOverProperty, Value = true };
        hover.Setters.Add(new Setter(Border.BackgroundProperty,
            new SolidColorBrush(Color.FromArgb(
                OverlayVisualMetrics.DetailLockButtonHoverAlpha,
                palette.PrimaryColor.R,
                palette.PrimaryColor.G,
                palette.PrimaryColor.B)), "LockChrome"));
        var active = new Trigger { Property = ToggleButton.IsCheckedProperty, Value = true };
        active.Setters.Add(new Setter(Border.BackgroundProperty,
            new SolidColorBrush(Color.FromArgb(
                OverlayVisualMetrics.DetailLockButtonActiveAlpha,
                palette.BadgeColor.R,
                palette.BadgeColor.G,
                palette.BadgeColor.B)), "LockChrome"));
        active.Setters.Add(new Setter(ToggleButton.ForegroundProperty, palette.Badge));
        template.Triggers.Add(hover);
        template.Triggers.Add(active);
        button.Template = template;
        UpdateDetailLockButtonAccessibility(button, content);
        button.Click += (_, _) =>
        {
            interaction = interaction.ToggleLockedOpen(IsPointerInsideOverlay());
            button.IsChecked = interaction.IsLockedOpen;
            UpdateDetailLockButtonAccessibility(button, content);
            RefreshInteraction();
        };
        return button;
    }

    private void UpdateDetailLockButtonAccessibility(ToggleButton button, QuotaDetailContent content)
    {
        var language = latestPresentation?.Language ?? DisplayLanguage.English;
        var label = QuotaDetailLockCopy.Label(language, interaction.IsLockedOpen);
        button.ToolTip = label;
        System.Windows.Automation.AutomationProperties.SetName(button, label);
        System.Windows.Automation.AutomationProperties.SetHelpText(button, content.Title);
    }

    private static Border BuildFullWidthSeparator(WpfOverlayPalette palette) => new()
    {
        Height = OverlayDetailLayout.SectionSeparatorHeight,
        Margin = new Thickness(
            OverlayDetailLayout.SectionSeparatorHorizontalMargin,
            0,
            OverlayDetailLayout.SectionSeparatorHorizontalMargin,
            0),
        Background = palette.Border,
        Opacity = 0.6,
        HorizontalAlignment = HorizontalAlignment.Stretch,
    };

    private static UIElement BuildThemeIcon(WpfOverlayPalette palette)
    {
        var imageSource = LoadThemeIconSource(palette);
        if (imageSource is not null)
        {
            return new Image
            {
                Source = imageSource,
                Width = OverlayDetailLayout.LogoSize,
                Height = OverlayDetailLayout.LogoSize,
                Stretch = Stretch.Uniform,
                VerticalAlignment = VerticalAlignment.Center,
                Clip = new EllipseGeometry(
                    new Point(
                        OverlayDetailLayout.LogoSize / 2,
                        OverlayDetailLayout.LogoSize / 2),
                    OverlayDetailLayout.LogoSize / 2,
                    OverlayDetailLayout.LogoSize / 2),
            };
        }

        return new Border
        {
            Width = OverlayDetailLayout.LogoSize,
            Height = OverlayDetailLayout.LogoSize,
            CornerRadius = new CornerRadius(OverlayDetailLayout.LogoSize / 2),
            Background = new SolidColorBrush(palette.BadgeColor),
            VerticalAlignment = VerticalAlignment.Center,
        };
    }

    private static ImageSource? LoadThemeIconSource(WpfOverlayPalette palette)
    {
        var resource = ReferenceEquals(palette, WpfOverlayPalette.Dark)
            ? "pack://application:,,,/Assets/quota-icon-dark.png"
            : "pack://application:,,,/Assets/quota-icon-light.png";
        try
        {
            return new BitmapImage(new Uri(resource));
        }
        catch (Exception)
        {
            return null;
        }
    }

    private static Border BuildTokenUsageBand(
        QuotaTokenUsageContent usage,
        Color accent,
        WpfOverlayPalette palette)
    {
        var panel = new StackPanel { Margin = new Thickness(16, 7, 16, 9) };
        var heading = new Grid();
        heading.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        heading.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        heading.Children.Add(new TextBlock
        {
            Text = usage.Title,
            FontFamily = new FontFamily("Segoe UI"),
            FontSize = 17,
            FontWeight = FontWeights.SemiBold,
            Foreground = palette.Primary,
        });
        var total = new TextBlock
        {
            Text = usage.Availability == TokenUsageAvailability.Available
                ? usage.TotalLabel
                : usage.UnavailableLabel,
            FontFamily = new FontFamily("Segoe UI"),
            FontSize = 13,
            Foreground = palette.Secondary,
            TextAlignment = TextAlignment.Right,
            VerticalAlignment = VerticalAlignment.Center,
        };
        Grid.SetColumn(total, 1);
        heading.Children.Add(total);
        panel.Children.Add(heading);
        var chart = new Grid { Height = 96, Margin = new Thickness(0, 10, 0, 0) };
        for (var index = 0; index < usage.Days.Count; index++)
        {
            chart.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            var day = usage.Days[index];
            var slot = new Grid();
            var labels = new StackPanel { VerticalAlignment = VerticalAlignment.Bottom };
            labels.Children.Add(new TextBlock
            {
                Text = day.TokensLabel,
                FontFamily = new FontFamily("Segoe UI"),
                FontSize = 10,
                Foreground = day.IsCurrent ? new SolidColorBrush(accent) : palette.Secondary,
                HorizontalAlignment = HorizontalAlignment.Center,
            });
            var bar = new Border
            {
                Width = 18,
                Height = day.Tokens == 0 ? 2 : Math.Max(4, Math.Min(42, 42 * day.Tokens / Math.Max(1, usage.Days.Max(item => item.Tokens)))),
                Background = day.IsCurrent ? new SolidColorBrush(accent) : palette.Border,
                CornerRadius = new CornerRadius(3),
                Margin = new Thickness(0, 4, 0, 4),
                HorizontalAlignment = HorizontalAlignment.Center,
            };
            labels.Children.Add(bar);
            labels.Children.Add(new TextBlock
            {
                Text = day.DateLabel,
                FontFamily = new FontFamily("Segoe UI"),
                FontSize = 9,
                Foreground = palette.Secondary,
                HorizontalAlignment = HorizontalAlignment.Center,
            });
            slot.Children.Add(labels);
            Grid.SetColumn(slot, index);
            chart.Children.Add(slot);
        }
        panel.Children.Add(chart);
        return new Border { Child = panel };
    }

    private UIElement BuildFooter(
        QuotaDetailContent content,
        WpfOverlayPalette palette,
        ImageSource? accountAvatarSource)
    {
        var footer = new Grid { Margin = new Thickness(16, 8, 12, 10) };
        footer.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        footer.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        footer.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        footer.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var account = content.Account?.PreferredName ?? content.AccountLabel;
        var avatar = BuildAccountAvatar(content.Account, palette, accountAvatarSource);
        Grid.SetColumn(avatar, 0);
        footer.Children.Add(avatar);
        var nameLabel = new TextBlock
        {
            Text = account,
            FontFamily = new FontFamily("Segoe UI"),
            FontSize = 13,
            Foreground = palette.Primary,
            VerticalAlignment = VerticalAlignment.Center,
            Margin = new Thickness(8, 0, 8, 0),
            TextTrimming = TextTrimming.CharacterEllipsis,
        };
        Grid.SetColumn(nameLabel, 1);
        footer.Children.Add(nameLabel);
        var github = new Button
        {
            Content = new StackPanel
            {
                Orientation = Orientation.Horizontal,
                Children =
                {
                    new System.Windows.Shapes.Path
                    {
                        Data = Geometry.Parse("M12 .297c-6.63 0-12 5.373-12 12 0 5.303 3.438 9.8 8.205 11.385.6.113.82-.258.82-.577 0-.285-.01-1.04-.015-2.04-3.338.724-4.042-1.61-4.042-1.61-.546-1.387-1.333-1.756-1.333-1.756-1.089-.745.084-.73.084-.73 1.205.084 1.84 1.237 1.84 1.237 1.07 1.834 2.807 1.304 3.492.997.108-.775.418-1.305.762-1.605-2.665-.3-5.466-1.332-5.466-5.93 0-1.31.465-2.38 1.235-3.22-.135-.303-.54-1.523.105-3.176 0 0 1.005-.322 3.3 1.23.957-.266 1.983-.399 3.003-.404 1.02.005 2.047.138 3.006.404 2.292-1.552 3.296-1.23 3.296-1.23.647 1.653.24 2.873.12 3.176.765.84 1.23 1.91 1.23 3.22 0 4.61-2.805 5.625-5.475 5.92.43.372.81 1.102.81 2.222 0 1.606-.015 2.896-.015 3.286 0 .315.21.69.825.57C20.565 22.092 24 17.595 24 12.297c0-6.627-5.373-12-12-12z"),
                        Width = 15,
                        Height = 15,
                        Stretch = Stretch.Uniform,
                        Fill = new SolidColorBrush(palette.Secondary is SolidColorBrush brush ? brush.Color : Colors.Gray),
                        Margin = new Thickness(0, 0, 5, 0),
                    },
                    new TextBlock { Text = "GitHub" },
                },
            },
            FontFamily = new FontFamily("Segoe UI"),
            FontSize = 11,
            Foreground = palette.Secondary,
            Background = Brushes.Transparent,
            BorderThickness = new Thickness(0),
            Padding = new Thickness(8, 4, 8, 4),
            Cursor = Cursors.Hand,
            ToolTip = "Open GitHub project",
        };
        var buttonChrome = new FrameworkElementFactory(typeof(Border));
        buttonChrome.Name = "GitHubChrome";
        buttonChrome.SetValue(Border.CornerRadiusProperty, new CornerRadius(8));
        buttonChrome.SetValue(Border.BackgroundProperty, Brushes.Transparent);
        buttonChrome.SetValue(Border.PaddingProperty, new Thickness(8, 4, 8, 4));
        var presenter = new FrameworkElementFactory(typeof(ContentPresenter));
        presenter.SetValue(ContentPresenter.HorizontalAlignmentProperty, HorizontalAlignment.Center);
        presenter.SetValue(ContentPresenter.VerticalAlignmentProperty, VerticalAlignment.Center);
        buttonChrome.AppendChild(presenter);
        var template = new ControlTemplate(typeof(Button)) { VisualTree = buttonChrome };
        var hover = new Trigger { Property = Button.IsMouseOverProperty, Value = true };
        hover.Setters.Add(new Setter(Border.BackgroundProperty,
            new SolidColorBrush(Color.FromArgb(24, palette.PrimaryColor.R, palette.PrimaryColor.G, palette.PrimaryColor.B)),
            "GitHubChrome"));
        hover.Setters.Add(new Setter(Border.EffectProperty,
            new System.Windows.Media.Effects.DropShadowEffect
            {
                BlurRadius = 8,
                ShadowDepth = 1,
                Opacity = 0.18,
                Color = Colors.Black,
            },
            "GitHubChrome"));
        template.Triggers.Add(hover);
        github.Template = template;
        github.Click += (_, _) =>
        {
            DismissDetail();
            try
            {
                Process.Start(new ProcessStartInfo
                {
                    FileName = "https://github.com/JaceHwang/codex-usage-sidebar",
                    UseShellExecute = true,
                });
            }
            catch (InvalidOperationException)
            {
            }
        };
        Grid.SetColumn(github, 2);
        footer.Children.Add(github);
        var settings = new Button
        {
            Content = new TextBlock { Text = "\uE713", FontFamily = new FontFamily("Segoe MDL2 Assets"),
                FontSize = 15, Foreground = palette.Secondary },
            Template = template,
            BorderThickness = new Thickness(0),
            Background = Brushes.Transparent,
            Cursor = Cursors.Hand,
            VerticalAlignment = VerticalAlignment.Center,
            ToolTip = latestPresentation?.Language switch
            {
                DisplayLanguage.SimplifiedChinese => "设置",
                DisplayLanguage.TraditionalChinese => "設定",
                _ => "Settings",
            },
        };
        System.Windows.Automation.AutomationProperties.SetName(settings, settings.ToolTip.ToString());
        settings.Click += (_, _) => ShowSettings(settings);
        Grid.SetColumn(settings, 3);
        footer.Children.Add(settings);
        return footer;
    }

    private static FrameworkElement BuildAccountAvatar(
        AccountIdentity? account,
        WpfOverlayPalette palette,
        ImageSource? accountAvatarSource)
    {
        if (accountAvatarSource is not null)
        {
            try
            {
                return new Image
                {
                    Source = accountAvatarSource,
                    Width = 24,
                    Height = 24,
                    Stretch = Stretch.UniformToFill,
                    VerticalAlignment = VerticalAlignment.Center,
                    Clip = new EllipseGeometry(new Point(12, 12), 12, 12),
                };
            }
            catch (Exception)
            {
                // Fall back to an initials avatar when the optional image is unavailable.
            }
        }

        var name = account?.PreferredName;
        var initial = string.IsNullOrWhiteSpace(name) ? "·" : name.Trim()[0].ToString().ToUpperInvariant();
        return new Border
        {
            Width = 24,
            Height = 24,
            CornerRadius = new CornerRadius(12),
            Background = new SolidColorBrush(palette.BadgeColor),
            VerticalAlignment = VerticalAlignment.Center,
            Child = new TextBlock
            {
                Text = initial,
                FontFamily = new FontFamily("Segoe UI"),
                FontSize = 12,
                FontWeight = FontWeights.SemiBold,
                Foreground = palette.Primary,
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center,
                TextAlignment = TextAlignment.Center,
            },
        };
    }

    private void UpdateAccountAvatar(Uri? avatarURL)
    {
        if (Equals(accountAvatarURL, avatarURL)) return;
        accountAvatarURL = avatarURL;
        accountAvatarSource = null;
        if (avatarURL is null) return;
        try
        {
            var image = new BitmapImage(avatarURL);
            image.Freeze();
            accountAvatarSource = image;
        }
        catch (Exception)
        {
            // An optional remote avatar must never prevent the quota card from rendering.
        }
    }

    private static TextBlock BuildDetailValue(string value, Color accent, WpfOverlayPalette palette,
        bool emphasizeCountdown = true)
    {
        var text = new TextBlock
        {
            FontFamily = new FontFamily("Segoe UI"),
            FontSize = OverlayVisualMetrics.DetailValueFontSize,
            TextAlignment = TextAlignment.Right,
            TextWrapping = TextWrapping.Wrap,
        };
        var segments = emphasizeCountdown ? QuotaCountdownSegmenter.Segments(value)
            : new[] { new QuotaCountdownSegment(value, QuotaCountdownSegmentRole.Plain) };
        foreach (var segment in segments)
        {
            var run = new System.Windows.Documents.Run(segment.Text)
            {
                BaselineAlignment = BaselineAlignment.Baseline,
            };
            switch (segment.Role)
            {
                case QuotaCountdownSegmentRole.Digits:
                    run.FontSize = OverlayVisualMetrics.CountdownDigitFontSize;
                    run.FontWeight = FontWeights.SemiBold;
                    run.Foreground = new SolidColorBrush(accent);
                    break;
                case QuotaCountdownSegmentRole.Unit:
                    run.FontSize = OverlayVisualMetrics.CountdownUnitFontSize;
                    run.FontWeight = FontWeights.Medium;
                    run.Foreground = palette.Secondary;
                    break;
                case QuotaCountdownSegmentRole.Punctuation:
                case QuotaCountdownSegmentRole.Suffix:
                    run.FontSize = OverlayVisualMetrics.CountdownUnitFontSize;
                    run.FontWeight = FontWeights.Normal;
                    run.Foreground = palette.Secondary;
                    break;
                default:
                    run.FontSize = OverlayVisualMetrics.DetailValueFontSize;
                    run.FontWeight = FontWeights.Normal;
                    run.Foreground = palette.Primary;
                    break;
            }
            text.Inlines.Add(run);
        }
        return text;
    }

    private static Window CreatePassiveWindow(UIElement content)
    {
        var window = new Window
        {
            AllowsTransparency = true,
            Background = Brushes.Transparent,
            WindowStyle = WindowStyle.None,
            ResizeMode = ResizeMode.NoResize,
            ShowActivated = false,
            ShowInTaskbar = false,
            Focusable = false,
            UseLayoutRounding = true,
            SnapsToDevicePixels = true,
            Content = content,
        };
        window.SourceInitialized += (_, _) =>
        {
            var handle = new WindowInteropHelper(window).Handle;
            var style = GetWindowLongPtr(handle, ExtendedWindowStyle).ToInt64();
            SetWindowLongPtr(handle, ExtendedWindowStyle, new IntPtr(style | NoActivateStyle | ToolWindowStyle));
            HwndSource.FromHwnd(handle)?.AddHook(NoActivateWindowHook);
        };
        return window;
    }

    private static IntPtr NoActivateWindowHook(
        IntPtr window,
        int message,
        IntPtr wordParameter,
        IntPtr longParameter,
        ref bool handled)
    {
        if (message != MouseActivateMessage) return IntPtr.Zero;
        handled = true;
        return new IntPtr(MouseActivateNoActivate);
    }

    private static void PositionPhysical(Window window, RectD frame)
    {
        var handle = new WindowInteropHelper(window).Handle;
        if (handle == IntPtr.Zero) return;
        if (!SetWindowPos(
            handle,
            IntPtr.Zero,
            checked((int)Math.Round(frame.X)),
            checked((int)Math.Round(frame.Y)),
            checked((int)Math.Round(frame.Width)),
            checked((int)Math.Round(frame.Height)),
            OverlayWindowPolicy.PositionFlags))
        {
            throw new Win32Exception(Marshal.GetLastWin32Error(), "Unable to position the overlay window.");
        }
    }

    private static void SetOwner(Window window, IntPtr owner)
    {
        var helper = new WindowInteropHelper(window);
        if (helper.Owner != owner) helper.Owner = owner;
    }

    private ValueTask OnUiAsync(Action action)
    {
        if (indicator.Dispatcher.CheckAccess())
        {
            action();
            return ValueTask.CompletedTask;
        }
        return new ValueTask(indicator.Dispatcher.InvokeAsync(action).Task);
    }

    private static RectD? WorkAreaFor(IntPtr owner)
    {
        var monitor = MonitorFromWindow(owner, 2);
        var info = new MonitorInfo { Size = Marshal.SizeOf<MonitorInfo>() };
        if (monitor == IntPtr.Zero || !GetMonitorInfo(monitor, ref info))
        {
            return null;
        }
        return new RectD(
            info.Work.Left,
            info.Work.Top,
            info.Work.Right - info.Work.Left,
            info.Work.Bottom - info.Work.Top);
    }

    private static bool UsableWorkArea(RectD workArea) =>
        double.IsFinite(workArea.X)
        && double.IsFinite(workArea.Y)
        && double.IsFinite(workArea.Width)
        && double.IsFinite(workArea.Height)
        && workArea.Width > 0
        && workArea.Height > 0;

    private static WpfOverlayPalette ResolvePalette(PointD probePoint)
    {
        if (SystemParameters.HighContrast)
        {
            return WpfOverlayPalette.HighContrast;
        }
        var screen = GetDC(IntPtr.Zero);
        if (screen == IntPtr.Zero)
        {
            return WpfOverlayPalette.Light;
        }
        try
        {
            var color = GetPixel(
                screen,
                checked((int)Math.Round(probePoint.X)),
                checked((int)Math.Round(probePoint.Y)));
            if (color == uint.MaxValue)
            {
                return WpfOverlayPalette.Light;
            }
            var kind = OverlayThemePolicy.Resolve(
                (byte)(color & 0xff),
                (byte)((color >> 8) & 0xff),
                (byte)((color >> 16) & 0xff),
                highContrast: false);
            return kind == OverlayThemeKind.Dark
                ? WpfOverlayPalette.Dark
                : WpfOverlayPalette.Light;
        }
        finally
        {
            ReleaseDC(IntPtr.Zero, screen);
        }
    }

    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")]
    private static extern IntPtr GetWindowLongPtr(IntPtr window, int index);

    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW")]
    private static extern IntPtr SetWindowLongPtr(IntPtr window, int index, IntPtr value);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetWindowPos(
        IntPtr window,
        IntPtr insertAfter,
        int x,
        int y,
        int width,
        int height,
        uint flags);

    [DllImport("user32.dll")]
    private static extern IntPtr MonitorFromWindow(IntPtr window, uint flags);

    [DllImport("user32.dll")]
    private static extern IntPtr MonitorFromPoint(NativePoint point, uint flags);

    [DllImport("shcore.dll")]
    private static extern int GetDpiForMonitor(IntPtr monitor, int type, out uint dpiX, out uint dpiY);

    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetMonitorInfo(IntPtr monitor, ref MonitorInfo info);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetCursorPos(out NativePoint point);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetWindowRect(IntPtr window, out NativeRect rectangle);

    [DllImport("user32.dll")]
    private static extern IntPtr GetDC(IntPtr window);

    [DllImport("user32.dll")]
    private static extern int ReleaseDC(IntPtr window, IntPtr deviceContext);

    [DllImport("gdi32.dll")]
    private static extern uint GetPixel(IntPtr deviceContext, int x, int y);

    [StructLayout(LayoutKind.Sequential)]
    private struct NativePoint
    {
        internal int X;
        internal int Y;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct NativeRect
    {
        internal int Left;
        internal int Top;
        internal int Right;
        internal int Bottom;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
    private struct MonitorInfo
    {
        internal int Size;
        internal NativeRect Monitor;
        internal NativeRect Work;
        internal uint Flags;
    }
}

internal sealed record WpfOverlayPalette(
    Color PrimaryColor,
    Color BadgeColor,
    Brush Primary,
    Brush Secondary,
    Brush Surface,
    Brush Border,
    Brush Track,
    Brush Badge)
{
    internal static WpfOverlayPalette Light { get; } = Create(
        Color.FromRgb(23, 23, 23),
        Color.FromRgb(112, 112, 112),
        Color.FromRgb(255, 255, 255),
        Color.FromRgb(208, 208, 208),
        Color.FromRgb(231, 231, 231),
        Color.FromRgb(0, 122, 255));

    internal static WpfOverlayPalette Dark { get; } = Create(
        Color.FromRgb(230, 230, 230),
        Color.FromRgb(154, 154, 154),
        Color.FromRgb(30, 30, 30),
        Color.FromRgb(63, 63, 63),
        Color.FromRgb(58, 58, 58),
        Color.FromRgb(10, 132, 255));

    internal static WpfOverlayPalette HighContrast { get; } = new(
        SystemColors.WindowTextColor,
        SystemColors.HighlightColor,
        SystemColors.WindowTextBrush,
        SystemColors.GrayTextBrush,
        SystemColors.WindowBrush,
        SystemColors.ActiveBorderBrush,
        SystemColors.ControlBrush,
        SystemColors.HighlightBrush);

    private static WpfOverlayPalette Create(
        Color primary,
        Color secondary,
        Color surface,
        Color border,
        Color track,
        Color badge) => new(
            primary,
            badge,
            Brush(primary),
            Brush(secondary),
            Brush(surface),
            Brush(border),
            Brush(track),
            Brush(badge));

    private static SolidColorBrush Brush(Color color)
    {
        var brush = new SolidColorBrush(color);
        brush.Freeze();
        return brush;
    }
}
#endif
