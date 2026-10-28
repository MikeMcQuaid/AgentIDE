import SanductorDomain
import SanductorInterface
import SwiftUI

extension DashboardView {
    var modePicker: some View {
        HStack(spacing: 0) {
            SidebarModePicker(mode: $mode)
            if mode == .repository {
                RepositorySortPicker(sort: $repositorySort).padding(.trailing, Self.listPadding)
            }
            NewSessionMenu(repositories: model.groups.map(\.repository)) { repository in
                model.openNewSession(for: repository)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .padding(.trailing, Self.listPadding)
            .help("Start a new agent session")
        }
    }

    var sidebarContent: some View {
        LazyVStack(alignment: .leading, spacing: Self.rowSpacing) {
            if mode == .repository {
                ForEach(model.repositoryGroups(sortedBy: repositorySort)) { group in
                    header(for: group)
                    if isExpanded(group.repository.path) {
                        ForEach(group.items) { item in row(for: item) }
                    }
                }
            } else {
                ForEach(model.statusGroups, id: \.status) { group in
                    SidebarStatusGroup(status: group.status, count: group.items.count) {
                        ForEach(group.items) { item in row(for: item) }
                    }
                }
            }
            NewRepositoryRow { model.showsRepositoryFinder = true }
                .padding(.trailing, Self.scrollbarClearance)
        }
        .padding([.leading, .vertical], Self.listPadding)
        .padding(.trailing, Self.listTrailingPadding)
    }

    func rowLabel(for item: WorktreeItem) -> some View {
        WorktreeRowView(
            item: item,
            pullRequest: model.pullRequest(for: item),
            standing: model.stackStanding(for: item),
            load: model.paneLoads[item.worktree.path],
            feedbackStatus: model.feedbackStatus(for: item),
            failure: model.launchFailure(for: item),
            block: model.block(for: item),
            repositoryName: mode == .status ? item.worktree.repositoryName : nil,
            repositoryOwner: model.groups.group(holding: item)?.repository.owner,
        )
    }
}
