import Foundation
import SanductorDomain

extension DashboardModel {
    var selectedItems: [WorktreeItem] {
        visibleGroups.flatMap(\.items).filter { isSelected($0) }
    }

    func isSelected(_ item: WorktreeItem) -> Bool {
        selectedWorktreePaths?.contains(item.id) ?? (selection?.id == item.id)
    }

    func selectSidebar(_ item: WorktreeItem, extending: Bool) {
        guard batchAction == nil, deletingPaths.contains(item.id) == false else {
            return
        }
        guard extending, item.worktree.isHostDirectory == false, item.isPlaceholder == false else {
            select(item)
            return
        }

        var paths = Set(selectedItems
            .filter { $0.worktree.isHostDirectory == false && $0.isPlaceholder == false }
            .map(\.id))
        if paths.contains(item.id) {
            paths.remove(item.id)
        } else {
            paths.insert(item.id)
        }
        selectedWorktreePaths = paths
    }

    func actionItems(for item: WorktreeItem) -> [WorktreeItem] {
        if isSelected(item) {
            selectedItems
        } else {
            [item]
        }
    }

    func editBlocks(_ block: WorkBlock?, targets: [SidebarTarget], replacing previous: [WorkBlock]) -> String? {
        guard targets.allSatisfy(sidebarTargets.contains) else {
            return "A selected worktree or branch has changed. Refresh and try again."
        }

        do {
            try service.editWorkBlocks(
                saving: block.map { template in
                    targets.map { WorkBlock(target: $0, scope: template.scope, dependency: template.dependency) }
                } ?? [],
                removing: block == nil ? previous : [],
                groups: groups,
            )
            updateWorkBlocks()
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
