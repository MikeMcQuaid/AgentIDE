import AgentIDEDomain
import AgentIDEInterface
import SwiftUI

// MARK: - WorktreeBlockSelection

struct WorktreeBlockSelection: Identifiable {
    // MARK: Lifecycle

    init(items: [WorktreeItem], model: DashboardModel) {
        targets = items.map { SidebarTarget($0.worktree) }
        blocks = items.compactMap { model.block(for: $0) }
    }

    // MARK: Internal

    let targets: [SidebarTarget]
    let blocks: [WorkBlock]

    var id: String {
        targets.map(\.id).joined(separator: "\n")
    }

    var commonBlock: WorkBlock? {
        guard blocks.count == targets.count, let first = blocks.first,
              blocks.allSatisfy({ $0.scope == first.scope && $0.dependency == first.dependency })
        else {
            return nil
        }

        return first
    }
}

// MARK: - WorktreeBlockSheet

struct WorktreeBlockSheet: View {
    let selection: WorktreeBlockSelection
    let model: DashboardModel
    let dismiss: () -> Void

    var body: some View {
        if let target = selection.targets.first {
            WorkBlockEditor(
                target: target,
                block: selection.commonBlock,
                targets: model.sidebarTargets,
                additionalTargets: Array(selection.targets.dropFirst()),
                loadSources: { path in
                    await model.service.handleSidebarRequest(.sources(repositoryPath: path), groups: model.groups)
                },
                save: { block, _ in model.editBlocks(block, targets: selection.targets, replacing: selection.blocks) },
                dismiss: dismiss,
            )
        }
    }
}
