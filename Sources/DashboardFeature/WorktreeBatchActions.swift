import AgentIDEDomain
import SwiftUI

struct WorktreeBatchActions: View {
    // MARK: Internal

    let items: [WorktreeItem]
    let model: DashboardModel
    let onBlock: () -> Void

    var body: some View {
        Group {
            action(.refresh)
            Divider()
            action(.fetch)
            action(.fetchAndReset)
                .hoverHelp("Hard-reset selected main checkouts to origin's default branch; local changes are lost")
            Divider()
            Button("Block " + String(items.count) + " worktrees…", action: onBlock)
            let selection = WorktreeBlockSelection(items: items, model: model)
            if selection.blocks.isEmpty == false {
                Button("Remove blocks (" + String(selection.blocks.count) + ")") {
                    if let error = model.editBlocks(nil, targets: selection.targets, replacing: selection.blocks) {
                        model.report(error)
                    }
                }
            }
            Divider()
            action(.cleanUp)
                .hoverHelp("Clean up merged work only; dirty or unmerged worktrees are left alone")
        }
        .disabled(model.batchAction != nil)
    }

    // MARK: Private

    private func action(_ action: WorktreeBatchAction) -> some View {
        let count = model.batchItems(for: action, in: items).count
        let unit =
            switch action {
            case .fetch,
                 .refresh:
                count == 1 ? " repository" : " repositories"

            case .fetchAndReset:
                count == 1 ? " main checkout" : " main checkouts"

            case .cleanUp:
                count == 1 ? " worktree" : " worktrees"
            }
        return Button(action.rawValue + " (" + String(count) + unit + ")") {
            Task {
                await model.performBatch(action, items: items)
            }
        }
        .disabled(count == 0)
    }
}
