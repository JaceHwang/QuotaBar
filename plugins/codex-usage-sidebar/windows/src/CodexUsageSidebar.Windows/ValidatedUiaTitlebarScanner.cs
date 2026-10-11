#if WINDOWS
using System.Windows.Automation;
using CodexUsageSidebar.Core;

namespace CodexUsageSidebar.Windows;

internal sealed record UiaScanningObservation(
    int Depth,
    string ControlType,
    string AutomationId,
    string ClassName,
    RectD Bounds,
    string Name);

public sealed class ValidatedUiaTitlebarScanner : ITitlebarScanner
{
    private const string CaptionContainerClass = "ChromeNodeCaptionButtonContainer";
    private const int MaximumDirectChildren = 64;
    private const int MaximumCandidateButtons = 1024;
    private const int MaximumRightPaneAncestorDepth = 8;
    private const int MaximumTopTitlebarAncestorDepth = 6;
    private const int MaximumTopTitlebarDescendantDepth = 6;
    private const string TitleGroupClassMarker = "text-md flex min-w-0 items-center";
    private const string RightToolbarClassMarker = "hide-scrollbar flex h-full min-w-0 flex-1";
    private const string RightToolbarOverflowMarker = "overflow-x-auto overflow-y-hidden";
    private static readonly TimeSpan ScanTimeout = TimeSpan.FromSeconds(2);
    private static readonly Condition CaptionContainerCondition = new AndCondition(
        new PropertyCondition(AutomationElement.ControlTypeProperty, ControlType.Pane),
        new PropertyCondition(AutomationElement.ClassNameProperty, CaptionContainerClass));
    private static readonly Condition OpenLocationCondition = new AndCondition(
        new PropertyCondition(AutomationElement.ControlTypeProperty, ControlType.Button),
        new OrCondition(UiaSemanticRoleClassifier.SupportedExactNames
            .Select(name => (Condition)new PropertyCondition(
                AutomationElement.NameProperty,
                name,
                PropertyConditionFlags.IgnoreCase))
            .ToArray()));
    private static readonly Condition ButtonCondition = new PropertyCondition(
        AutomationElement.ControlTypeProperty,
        ControlType.Button);
    private static readonly Condition SettingsNavigationCondition = new OrCondition(
        new PropertyCondition(AutomationElement.ControlTypeProperty, ControlType.Button),
        new PropertyCondition(AutomationElement.ControlTypeProperty, ControlType.Hyperlink));
    private readonly ValidatedTitlebarCache cache = new();
    private readonly object scanGate = new();
    private readonly SelectorProfileCatalog selectorCatalog;
    private readonly Func<HostWindowSnapshot, CancellationToken, ValueTask<IReadOnlyList<UiaScanningObservation>>>? observationProvider;
    private readonly bool isCatalogValid;
    private InFlightScan? inFlight;

    public ValidatedUiaTitlebarScanner()
    {
        isCatalogValid = SelectorProfileCatalog.TryLoadRuntime(out selectorCatalog);
    }

    internal ValidatedUiaTitlebarScanner(SelectorProfileCatalog selectorCatalog)
    {
        this.selectorCatalog = selectorCatalog ?? throw new ArgumentNullException(nameof(selectorCatalog));
        isCatalogValid = true;
    }

    internal ValidatedUiaTitlebarScanner(
        SelectorProfileCatalog selectorCatalog,
        Func<HostWindowSnapshot, CancellationToken, ValueTask<IReadOnlyList<UiaScanningObservation>>> observationProvider)
    {
        this.selectorCatalog = selectorCatalog ?? throw new ArgumentNullException(nameof(selectorCatalog));
        this.observationProvider = observationProvider ?? throw new ArgumentNullException(nameof(observationProvider));
        isCatalogValid = true;
    }

    internal SelectorProfileCatalog Catalog => selectorCatalog;

    public TitlebarSnapshot? TryGetCurrent(HostWindowSnapshot host) => cache.TryGet(host);
    public TitlebarSnapshot? TryGetRetained(HostWindowSnapshot host) => cache.TryGetRetained(host);

    public async ValueTask<TitlebarSnapshot> ScanAsync(
        HostWindowSnapshot host,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        Task<TitlebarSnapshot> scanTask;
        var identity = ScanIdentity.For(host);
        lock (scanGate)
        {
            if (inFlight is null || inFlight.Task.IsCompleted)
            {
                inFlight?.Cancellation.Dispose();
                var workerCancellation = new CancellationTokenSource(ScanTimeout);
                inFlight = new InFlightScan(
                    identity,
                    Task.Run(
                        () => Scan(host, workerCancellation.Token),
                        CancellationToken.None),
                    workerCancellation);
            }
            if (inFlight.Identity != identity)
            {
                throw new WindowsDeviceValidationRequiredException(host.BuildIdentity);
            }
            scanTask = inFlight.Task;
        }

        using var scanCancellation = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        scanCancellation.CancelAfter(ScanTimeout);
        try
        {
            var snapshot = await scanTask.WaitAsync(scanCancellation.Token).ConfigureAwait(false);
            cache.Store(host, snapshot);
            return snapshot;
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            throw new WindowsDeviceValidationRequiredException(host.BuildIdentity);
        }
    }

    private sealed record InFlightScan(
        ScanIdentity Identity,
        Task<TitlebarSnapshot> Task,
        CancellationTokenSource Cancellation);

    private readonly record struct ScanIdentity(
        IntPtr Handle,
        RectD Bounds,
        double DpiScale,
        string BuildIdentity)
    {
        internal static ScanIdentity For(HostWindowSnapshot host) => new(
            host.Handle, host.Bounds, host.DpiScale, host.BuildIdentity);
    }

    public void Invalidate() => cache.Invalidate();

    private TitlebarSnapshot Scan(
        HostWindowSnapshot host,
        CancellationToken cancellationToken)
    {
        if (!isCatalogValid)
        {
            throw new InvalidSelectorCatalogException();
        }
        IReadOnlyList<UiaStructureNode> nodes;
        if (observationProvider is null)
        {
            nodes = QueryValidatedStructureFromDesktop(host, cancellationToken);
        }
        else
        {
            var observations = observationProvider(host, cancellationToken).AsTask().GetAwaiter().GetResult();
            var hasConversationAnchor = observations.Any(observation =>
                UiaSemanticRoleClassifier.Classify(observation.Name) == UiaSemanticRoles.OpenLocation);
            nodes = NormalizeObservations(observations);
            hasConversationAnchor |= CodexTitlebarSelector.TryResolve(
                host.BuildIdentity, host.DpiScale, host.Bounds, nodes, selectorCatalog) is not null;
            if (observations.Any(observation => HostPagePolicy.IsSettingsNavigation(
                new HostPageControl(observation.Bounds, observation.Name),
                host.Bounds,
                allowStructuralMatch: !hasConversationAnchor)))
            {
                throw new HostSettingsPageDetectedException();
            }
        }
        var snapshot = CodexTitlebarSelector.TryResolve(
            host.BuildIdentity,
            host.DpiScale,
            host.Bounds,
            nodes,
            selectorCatalog);
        return snapshot ?? throw new WindowsDeviceValidationRequiredException(host.BuildIdentity);
    }

    private static IReadOnlyList<UiaStructureNode> QueryValidatedStructure(
        AutomationElement root,
        RectD hostBounds,
        double dpiScale,
        CancellationToken cancellationToken)
    {
        var nodes = new List<UiaStructureNode>();
        var captionContainers = root.FindAll(TreeScope.Descendants, CaptionContainerCondition);
        foreach (AutomationElement container in captionContainers)
        {
            cancellationToken.ThrowIfCancellationRequested();
            AddNode(container, 3, nodes);
            AddDirectChildren(container, 4, nodes, cancellationToken);
        }

        // Newer hosts can omit Open Location entirely. Discover confirmed
        // header containers structurally before inspecting their descendants.
        var groups = root.FindAll(TreeScope.Descendants,
            new PropertyCondition(AutomationElement.ControlTypeProperty, ControlType.Group));
        var scanHost = new HostWindowSnapshot(IntPtr.Zero, hostBounds, true, dpiScale, "");
        var inspected = 0;
        foreach (AutomationElement group in groups)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (++inspected > UiaTraversalBudget.DiagnosticMaximumNodes) break;
            try
            {
                var current = group.Current;
                var className = current.ClassName ?? "";
                var tokens = className.Split(' ', StringSplitOptions.RemoveEmptyEntries);
                if (!tokens.Contains("fixed") || !tokens.Contains("h-toolbar")
                    || !tokens.Contains("top-toolbar-sm")) continue;
                var rectangle = current.BoundingRectangle;
                var bounds = new RectD(rectangle.X, rectangle.Y, rectangle.Width, rectangle.Height);
                if (DiagnosticTitlebarScope.Resolve(scanHost, "ControlType.Group",
                    className, bounds, null) is null) continue;
                var observation = new List<UiaStructureNode>();
                AddBoundedSubtree(group, 14, MaximumTopTitlebarDescendantDepth, observation, cancellationToken);
                nodes.AddRange(TopTitlebarObservationCollector.Normalize(observation));
            }
            catch (ElementNotAvailableException) { }
        }

        var structuralNodes = TopTitlebarObservationCollector.Normalize(nodes);
        if (structuralNodes.Any(node => node.ClassName.Split(' ').Contains("button-toolbar"))
            && CodexTitlebarSelector.TryResolve("", dpiScale, hostBounds, structuralNodes) is not null)
            return structuralNodes;

        var openLocationButtons = DiscoverOpenLocationSeeds(root, hostBounds, dpiScale, cancellationToken);
        foreach (var openLocation in openLocationButtons)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var toolbar = TryFindAncestor(
                openLocation,
                element => ClassNameContains(element, "fixed z-30 flex h-toolbar")
                    && ClassNameContains(element, "top-toolbar-sm"),
                MaximumTopTitlebarAncestorDepth);
            if (toolbar is null)
            {
                continue;
            }
            var observation = new List<UiaStructureNode>();
            AddBoundedSubtree(
                toolbar,
                14,
                MaximumTopTitlebarDescendantDepth,
                observation,
                cancellationToken);
            nodes.AddRange(TopTitlebarObservationCollector.Normalize(observation));
        }

        AddRightPaneStructures(root, openLocationButtons, dpiScale, nodes, cancellationToken);

        return TopTitlebarObservationCollector.Normalize(nodes);
    }

    private static IReadOnlyList<AutomationElement> DiscoverOpenLocationSeeds(
        AutomationElement root,
        RectD hostBounds,
        double dpiScale,
        CancellationToken cancellationToken)
    {
        var seeds = new List<AutomationElement>();
        var seen = new HashSet<OpenLocationSeedIdentity>();
        AddOpenLocationSeeds(root.FindAll(TreeScope.Descendants, OpenLocationCondition), seeds, seen);

        AutomationElementCollection buttons;
        try
        {
            buttons = root.FindAll(TreeScope.Descendants, ButtonCondition);
        }
        catch (ElementNotAvailableException)
        {
            return seeds;
        }
        if (buttons.Count > MaximumCandidateButtons)
        {
            return seeds;
        }

        foreach (AutomationElement button in buttons)
        {
            cancellationToken.ThrowIfCancellationRequested();
            RectD bounds;
            string controlType;
            string className;
            try
            {
                var current = button.Current;
                var rectangle = current.BoundingRectangle;
                bounds = new RectD(rectangle.X, rectangle.Y, rectangle.Width, rectangle.Height);
                controlType = current.ControlType?.ProgrammaticName ?? string.Empty;
                className = current.ClassName ?? string.Empty;
            }
            catch (ElementNotAvailableException)
            {
                continue;
            }

            if (!OpenLocationSeedCandidatePolicy.IsCandidate(
                controlType,
                className,
                bounds,
                hostBounds,
                dpiScale))
            {
                continue;
            }
            AddOpenLocationSeed(button, bounds, className, seeds, seen);
        }

        return seeds;
    }

    private static void AddOpenLocationSeeds(
        AutomationElementCollection candidates,
        List<AutomationElement> seeds,
        HashSet<OpenLocationSeedIdentity> seen)
    {
        foreach (AutomationElement candidate in candidates)
        {
            RectD bounds;
            string className;
            try
            {
                var current = candidate.Current;
                var rectangle = current.BoundingRectangle;
                bounds = new RectD(rectangle.X, rectangle.Y, rectangle.Width, rectangle.Height);
                className = current.ClassName ?? string.Empty;
            }
            catch (ElementNotAvailableException)
            {
                continue;
            }
            AddOpenLocationSeed(candidate, bounds, className, seeds, seen);
        }
    }

    private static void AddOpenLocationSeed(
        AutomationElement candidate,
        RectD bounds,
        string className,
        List<AutomationElement> seeds,
        HashSet<OpenLocationSeedIdentity> seen)
    {
        var identity = new OpenLocationSeedIdentity(
            bounds.X,
            bounds.Y,
            bounds.Width,
            bounds.Height,
            className);
        if (seen.Add(identity))
        {
            seeds.Add(candidate);
        }
    }

    private readonly record struct OpenLocationSeedIdentity(
        double X,
        double Y,
        double Width,
        double Height,
        string ClassName);

    private static void AddTitleChildren(
        AutomationElement contentGroup,
        List<UiaStructureNode> nodes,
        CancellationToken cancellationToken)
    {
        var titleGroups = DirectChildren(contentGroup, cancellationToken)
            .Where(element => ClassNameContains(element, TitleGroupClassMarker))
            .ToArray();
        foreach (var titleGroup in titleGroups)
        {
            AddDirectChildren(titleGroup, 17, nodes, cancellationToken);
        }
    }

    private static void AddRightPaneStructures(
        AutomationElement root,
        IReadOnlyList<AutomationElement> openLocationButtons,
        double dpiScale,
        List<UiaStructureNode> nodes,
        CancellationToken cancellationToken)
    {
        AutomationElementCollection buttons;
        try
        {
            buttons = root.FindAll(TreeScope.Descendants, ButtonCondition);
        }
        catch (ElementNotAvailableException)
        {
            return;
        }
        if (buttons.Count > MaximumCandidateButtons)
        {
            return;
        }
        foreach (AutomationElement openLocation in openLocationButtons)
        {
            RectD openLocationBounds;
            try
            {
                var bounds = openLocation.Current.BoundingRectangle;
                openLocationBounds = new RectD(bounds.X, bounds.Y, bounds.Width, bounds.Height);
            }
            catch (ElementNotAvailableException)
            {
                continue;
            }
            foreach (AutomationElement button in buttons)
            {
                cancellationToken.ThrowIfCancellationRequested();
                RectD buttonBounds;
                string controlType;
                string className;
                try
                {
                    var current = button.Current;
                    var bounds = current.BoundingRectangle;
                    buttonBounds = new RectD(bounds.X, bounds.Y, bounds.Width, bounds.Height);
                    controlType = current.ControlType?.ProgrammaticName ?? string.Empty;
                    className = current.ClassName ?? string.Empty;
                }
                catch (ElementNotAvailableException)
                {
                    continue;
                }
                if (!RightToolbarCandidatePolicy.IsCandidate(
                    openLocationBounds, buttonBounds, controlType, className, dpiScale))
                {
                    continue;
                }
                var surface = TryGetParent(button);
                if (surface is null)
                {
                    continue;
                }
                var surfaceChildren = DirectChildren(surface, cancellationToken);
                if (surfaceChildren.Count(child =>
                        ClassNameContains(child, RightToolbarClassMarker)
                        && ClassNameContains(child, RightToolbarOverflowMarker)) != 1)
                {
                    continue;
                }
                var container = TryGetParent(surface);
                var rightPane = container is null
                    ? null
                    : TryFindAncestor(
                        container,
                        element => ClassNameContains(element, "relative z-[41] h-full")
                            && ClassNameContains(element, "min-w-0 shrink-0 overflow-visible"),
                        MaximumRightPaneAncestorDepth);
                if (container is null || rightPane is null)
                {
                    continue;
                }
                AddNode(rightPane, 15, nodes);
                AddNode(container, 16, nodes);
                AddNode(surface, 17, nodes);
                foreach (var child in surfaceChildren)
                {
                    AddNode(child, 18, nodes);
                }
            }
        }
    }

    private static bool ClassNameContains(AutomationElement element, string marker)
    {
        try
        {
            var tokens = (element.Current.ClassName ?? string.Empty)
                .Split(' ', StringSplitOptions.RemoveEmptyEntries)
                .ToHashSet(StringComparer.Ordinal);
            return marker.Split(' ', StringSplitOptions.RemoveEmptyEntries).All(tokens.Contains);
        }
        catch (ElementNotAvailableException)
        {
            return false;
        }
    }

    private static AutomationElement? TryGetParent(AutomationElement element)
    {
        try
        {
            return TreeWalker.RawViewWalker.GetParent(element);
        }
        catch (ElementNotAvailableException)
        {
            return null;
        }
    }

    private static AutomationElement? TryFindAncestor(
        AutomationElement start,
        Func<AutomationElement, bool> predicate,
        int maximumDepth)
    {
        var current = start;
        for (var depth = 0; depth <= maximumDepth && current is not null; depth++)
        {
            if (predicate(current)) return current;
            current = TryGetParent(current);
        }
        return null;
    }

    private static void AddDirectChildren(
        AutomationElement parent,
        int depth,
        List<UiaStructureNode> nodes,
        CancellationToken cancellationToken)
    {
        foreach (var child in DirectChildren(parent, cancellationToken))
        {
            AddNode(child, depth, nodes);
        }
    }

    private static IReadOnlyList<UiaStructureNode> QueryValidatedStructureFromDesktop(
        HostWindowSnapshot host,
        CancellationToken cancellationToken)
    {
        var root = AutomationElement.FromHandle(host.Handle);
        if (root is null)
        {
            throw new WindowsDeviceValidationRequiredException(host.BuildIdentity);
        }
        var scoped = TopTitlebarObservationCollector.Normalize(WindowsDiagnosticProbe.Collect(
            root, host, false, ProbeRedactor.Create(), cancellationToken)
            .Select(node => new UiaStructureNode(node.Depth, node.ControlType,
                node.AutomationId, node.ClassName, node.Bounds, node.NameLength, node.SemanticRole)).ToArray());
        if (scoped.Any(node => node.ClassName.Split(' ').Contains("button-toolbar"))
            && CodexTitlebarSelector.TryResolve(host.BuildIdentity, host.DpiScale, host.Bounds, scoped) is not null)
            return scoped;
        var conversationAnchors = DiscoverOpenLocationSeeds(root, host.Bounds, host.DpiScale, cancellationToken);
        if (IsSettingsPage(root, host.Bounds, conversationAnchors.Count == 0, cancellationToken))
        {
            throw new HostSettingsPageDetectedException();
        }
        return QueryValidatedStructure(root, host.Bounds, host.DpiScale, cancellationToken);
    }

    private static bool IsSettingsPage(
        AutomationElement root,
        RectD hostBounds,
        bool allowStructuralMatch,
        CancellationToken cancellationToken)
    {
        AutomationElementCollection candidates;
        try { candidates = root.FindAll(TreeScope.Descendants, SettingsNavigationCondition); }
        catch (ElementNotAvailableException) { return false; }
        if (candidates.Count > MaximumCandidateButtons) return false;
        foreach (AutomationElement candidate in candidates)
        {
            cancellationToken.ThrowIfCancellationRequested();
            try
            {
                var current = candidate.Current;
                var bounds = current.BoundingRectangle;
                if (HostPagePolicy.IsSettingsNavigation(
                    new HostPageControl(
                        new RectD(bounds.X, bounds.Y, bounds.Width, bounds.Height),
                        current.Name ?? string.Empty),
                    hostBounds,
                    allowStructuralMatch))
                {
                    return true;
                }
            }
            catch (ElementNotAvailableException) { }
        }
        return false;
    }

    private static IReadOnlyList<UiaStructureNode> NormalizeObservations(IReadOnlyList<UiaScanningObservation> observed)
    {
        ArgumentNullException.ThrowIfNull(observed);
        return TopTitlebarObservationCollector.Normalize(observed
            .Where(observation => UiaTraversalBudget.HasFiniteBounds(observation.Bounds))
            .Select(observation => new UiaStructureNode(
                observation.Depth,
                observation.ControlType,
                observation.AutomationId,
                observation.ClassName,
                observation.Bounds,
                observation.Name.Length,
                UiaSemanticRoleClassifier.Classify(observation.Name)))
            .ToArray());
    }

    private static void AddBoundedSubtree(
        AutomationElement parent,
        int depth,
        int remainingDepth,
        List<UiaStructureNode> nodes,
        CancellationToken cancellationToken)
    {
        if (remainingDepth < 0 || nodes.Count >= TopTitlebarObservationCollector.MaximumObservedNodes)
        {
            return;
        }
        AddNode(parent, depth, nodes);
        if (remainingDepth == 0) return;
        foreach (var child in DirectChildren(parent, cancellationToken))
        {
            if (nodes.Count >= TopTitlebarObservationCollector.MaximumObservedNodes) return;
            AddBoundedSubtree(child, depth + 1, remainingDepth - 1, nodes, cancellationToken);
        }
    }

    private static IReadOnlyList<AutomationElement> DirectChildren(
        AutomationElement parent,
        CancellationToken cancellationToken)
    {
        var children = new List<AutomationElement>();
        AutomationElement? child;
        try
        {
            child = TreeWalker.RawViewWalker.GetFirstChild(parent);
        }
        catch (ElementNotAvailableException)
        {
            return children;
        }
        while (child is not null && children.Count < MaximumDirectChildren)
        {
            cancellationToken.ThrowIfCancellationRequested();
            children.Add(child);
            try
            {
                child = TreeWalker.RawViewWalker.GetNextSibling(child);
            }
            catch (ElementNotAvailableException)
            {
                break;
            }
        }
        return children;
    }

    private static void AddNode(
        AutomationElement element,
        int depth,
        List<UiaStructureNode> nodes)
    {
        try
        {
            var current = element.Current;
            var bounds = current.BoundingRectangle;
            var name = current.Name ?? string.Empty;
            var nodeBounds = new RectD(bounds.X, bounds.Y, bounds.Width, bounds.Height);
            if (!UiaTraversalBudget.HasFiniteBounds(nodeBounds))
            {
                return;
            }
            nodes.Add(new UiaStructureNode(
                depth,
                current.ControlType?.ProgrammaticName ?? string.Empty,
                current.AutomationId ?? string.Empty,
                current.ClassName ?? string.Empty,
                nodeBounds,
                name.Length,
                UiaSemanticRoleClassifier.Classify(name)));
        }
        catch (ElementNotAvailableException)
        {
        }
    }
}
#endif
