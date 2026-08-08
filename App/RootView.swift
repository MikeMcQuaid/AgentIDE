import AgentIDEDomain
import DashboardFeature
import PRFeature
import ReviewFeature
import SessionFeature
import SwiftUI

/// The main window: dashboard sidebar, detail panes per worktree.
struct RootView: View {
    // MARK: Internal

    let dependencies: AppDependencies

    var body: some View {
        NavigationSplitView {
            DashboardView(model: dependencies.dashboard)
                .navigationSplitViewColumnWidth(min: Self.sidebarMinimum, ideal: Self.sidebarIdeal)
        } detail: {
            detail
        }
        .sheet(isPresented: newSessionBinding) {
            NewSessionSheet(model: dependencies.dashboard)
        }
        .task { await dependencies.dashboard.poll() }
    }

    // MARK: Private

    private enum DetailPane: CaseIterable {
        case session
        case review
        case pullRequests

        // MARK: Internal

        var title: String {
            switch self {
            case .session:
                "Session"

            case .review:
                "Review"

            case .pullRequests:
                "Pull requests"
            }
        }
    }

    private static let sidebarMinimum: CGFloat = 260
    private static let sidebarIdeal: CGFloat = 320
    private static let pickerPadding: CGFloat = 8

    @State private var pane: DetailPane = .session

    private var newSessionBinding: Binding<Bool> {
        Binding(
            get: { dependencies.dashboard.showsNewSession },
            set: { dependencies.dashboard.showsNewSession = $0 },
        )
    }

    @ViewBuilder private var detail: some View {
        if let item = dependencies.dashboard.selection {
            VStack(spacing: 0) {
                Picker("Pane", selection: $pane) {
                    ForEach(DetailPane.allCases, id: \.self) { pane in
                        Text(pane.title).tag(pane)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(Self.pickerPadding)
                Divider()
                pane(for: item)
            }
        } else {
            ContentUnavailableView(
                "No agents yet",
                systemImage: "rectangle.stack",
                description: Text("Create a session to put a worktree and agent here."),
            )
        }
    }

    @ViewBuilder
    private func pane(for item: WorktreeItem) -> some View {
        switch pane {
        case .session:
            SessionDetailView(item: item, service: dependencies.service)

        case .review:
            ReviewView(worktreePath: item.worktree.path, git: dependencies.git)

        case .pullRequests:
            PullRequestsView(
                repository: Repository(name: item.worktree.repositoryName, path: item.worktree.repositoryPath),
                items: repositoryItems(for: item),
                github: dependencies.github,
                service: dependencies.service,
            )
        }
    }

    private func repositoryItems(for item: WorktreeItem) -> [WorktreeItem] {
        dependencies.dashboard
            .groups
            .first { $0.repository.path == item.worktree.repositoryPath }?
            .items ?? []
    }
}
