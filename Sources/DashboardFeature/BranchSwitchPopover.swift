import AgentIDEDomain
import SwiftUI
import TerminalUI

/// The branches a worktree could switch to: every local branch not
/// checked out by this or any other worktree of the repository.
/// A popover rather than a submenu because the list is a git read,
/// and a menu's content cannot wait for one.
struct BranchSwitchPopover: View {
    // MARK: Internal

    let item: WorktreeItem
    let model: DashboardModel

    /// Told when a switch finishes, so the popover closes.
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Self.spacing) {
            Text("Switch " + item.worktree.branch + " to")
                .font(.subheadline.weight(.semibold))
            if let branches {
                if branches.isEmpty {
                    Text("Every other local branch is checked out elsewhere.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    list(of: branches)
                }
            } else {
                ProgressView("Listing branches…")
                    .controlSize(.small)
            }
        }
        .padding(Self.padding)
        .frame(minWidth: Self.minimumWidth)
        .task { branches = await model.availableBranches(for: item) }
    }

    // MARK: Private

    private static let spacing: CGFloat = 6
    private static let rowVerticalPadding: CGFloat = 3
    private static let padding: CGFloat = 10
    private static let minimumWidth: CGFloat = 220
    private static let listHeight: CGFloat = 240

    // nil until the git read answers; empty means nothing to offer.
    // swiftlint:disable:next discouraged_optional_collection
    @State private var branches: [String]?

    @State private var isSwitching = false

    private func list(of branches: [String]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(branches, id: \.self) { branch in
                    Button {
                        isSwitching = true
                        Task {
                            await model.switchBranch(branch, for: item)
                            onDone()
                        }
                    } label: {
                        Label(branch, image: "octicon-git-branch")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, Self.rowVerticalPadding)
                    .hoverHelp("git checkout " + branch + " in this worktree")
                }
            }
        }
        .frame(maxHeight: Self.listHeight)
        .disabled(isSwitching)
    }
}
