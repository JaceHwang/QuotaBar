using CodexUsageSidebar.Core;

namespace CodexUsageSidebar.Windows;

public sealed class WindowsHostCoordinator
{
    private readonly IHostWindowLocator locator;
    private readonly ITitlebarScanner scanner;
    private readonly IOverlaySurface overlay;
    private readonly Func<DateTimeOffset> now;
    private readonly IRuntimeStateStore? runtimeStateStore;
    private readonly ISafeDockPreferencesStore? safeDockPreferencesStore;
    private readonly CompatibilityStateMachine compatibilityStateMachine;
    private SafeDockPreferences safeDockPreferences;
    private string? lastBuildIdentity;
    private DisplayLanguage? lastLanguage;

    public WindowsHostCoordinator(
        IHostWindowLocator locator,
        ITitlebarScanner scanner,
        IOverlaySurface overlay,
        Func<DateTimeOffset>? now = null,
        IRuntimeStateStore? runtimeStateStore = null,
        SafeDockPreferences? safeDockPreferences = null,
        ISafeDockPreferencesStore? safeDockPreferencesStore = null)
    {
        this.locator = locator;
        this.scanner = scanner;
        this.overlay = overlay;
        this.now = now ?? (() => DateTimeOffset.Now);
        this.runtimeStateStore = runtimeStateStore;
        this.safeDockPreferences = safeDockPreferences ?? SafeDockPreferences.Default;
        this.safeDockPreferencesStore = safeDockPreferencesStore;
        compatibilityStateMachine = new CompatibilityStateMachine(this.safeDockPreferences);
        if (overlay is ISafeDockOverlaySurface safeDockOverlay)
        {
            safeDockOverlay.SafeDockPreferencesChanged += ApplySafeDockPreferencesAsync;
        }
    }

    public CompatibilityDecision? LastCompatibilityDecision { get; private set; }

    public ValueTask UpdateSafeDockPreferencesAsync(SafeDockPreferences preferences, CancellationToken cancellationToken) =>
        ApplySafeDockPreferencesAsync(preferences, cancellationToken);

    public ValueTask<HostRuntimeState> ReconcileAsync(
        AllowanceSnapshot? snapshot,
        CancellationToken cancellationToken) =>
        ReconcileAsync(snapshot, DisplayLanguage.SimplifiedChinese, cancellationToken);

    public async ValueTask<HostRuntimeState> ReconcileAsync(
        AllowanceSnapshot? snapshot,
        DisplayLanguage language,
        CancellationToken cancellationToken,
        TokenUsageSnapshot? tokenUsage = null,
        AccountIdentity? account = null)
    {
        var observedAt = now();
        var host = await locator.FindAsync(cancellationToken).ConfigureAwait(false);
        if (host is null)
        {
            lastBuildIdentity = null;
            lastLanguage = null;
            await overlay.HideAsync(cancellationToken).ConfigureAwait(false);
            return await CompleteAsync(
                HostRuntimeState.WaitingForCodex,
                new CompatibilityDecision(
                    SemanticCompatibility.Unknown,
                    ProfileCompatibility.Invalid,
                    SafeDockPlacement.None,
                    CompatibilityFailureCode.MissingCodexWindow),
                cancellationToken).ConfigureAwait(false);
        }

        if (!host.IsForeground && !overlay.HasForegroundWindow)
        {
            await overlay.HideAsync(cancellationToken).ConfigureAwait(false);
            return await CompleteAsync(
                HostRuntimeState.Hidden,
                new CompatibilityDecision(SemanticCompatibility.Unknown, ProfileCompatibility.Unknown,
                    SafeDockPlacement.None, CompatibilityFailureCode.HostNotForeground),
                cancellationToken).ConfigureAwait(false);
        }

        if (lastBuildIdentity is not null
            && !string.Equals(lastBuildIdentity, host.BuildIdentity, StringComparison.Ordinal))
        {
            scanner.Invalidate();
        }
        lastBuildIdentity = host.BuildIdentity;
        if (lastLanguage is not null && lastLanguage != language)
        {
            scanner.Invalidate();
        }
        lastLanguage = language;

        if (snapshot is null)
        {
            compatibilityStateMachine.Transition(
                new CompatibilityDecision(
                    SemanticCompatibility.Unknown,
                    ProfileCompatibility.Unknown,
                    SafeDockPlacement.None,
                    CompatibilityFailureCode.MissingQuotaSnapshot),
                hasLiveQuota: false,
                hasValidCodexHost: true,
                observedAt);
            await overlay.HideAsync(cancellationToken).ConfigureAwait(false);
            return await CompleteAsync(
                HostRuntimeState.Hidden,
                new CompatibilityDecision(
                    SemanticCompatibility.Unknown,
                    ProfileCompatibility.Unknown,
                    SafeDockPlacement.None,
                    CompatibilityFailureCode.MissingQuotaSnapshot),
                cancellationToken).ConfigureAwait(false);
        }

        var freshness = RefreshPolicy.Freshness(snapshot.ReceivedAt, observedAt);
        if (freshness == SnapshotFreshness.Hidden)
        {
            await overlay.HideAsync(cancellationToken).ConfigureAwait(false);
            return await CompleteAsync(
                HostRuntimeState.Hidden,
                new CompatibilityDecision(
                    SemanticCompatibility.Valid,
                    ProfileCompatibility.Validated,
                    SafeDockPlacement.None,
                    CompatibilityFailureCode.None),
                cancellationToken).ConfigureAwait(false);
        }

        var titlebar = scanner.TryGetCurrent(host);
        if (titlebar is null)
        {
            try
            {
                titlebar = await scanner.ScanAsync(host, cancellationToken).ConfigureAwait(false);
            }
            catch (HostSettingsPageDetectedException)
            {
                await overlay.HideAsync(cancellationToken).ConfigureAwait(false);
                return await CompleteAsync(
                    HostRuntimeState.Hidden,
                    new CompatibilityDecision(
                        SemanticCompatibility.Valid,
                        ProfileCompatibility.Validated,
                        SafeDockPlacement.None,
                        CompatibilityFailureCode.None),
                    cancellationToken).ConfigureAwait(false);
            }
            catch (InvalidSelectorCatalogException)
            {
                return await HandleUnresolvedTitlebarAsync(
                    host, snapshot, language, freshness, tokenUsage, account,
                    CompatibilityFailureCode.InvalidCatalog, observedAt, cancellationToken).ConfigureAwait(false);
            }
            catch (WindowsDeviceValidationRequiredException)
            {
                titlebar = scanner.TryGetRetained(host);
                if (titlebar is null)
                {
                    return await HandleUnresolvedTitlebarAsync(
                        host, snapshot, language, freshness, tokenUsage, account,
                        CompatibilityFailureCode.UiaUnavailable, observedAt, cancellationToken).ConfigureAwait(false);
                }
            }
            catch (OperationCanceledException)
            {
                throw;
            }
            catch (Exception)
            {
                titlebar = scanner.TryGetRetained(host);
                if (titlebar is null)
                {
                    return await HandleUnresolvedTitlebarAsync(
                        host, snapshot, language, freshness, tokenUsage, account,
                        CompatibilityFailureCode.UiaUnavailable, observedAt, cancellationToken).ConfigureAwait(false);
                }
            }
        }

        var scale = host.DpiScale;
        var indicatorHeight = titlebar.OpenLocationBounds.Height / scale;
        var indicatorWidth = (overlay is IIndicatorSizeProvider measured
            ? measured.MeasureIndicatorWidth(snapshot, language, indicatorHeight)
            : OverlayVisualMetrics.IndicatorWidthForHeight(indicatorHeight)) * scale;
        var automatic = PlacementResolver.ResolveAutomatic(host.Bounds, titlebar.ToolbarBounds,
            titlebar.OpenLocationBounds, titlebar.TitleBounds, indicatorWidth, scale,
            titlebar.AllInteractiveObstacles);
        var placement = automatic?.Placement;
        var switchToFree = automatic?.SwitchToFree ?? false;
        if (placement is { } located && titlebar.RightToolbarBounds.Width > 0
            && located.Frame.X >= titlebar.RightToolbarBounds.X
            && located.Frame.Right <= titlebar.RightToolbarBounds.Right
            && located.Frame.Y >= titlebar.RightToolbarBounds.Y
            && located.Frame.Bottom <= titlebar.RightToolbarBounds.Bottom)
        {
            placement = located with { Surface = PlacementSurface.RightToolbar };
        }
        if (placement is null)
        {
            return await HandleUnresolvedTitlebarAsync(
                host, snapshot, language, freshness, tokenUsage, account,
                CompatibilityFailureCode.NoCollisionFreeSlot, observedAt, cancellationToken,
                SemanticCompatibility.Valid, ProfileCompatibility.Validated,
                HostRuntimeState.Hidden).ConfigureAwait(false);
        }

        var titlebarDecision = new CompatibilityDecision(
            SemanticCompatibility.Valid,
            ProfileCompatibility.Validated,
            SafeDockPlacement.Titlebar,
            CompatibilityFailureCode.None);
        var transition = compatibilityStateMachine.Transition(
            titlebarDecision, hasLiveQuota: true, hasValidCodexHost: true, observedAt);
        if (transition.ShouldShowSafeDock)
        {
            return await ShowSafeDockAsync(
                host, snapshot, language, freshness, tokenUsage, account, titlebarDecision, cancellationToken).ConfigureAwait(false);
        }

        await overlay.ShowAsync(
            new OverlayPresentation(
                host.Handle,
                host.DpiScale,
                language,
                snapshot,
                placement.Value,
                freshness,
                new PointD(
                    titlebar.ToolbarBounds.X + (4 * scale),
                    titlebar.ToolbarBounds.Y + (4 * scale)),
                tokenUsage,
                account,
                Version: QuotaDetailFormatter.ProductVersion,
                SwitchToFree: switchToFree),
            cancellationToken).ConfigureAwait(false);
        return await CompleteAsync(HostRuntimeState.Visible, titlebarDecision, cancellationToken).ConfigureAwait(false);
    }

    private async ValueTask<HostRuntimeState> HandleUnresolvedTitlebarAsync(
        HostWindowSnapshot host,
        AllowanceSnapshot snapshot,
        DisplayLanguage language,
        SnapshotFreshness freshness,
        TokenUsageSnapshot? tokenUsage,
        AccountIdentity? account,
        CompatibilityFailureCode failureCode,
        DateTimeOffset observedAt,
        CancellationToken cancellationToken,
        SemanticCompatibility semantic = SemanticCompatibility.Invalid,
        ProfileCompatibility profile = ProfileCompatibility.Invalid,
        HostRuntimeState unresolvedState = HostRuntimeState.DeviceValidationRequired)
    {
        var decision = new CompatibilityDecision(semantic, profile, SafeDockPlacement.None, failureCode);
        var transition = compatibilityStateMachine.Transition(
            decision, hasLiveQuota: true, hasValidCodexHost: true, observedAt);
        if (transition.ShouldShowSafeDock)
        {
            return await ShowSafeDockAsync(
                host, snapshot, language, freshness, tokenUsage, account, decision, cancellationToken).ConfigureAwait(false);
        }

        await overlay.HideAsync(cancellationToken).ConfigureAwait(false);
        return await CompleteAsync(unresolvedState, decision, cancellationToken).ConfigureAwait(false);
    }

    private async ValueTask<HostRuntimeState> ShowSafeDockAsync(
        HostWindowSnapshot host,
        AllowanceSnapshot snapshot,
        DisplayLanguage language,
        SnapshotFreshness freshness,
        TokenUsageSnapshot? tokenUsage,
        AccountIdentity? account,
        CompatibilityDecision sourceDecision,
        CancellationToken cancellationToken)
    {
        var request = new SafeDockPlacementRequest(
            host.Bounds,
            host.WorkArea ?? host.Bounds,
            host.CaptionBounds ?? default,
            host.DpiScale,
            safeDockPreferences,
            overlay is IIndicatorSizeProvider measured
                ? measured.MeasureIndicatorWidth(snapshot, language, OverlayVisualMetrics.IndicatorHeight) : null);
        var resolved = SafeDockPlacementResolver.Resolve(request);
        if (resolved.Frame is null)
        {
            await overlay.HideAsync(cancellationToken).ConfigureAwait(false);
            return await CompleteAsync(
                HostRuntimeState.Hidden,
                sourceDecision with { Placement = SafeDockPlacement.None, FailureCode = CompatibilityFailureCode.InvalidGeometry },
                cancellationToken).ConfigureAwait(false);
        }

        await overlay.ShowAsync(
            new OverlayPresentation(
                host.Handle,
                host.DpiScale,
                language,
                snapshot,
                new PlacementResult(PlacementSurface.Content, resolved.Frame.Value),
                freshness,
                new PointD(host.Bounds.X + (4 * host.DpiScale), host.Bounds.Y + (72 * host.DpiScale)),
                tokenUsage,
                account,
                Version: QuotaDetailFormatter.ProductVersion,
                Mode: PlacementMode.SafeDock,
                SafeDockSize: resolved.Size,
                SafeDockRequest: request),
            cancellationToken).ConfigureAwait(false);
        var profile = safeDockPreferences.FallbackLocked
            ? ProfileCompatibility.FallbackLocked
            : sourceDecision.Profile;
        return await CompleteAsync(
            HostRuntimeState.Visible,
            sourceDecision with { Profile = profile, Placement = SafeDockPlacement.Fallback },
            cancellationToken).ConfigureAwait(false);
    }

    private async ValueTask ApplySafeDockPreferencesAsync(
        SafeDockPreferences preferences,
        CancellationToken cancellationToken)
    {
        safeDockPreferences = preferences;
        compatibilityStateMachine.UpdatePreferences(preferences);
        if (safeDockPreferencesStore is not null)
        {
            await safeDockPreferencesStore.SaveAsync(preferences, cancellationToken).ConfigureAwait(false);
        }
    }

    private async ValueTask<HostRuntimeState> CompleteAsync(
        HostRuntimeState state,
        CompatibilityDecision decision,
        CancellationToken cancellationToken)
    {
        LastCompatibilityDecision = decision;
        if (runtimeStateStore is not null)
        {
            try
            {
                await runtimeStateStore.WriteAsync(
                    new RuntimeStateOutcome(state, decision, now()),
                    cancellationToken).ConfigureAwait(false);
            }
            catch (OperationCanceledException)
            {
                throw;
            }
            catch (Exception)
            {
                // Persisted telemetry must not change overlay behavior.
            }
        }

        return state;
    }
}
