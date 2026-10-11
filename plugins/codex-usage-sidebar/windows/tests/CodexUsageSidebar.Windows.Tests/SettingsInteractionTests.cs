#if WINDOWS
using System.Reflection;
using System.Windows;
using System.Windows.Controls;
using CodexUsageSidebar.Core;

namespace CodexUsageSidebar.Windows.Tests;

[TestClass]
public sealed class SettingsInteractionTests
{
    [STATestMethod]
    public async Task SwitchingToAutomaticPlacementRequestsATitlebarRescan()
    {
        Application.ResourceAssembly ??= typeof(WpfOverlaySurface).Assembly;
        var preferences = new IndicatorPlacementPreferences { Mode = IndicatorPlacementMode.Free };
        var surface = new WpfOverlaySurface(DisplayLanguage.English, TimeZoneInfo.Utc, preferences);
        var refreshEvent = typeof(WpfOverlaySurface).GetEvent("TitlebarRefreshRequested");

        Assert.IsNotNull(refreshEvent);
        var refreshes = 0;
        refreshEvent.AddEventHandler(surface, (Action)(() => refreshes++));
        var method = typeof(WpfOverlaySurface).GetMethod("SetPlacementModeAsync",
            BindingFlags.Instance | BindingFlags.NonPublic)!;

        await (Task)method.Invoke(surface, [IndicatorPlacementMode.Automatic])!;

        Assert.AreEqual(IndicatorPlacementMode.Automatic, preferences.Mode);
        Assert.AreEqual(1, refreshes);
    }

    [STATestMethod]
    public void DarkSettingsMenuOverridesSystemMenuAndSelectionColors()
    {
        Application.ResourceAssembly ??= typeof(WpfOverlaySurface).Assembly;
        var surface = new WpfOverlaySurface(DisplayLanguage.English, TimeZoneInfo.Utc);
        const BindingFlags flags = BindingFlags.Instance | BindingFlags.NonPublic;
        var type = typeof(WpfOverlaySurface);
        type.GetField("palette", flags)!.SetValue(surface, WpfOverlayPalette.Dark);
        try
        {
            var menu = (ContextMenu)type.GetMethod("CreateMenu", flags)!.Invoke(surface, [new Button(), 176d])!;

            Assert.AreSame(WpfOverlayPalette.Dark.Surface, menu.Resources[SystemColors.MenuBrushKey]);
            Assert.AreSame(WpfOverlayPalette.Dark.Primary, menu.Resources[SystemColors.MenuTextBrushKey]);
            Assert.AreSame(WpfOverlayPalette.Dark.Track, menu.Resources[SystemColors.HighlightBrushKey]);
            Assert.AreSame(WpfOverlayPalette.Dark.Primary, menu.Resources[SystemColors.HighlightTextBrushKey]);
            Assert.AreSame(WpfOverlayPalette.Dark.Border, menu.Resources[SystemColors.ActiveBorderBrushKey]);
            Assert.IsNotNull(menu.Style, "The menu needs its own popup chrome instead of the Windows menu template.");
            Assert.IsInstanceOfType(menu.Style.Setters.OfType<Setter>()
                .Single(setter => setter.Property == Control.TemplateProperty).Value, typeof(ControlTemplate));
            Assert.IsNotNull(menu.ItemContainerStyle, "Menu rows need their own hover and border template.");
            Assert.IsInstanceOfType(menu.ItemContainerStyle.Setters.OfType<Setter>()
                .Single(setter => setter.Property == Control.TemplateProperty).Value, typeof(ControlTemplate));
        }
        finally
        {
            ((Window)type.GetField("indicator", flags)!.GetValue(surface)!).Close();
            ((Window)type.GetField("detail", flags)!.GetValue(surface)!).Close();
        }
    }

    [STATestMethod]
    public void OpeningSettingsPreservesTheExplicitDetailLock()
    {
        Application.ResourceAssembly ??= typeof(WpfOverlaySurface).Assembly;
        var surface = new WpfOverlaySurface(DisplayLanguage.English, TimeZoneInfo.Utc);
        const BindingFlags flags = BindingFlags.Instance | BindingFlags.NonPublic;
        var type = typeof(WpfOverlaySurface);
        var stateField = type.GetField("interaction", flags)!;
        var locked = DetailInteractionState.Initial.ToggleLockedOpen(true);
        stateField.SetValue(surface, locked);
        var now = DateTimeOffset.UtcNow;
        type.GetField("latestPresentation", flags)!.SetValue(surface,
            new OverlayPresentation(IntPtr.Zero, 1, DisplayLanguage.English,
                new AllowanceSnapshot(10, 90, now.AddHours(1), now), default,
                SnapshotFreshness.Fresh, default));
        try
        {
            type.GetMethod("ShowSettings", flags)!.Invoke(surface, [new Button()]);
            var after = (DetailInteractionState)stateField.GetValue(surface)!;
            Assert.IsTrue(after.IsLockedOpen, "Opening settings must not unlock the detail card.");
            Assert.AreEqual(locked.IsPinned, after.IsPinned);
            Assert.IsTrue(after.PointerPressed(false, false).ShouldShowDetail);
        }
        finally
        {
            if (type.GetField("settingsMenu", flags)!.GetValue(surface) is ContextMenu menu)
                menu.IsOpen = false;
            ((Window)type.GetField("indicator", flags)!.GetValue(surface)!).Close();
            ((Window)type.GetField("detail", flags)!.GetValue(surface)!).Close();
        }
    }
}
#endif
