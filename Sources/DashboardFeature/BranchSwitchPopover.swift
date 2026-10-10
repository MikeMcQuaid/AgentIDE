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
        PopoverContent(width: Self.width) {
            VStack(alignment: .leading, spacing: Self.spacing) {
                HStack(spacing: Self.spacing) {
                    Text("Switch").interfaceFont(.subheadline, weight: .semibold)
                    Text(item.worktree.branch).font(nameStyle.font)
                    Text("to").interfaceFont(.subheadline, weight: .semibold)
                }
                if let branches {
                    if branches.isEmpty {
                        Text("Every other local branch is checked out elsewhere.")
                            .interfaceFont(.callout)
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
        }
        .task { branches = await model.availableBranches(for: item) }
    }

    // MARK: Private

    private static let spacing: CGFloat = 6
    private static let rowHeight: CGFloat = 24
    private static let padding: CGFloat = 10
    private static let width: CGFloat = 420

    // nil until the git read answers; empty means nothing to offer.
    // swiftlint:disable:next discouraged_optional_collection
    @State private var branches: [String]?

    @State private var isSwitching = false

    private var nameStyle: NameStyle = .init()

    private func list(of branches: [String]) -> some View {
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
                        .font(nameStyle.font)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(height: Self.rowHeight)
                .hoverHelp("git checkout " + branch + " in this worktree")
            }
        }
        .disabled(isSwitching)
    }
}
