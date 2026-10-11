#if WINDOWS
using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Windows.Interop;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Media;
using CodexUsageSidebar.Core;

namespace CodexUsageSidebar.Windows;

public sealed partial class WpfOverlaySurface
{
    private ContextMenu? settingsMenu;
    private OutsideClickMonitor? outsideClickMonitor;
    public event Action? ReloadRequested;
    public event Action? TitlebarRefreshRequested;
    public event Action? QuitRequested;

    private void DismissDetail()
    {
        if (settingsMenu is not null) settingsMenu.IsOpen = false;
        interaction = new DetailInteractionState(false, IsPointerInside(indicator), true, false);
        detail.Hide();
        UpdateOutsideClickMonitor();
    }

    private void UpdateOutsideClickMonitor()
    {
        if (!detail.IsVisible || !interaction.IsPinned)
        {
            outsideClickMonitor?.Dispose();
            outsideClickMonitor = null;
            return;
        }
        if (outsideClickMonitor is not null) return;
        try
        {
            outsideClickMonitor = new OutsideClickMonitor(indicator.Dispatcher, point =>
            {
                var inside = ContainsScreenPoint(indicator, point) || ContainsScreenPoint(detail, point);
                var insideMenu = false;
                if (settingsMenu?.IsOpen == true)
                {
                    var window = WindowFromPoint(new NativePoint { X = (int)point.X, Y = (int)point.Y });
                    _ = GetWindowThreadProcessId(window, out var processId);
                    insideMenu = processId == (uint)Environment.ProcessId;
                }
                interaction = interaction.PointerPressed(inside, insideMenu);
                if (!interaction.ShouldShowDetail) DismissDetail();
            });
        }
        catch (Win32Exception error)
        {
            Trace.TraceWarning("Outside-click monitor unavailable: {0}", error.NativeErrorCode);
        }
    }

    private static bool ContainsScreenPoint(Window window, PointD point)
    {
        if (!window.IsVisible || !GetWindowRect(new WindowInteropHelper(window).Handle, out var frame)) return false;
        return OverlayPointerPolicy.IsInside(point, new Core.RectD(frame.Left, frame.Top,
            frame.Right - frame.Left, frame.Bottom - frame.Top));
    }

    [DllImport("user32.dll")]
    private static extern IntPtr WindowFromPoint(NativePoint point);
    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);

    private void ShowSettings(FrameworkElement target)
    {
        if (latestPresentation is null) return;
        if (settingsMenu?.IsOpen == true)
        {
            settingsMenu.IsOpen = false;
            return;
        }
        // RefreshInteraction keeps the card stable while the menu is open.
        // Preserve the user's pin and explicit lock, as on macOS.
        var menu = CreateMenu(target, 176);
        var rowStyle = (Style)menu.ItemContainerStyle;
        foreach (var descriptor in QuotaSettingsMenu.Create(latestPresentation.Language, placementPreferences.Mode))
        {
            var item = MenuRow(descriptor.Label, descriptor.Icon, 176, rowStyle);
            if (descriptor.Children is { } choices)
            {
                foreach (var choice in choices)
                {
                    var child = MenuRow(choice.Label, choice.Icon, 156, rowStyle, choice.Selected);
                    child.Click += async (_, _) =>
                    {
                        menu.IsOpen = false;
                        await SetPlacementModeAsync(choice.Mode);
                    };
                    item.Items.Add(child);
                }
            }
            else
            {
                item.Click += (_, _) =>
                {
                    DismissDetail();
                    switch (descriptor.Action)
                    {
                        case QuotaSettingsAction.CheckUpdates:
                            try { Process.Start(new ProcessStartInfo("https://github.com/JaceHwang/codex-usage-sidebar/releases") { UseShellExecute = true }); }
                            catch (Exception error) when (error is Win32Exception or InvalidOperationException)
                            { Trace.TraceWarning("Unable to open releases: {0}", error.GetType().Name); }
                            break;
                        case QuotaSettingsAction.Reload: ReloadRequested?.Invoke(); break;
                        case QuotaSettingsAction.Quit: QuitRequested?.Invoke(); break;
                    }
                };
            }
            menu.Items.Add(item);
        }
        settingsMenu = menu;
        menu.IsOpen = true;
        UpdateOutsideClickMonitor();
    }

    private void ShowPositionMenu(FrameworkElement target)
    {
        if (latestPresentation is null) return;
        if (settingsMenu?.IsOpen == true)
        {
            settingsMenu.IsOpen = false;
            return;
        }
        interaction = new DetailInteractionState(false, IsPointerInside(indicator), true, false);
        detail.Hide();
        var menu = CreateMenu(target, 176);
        var rowStyle = (Style)menu.ItemContainerStyle;
        foreach (var choice in QuotaSettingsMenu.CreatePlacementItems(
                     latestPresentation.Language,
                     placementPreferences.Mode))
        {
            var item = MenuRow(choice.Label, choice.Icon, 176, rowStyle, choice.Selected);
            item.Click += async (_, _) =>
            {
                menu.IsOpen = false;
                await SetPlacementModeAsync(choice.Mode);
            };
            menu.Items.Add(item);
        }
        settingsMenu = menu;
        menu.IsOpen = true;
        UpdateOutsideClickMonitor();
    }

    private ContextMenu CreateMenu(FrameworkElement target, double width)
    {
        var menu = new ContextMenu
        {
            Width = width,
            FontFamily = new FontFamily("Segoe UI"),
            FontSize = 12,
            Foreground = palette.Primary,
            Background = palette.Surface,
            BorderBrush = palette.Border,
            BorderThickness = new Thickness(0.5),
            PlacementTarget = target,
            Placement = System.Windows.Controls.Primitives.PlacementMode.Custom,
            CustomPopupPlacementCallback = (popup, anchor, _) =>
            [
                new CustomPopupPlacement(new Point(anchor.Width - popup.Width, -popup.Height - 6), PopupPrimaryAxis.Horizontal),
                new CustomPopupPlacement(new Point(anchor.Width - popup.Width, anchor.Height + 6), PopupPrimaryAxis.Horizontal),
            ],
        };

        // WPF's stock MenuItem template uses these system resources for its
        // popup surface, hover state, and separator borders. Override them at
        // the menu scope so both the top-level menu and its submenus follow
        // the detected Codex theme instead of the Windows light theme.
        menu.Resources[SystemColors.MenuBrushKey] = palette.Surface;
        menu.Resources[SystemColors.MenuTextBrushKey] = palette.Primary;
        menu.Resources[SystemColors.ControlBrushKey] = palette.Surface;
        menu.Resources[SystemColors.ControlTextBrushKey] = palette.Primary;
        menu.Resources[SystemColors.HighlightBrushKey] = palette.Track;
        menu.Resources[SystemColors.HighlightTextBrushKey] = palette.Primary;
        menu.Resources[SystemColors.ActiveBorderBrushKey] = palette.Border;
        var rowStyle = BuildMenuRowStyle(palette);
        menu.Style = BuildMenuStyle(palette);
        menu.ItemContainerStyle = rowStyle;
        menu.Resources[typeof(MenuItem)] = rowStyle;
        return menu;
    }

    private static Style BuildMenuStyle(WpfOverlayPalette palette)
    {
        var chrome = new FrameworkElementFactory(typeof(Border));
        chrome.SetValue(Border.BackgroundProperty, palette.Surface);
        chrome.SetValue(Border.BorderBrushProperty, palette.Border);
        chrome.SetValue(Border.BorderThicknessProperty, new Thickness(0.5));
        chrome.SetValue(Border.PaddingProperty, new Thickness(2));
        chrome.AppendChild(new FrameworkElementFactory(typeof(ItemsPresenter)));
        var template = new ControlTemplate(typeof(ContextMenu)) { VisualTree = chrome };
        var style = new Style(typeof(ContextMenu));
        style.Setters.Add(new Setter(Control.TemplateProperty, template));
        return style;
    }

    private static Style BuildMenuRowStyle(WpfOverlayPalette palette)
    {
        var root = new FrameworkElementFactory(typeof(Grid));
        var chrome = new FrameworkElementFactory(typeof(Border));
        chrome.Name = "MenuRowChrome";
        chrome.SetValue(Border.BackgroundProperty, palette.Surface);
        chrome.SetValue(Border.BorderBrushProperty, Brushes.Transparent);
        chrome.SetValue(Border.BorderThicknessProperty, new Thickness(1));
        chrome.SetValue(Border.PaddingProperty, new Thickness(8, 0, 8, 0));
        var row = new FrameworkElementFactory(typeof(DockPanel));
        var icon = new FrameworkElementFactory(typeof(ContentPresenter));
        icon.SetValue(ContentPresenter.ContentSourceProperty, "Icon");
        icon.SetValue(FrameworkElement.WidthProperty, 24d);
        icon.SetValue(FrameworkElement.VerticalAlignmentProperty, VerticalAlignment.Center);
        icon.SetValue(DockPanel.DockProperty, Dock.Left);
        row.AppendChild(icon);
        var arrow = new FrameworkElementFactory(typeof(TextBlock));
        arrow.Name = "SubmenuArrow";
        arrow.SetValue(TextBlock.TextProperty, "›");
        arrow.SetValue(TextBlock.VisibilityProperty, Visibility.Collapsed);
        arrow.SetValue(TextBlock.ForegroundProperty, palette.Secondary);
        arrow.SetValue(TextBlock.FontSizeProperty, 16d);
        arrow.SetValue(TextBlock.VerticalAlignmentProperty, VerticalAlignment.Center);
        arrow.SetValue(DockPanel.DockProperty, Dock.Right);
        row.AppendChild(arrow);
        var header = new FrameworkElementFactory(typeof(ContentPresenter));
        header.SetValue(ContentPresenter.ContentSourceProperty, "Header");
        header.SetValue(FrameworkElement.VerticalAlignmentProperty, VerticalAlignment.Center);
        row.AppendChild(header);
        chrome.AppendChild(row);
        root.AppendChild(chrome);

        var popup = new FrameworkElementFactory(typeof(Popup));
        popup.SetValue(Popup.AllowsTransparencyProperty, true);
        popup.SetValue(Popup.PlacementProperty, System.Windows.Controls.Primitives.PlacementMode.Right);
        popup.SetBinding(Popup.IsOpenProperty, new System.Windows.Data.Binding("IsSubmenuOpen")
        {
            RelativeSource = new System.Windows.Data.RelativeSource(System.Windows.Data.RelativeSourceMode.TemplatedParent),
            Mode = System.Windows.Data.BindingMode.TwoWay,
        });
        var submenuChrome = new FrameworkElementFactory(typeof(Border));
        submenuChrome.SetValue(Border.BackgroundProperty, palette.Surface);
        submenuChrome.SetValue(Border.BorderBrushProperty, palette.Border);
        submenuChrome.SetValue(Border.BorderThicknessProperty, new Thickness(0.5));
        submenuChrome.SetValue(Border.PaddingProperty, new Thickness(2));
        submenuChrome.AppendChild(new FrameworkElementFactory(typeof(ItemsPresenter)));
        popup.AppendChild(submenuChrome);
        root.AppendChild(popup);

        var template = new ControlTemplate(typeof(MenuItem)) { VisualTree = root };
        var hasItems = new Trigger { Property = MenuItem.HasItemsProperty, Value = true };
        hasItems.Setters.Add(new Setter(TextBlock.VisibilityProperty, Visibility.Visible, "SubmenuArrow"));
        template.Triggers.Add(hasItems);
        foreach (var property in new[] { MenuItem.IsHighlightedProperty, MenuItem.IsSubmenuOpenProperty })
        {
            var highlighted = new Trigger { Property = property, Value = true };
            highlighted.Setters.Add(new Setter(Border.BackgroundProperty, palette.Track, "MenuRowChrome"));
            highlighted.Setters.Add(new Setter(Border.BorderBrushProperty, palette.Border, "MenuRowChrome"));
            template.Triggers.Add(highlighted);
        }
        var style = new Style(typeof(MenuItem));
        style.Setters.Add(new Setter(Control.TemplateProperty, template));
        style.Setters.Add(new Setter(Control.ForegroundProperty, palette.Primary));
        style.Setters.Add(new Setter(Control.BackgroundProperty, palette.Surface));
        style.Setters.Add(new Setter(Control.BorderBrushProperty, palette.Border));
        return style;
    }

    private MenuItem MenuRow(string title, string icon, double width, Style rowStyle, bool selected = false)
    {
        var header = new Grid { MinWidth = width - 72 };
        header.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        header.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(14) });
        header.Children.Add(new TextBlock { Text = title, VerticalAlignment = VerticalAlignment.Center });
        if (selected)
        {
            var check = new TextBlock { Text = "✓", HorizontalAlignment = HorizontalAlignment.Right };
            Grid.SetColumn(check, 1);
            header.Children.Add(check);
        }
        var item = new MenuItem
        {
            Header = header,
            Icon = new TextBlock { Text = icon, FontFamily = new FontFamily("Segoe MDL2 Assets"), FontSize = 14,
                Foreground = palette.Secondary, VerticalAlignment = VerticalAlignment.Center },
            Height = 32,
            Width = width,
            Style = rowStyle,
            Foreground = palette.Primary,
            Background = palette.Surface,
        };
        System.Windows.Automation.AutomationProperties.SetName(item, title);
        return item;
    }
}
#endif
