import AgentIDEInterface
import SwiftUI

extension DashboardView {
    @ViewBuilder var selectionBar: some View {
        if let progress = model.batchProgress {
            HStack {
                ProgressView().controlSize(.small)
                Text(progress).interfaceFont(.caption)
            }
            .padding(Self.listPadding)
        } else if model.selectedItems.count > 1 {
            HStack {
                Menu(String(model.selectedItems.count) + " selected") {
                    WorktreeBatchActions(items: model.selectedItems, model: model) {
                        pendingBlock = WorktreeBlockSelection(items: model.selectedItems, model: model)
                    }
                }
                .menuStyle(.borderlessButton)
                Spacer(minLength: 0)
                Button("Clear selection", systemImage: "xmark") { model.selectedWorktreePaths = nil }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .help("Return to the open worktree")
            }
            .interfaceFont(.caption)
            .padding(Self.listPadding)
        }
    }
}
