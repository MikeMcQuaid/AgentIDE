import AgentIDEDomain
import DashboardFeature
import SwiftUI

/// The detail column's composition: the covering pages, the split
/// and the utility pane. Split from the view body's file for length.
extension RootView {
    /// The middle pages, never sheets, cover the primary pane
    /// rather than replacing it: unmounting takes the panes with it,
    /// and a pane can hold a running agent or shell, which only
    /// destroying its worktree should end. They cover that pane
    /// alone, so the utility pane stays where it was: the window
    /// keeps one shape whatever it is showing.
    var detail: some View {
        ZStack {
            if let item = dependencies.dashboard.selection {
                split(for: item)
            } else {
                unselectedSplit
            }
        }
    }

    @ViewBuilder var coveringPage: some View {
        if dependencies.dashboard.showsNewSession {
            NewSessionPane(model: dependencies.dashboard)
        } else if dependencies.dashboard.showsRepositoryFinder {
            RepositoryFinderPane(model: dependencies.dashboard)
        }
    }

    /// Narrows the panes to what the window can hold. The widths
    /// are written back, so the dividers keep dragging from where
    /// the panes actually are.
    func fitPanes(to width: CGFloat) {
        currentWindowWidth = width
        let layout = PaneLayout(
            width: width,
            sidebar: sidebarWidth,
            utility: utilityPaneWidth,
            showsUtility: showsUtilityPane,
        )
        if layout.sidebar != sidebarWidth {
            sidebarWidth = layout.sidebar
        }
        if layout.utility != utilityPaneWidth {
            utilityPaneWidth = layout.utility
        }
    }

    // MARK: Private

    private func split(for item: WorktreeItem) -> some View {
        HStack(spacing: 0) {
            primaryColumn(for: item)
            if showsUtility {
                PaneDivider(width: $utilityPaneWidth, range: PaneLayout.utilityRange, controlsLeadingPane: false)
                    .ignoresSafeArea(.container, edges: .top)
                utilityPane(for: item)
                    .frame(width: utilityPaneWidth)
                    .frame(maxHeight: .infinity)
                    .ignoresSafeArea(.container, edges: .top)
            }
        }
        .ignoresSafeArea(.container, edges: .top)
    }

    /// The utility pane: the shared tab header over the content, so
    /// the current tab is always visible whichever tab shows.
    /// Restores the worktree's remembered tab whenever the selection
    /// changes, so each worktree keeps its own pane.
    private func utilityPane(for item: WorktreeItem) -> some View {
        VStack(spacing: 0) {
            utilityHeader(for: item)
            Divider()
            utilityContent(for: item)
        }
        .task(id: item.worktree.path) {
            // A stale conversation focus must not survive switching
            // to another sidebar item.
            conversationWorktree = nil
            utilityTabName = tabMemory[item.worktree.path] ?? utilityTabName
        }
        .onChange(of: utilityTabName) {
            tabMemory[item.worktree.path] = utilityTabName
        }
    }
}
