import AgentIDEDomain
import DashboardFeature
import SwiftUI
import TerminalUI

/// The detail column's composition: the covering pages, the split
/// and the utility pane. Split from the view body's file for length.
extension RootView {
    var sidebarDivider: some View {
        PaneDivider(width: $sidebarWidth, range: PaneLayout.sidebarRange, controlsLeadingPane: true) {
            sidebarWidth = min(PaneLayout.sidebarComfortable, max(
                PaneLayout.sidebarRange.lowerBound,
                currentWindowWidth - (showsUtility ? utilityPaneWidth : 0) - PaneLayout.primaryMinimum,
            ))
        }
        .ignoresSafeArea(.container, edges: .top)
    }

    /// The middle pages, never sheets, cover the primary pane
    /// rather than replacing it: unmounting takes the panes with it,
    /// and a pane can hold a running agent or shell, which only
    /// destroying its worktree should end. They cover that pane
    /// alone, so the utility pane stays where it was: the window
    /// keeps one shape whatever it is showing.
    var detail: some View {
        HStack(spacing: 0) {
            if let item = dependencies.dashboard.selection {
                primaryColumn(for: item)
            } else {
                unselectedColumn
            }
            if showsUtility {
                PaneDivider(width: $utilityPaneWidth, range: PaneLayout.utilityRange, controlsLeadingPane: false) {
                    utilityPaneWidth = PaneLayout.defaultUtilityWidth(in: currentWindowWidth, sidebar: sidebarWidth)
                }
                .ignoresSafeArea(.container, edges: .top)
            }
            RetainedPane(isExpanded: showsUtility, width: utilityPaneWidth) {
                utilityPane(for: dependencies.dashboard.selection)
            }
            .ignoresSafeArea(.container, edges: .top)
        }
        .ignoresSafeArea(.container, edges: .top)
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

    /// The utility pane: the shared tab header over the content, so
    /// the current tab is always visible whichever tab shows.
    /// Restores the worktree's remembered tab whenever the selection
    /// changes, so each worktree keeps its own pane.
    private func utilityPane(for item: WorktreeItem?) -> some View {
        VStack(spacing: 0) {
            if item != nil {
                utilityHeader
                Divider()
            }
            utilityContent(for: item)
        }
        .task(id: item?.worktree.path) {
            // A stale conversation focus must not survive switching
            // to another sidebar item.
            conversationWorktree = nil
            if let item {
                utilityTabName = tabMemory[item.worktree.path] ?? utilityTabName
            }
        }
        .onChange(of: utilityTabName) {
            if let item {
                tabMemory[item.worktree.path] = utilityTabName
            }
        }
    }
}
