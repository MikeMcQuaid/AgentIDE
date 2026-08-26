import AgentIDEDomain
import SwiftUI

/// The stack a worktree's branch belongs to, bottom first, with the
/// checked-out one emphasised: `main ← fix_the_lexer ← use_the_lexer`.
/// One component, shown by the review and pull request surfaces
/// alike, and shown by neither when the branch stands on its own.
public struct BranchStackStrip: View {
    // MARK: Lifecycle

    /// Creates the strip. `onSelect` retargets the surrounding pane
    /// to a branch; it never checks anything out, which is a
    /// deliberate act of its own.
    @preconcurrency
    public init(
        stack: BranchStack,
        selected: String,
        isEnabled: @escaping (String) -> Bool = { _ in true },
        onSelect: @escaping @MainActor (String) -> Void,
    ) {
        self.stack = stack
        self.selected = selected
        self.isEnabled = isEnabled
        self.onSelect = onSelect
    }

    // MARK: Public

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Self.spacing) {
                if let base = stack.base {
                    Text(base)
                        .foregroundStyle(.secondary)
                    arrow
                }
                ForEach(Array(stack.branches.enumerated()), id: \.element) { index, branch in
                    Button(branch) { onSelect(branch) }
                        .disabled(isEnabled(branch) == false)
                        .buttonStyle(.plain)
                        .fontWeight(branch == selected ? .semibold : .regular)
                        .foregroundStyle(branch == stack.checkedOut ? Color.primary : .secondary)
                        .hoverHelp(help(for: branch))
                    if index < stack.branches.count - 1 {
                        arrow
                    }
                }
            }
            .font(.caption)
            .padding(.horizontal, Self.spacing)
            .padding(.vertical, Self.verticalPadding)
        }
    }

    // MARK: Private

    private static let spacing: CGFloat = 6
    private static let verticalPadding: CGFloat = 3

    private let stack: BranchStack
    private let selected: String

    /// Whether an entry can be moved to here: the pull request tab
    /// keeps entries above an unpushed branch out of reach, since
    /// there is nothing to list or open for them yet.
    private let isEnabled: (String) -> Bool

    private let onSelect: @MainActor (String) -> Void

    private var arrow: some View {
        Text(verbatim: "←")
            .foregroundStyle(.tertiary)
            .font(.caption)
    }

    private func help(for branch: String) -> String {
        branch == stack.checkedOut
            ? "The branch this worktree holds; its diff is the one you can change"
            : "Show this branch's own changes; checking it out is a separate step"
    }
}
