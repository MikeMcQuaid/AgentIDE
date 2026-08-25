import AgentIDEDomain
import SwiftUI

/// Asks what to call a branch stacked on this worktree's own, since
/// a context menu cannot ask anything itself. The branch is cut in
/// this worktree and checked out: a stack lives in one checkout.
struct StackBranchPrompt: ViewModifier {
    // MARK: Internal

    let item: WorktreeItem
    let model: DashboardModel

    @Binding var name: String
    @Binding var pending: WorktreeItem?

    func body(content: Content) -> some View {
        content
            .alert("Stack a branch on " + item.worktree.branch, isPresented: isPresented) {
                TextField("Branch name", text: $name)
                Button("Create") {
                    let branch = name
                    dismiss()
                    Task { await model.stackBranch(named: branch, on: item) }
                }
                .disabled(name.isEmpty)
                Button("Cancel", role: .cancel) { dismiss() }
            } message: {
                Text("The branch is cut here, in this worktree, and checked out. "
                    + "Whatever is running carries on where it is.")
            }
    }

    // MARK: Private

    private var isPresented: Binding<Bool> {
        Binding(
            get: { pending?.id == item.id },
            set: { shown in
                if shown == false, pending?.id == item.id {
                    pending = nil
                }
            },
        )
    }

    private func dismiss() {
        pending = nil
        name = ""
    }
}
