import AgentIDEDomain
import SwiftUI
import TerminalUI

/// What this worktree's stack is inferred to be, and the chance to
/// say otherwise. Ancestry cannot tell a branch that belongs to the
/// work in hand from an old one that merely shares history, so every
/// branch it found is listed with a way to drop it, and dropped ones
/// are listed with a way back. Nothing here touches git.
struct StackPopover: View {
    // MARK: Internal

    let item: WorktreeItem
    let model: DashboardModel

    /// Told when a branch has been cut, so the popover closes on
    /// the row that now shows it.
    let onCreated: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Self.spacing) {
            Text("Stack in " + (stack?.checkedOut ?? item.worktree.branch)).font(.headline)
            if let stack {
                stacked(stack)
            } else {
                Text("Working out which branches are stacked here…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Divider()
            newBranchField
        }
        .padding(Self.padding)
        .frame(width: Self.width)
        .task { await load() }
    }

    // MARK: Private

    private static let width: CGFloat = 460
    private static let padding: CGFloat = 12
    private static let spacing: CGFloat = 8
    private static let rowSpacing: CGFloat = 4
    private static let excludedOpacity = 0.6

    @State private var stack: BranchStack?
    @State private var excluded: [String] = []
    @State private var newBranch = ""

    /// Locks the field while the branch is being cut, so a second
    /// name cannot be typed into the one being acted on.
    @State private var isCreating = false

    /// Growing the stack: the branch is cut here and checked out, so
    /// whatever is running carries on where it is.
    private var newBranchField: some View {
        HStack(spacing: Self.rowSpacing) {
            TextField("Stack a new branch on top", text: $newBranch)
                .textFieldStyle(.roundedBorder)
                .disabled(isCreating)
                .onSubmit { Task { await create() } }
            BusyButton(
                "Create",
                busy: "Creating",
                prominent: true,
                disabled: newBranch.isEmpty,
            ) {
                await create()
            }
            .keyboardShortcut(.return, modifiers: .command)
            .hoverHelp("Cut this branch on top of " + item.worktree.branch + " in this same worktree")
        }
    }

    /// The inferred stack bottom first, then whatever has been left
    /// out of it.
    @ViewBuilder
    private func stacked(_ stack: BranchStack) -> some View {
        if stack.branches.count <= 1, excluded.isEmpty {
            Text(stack.checkedOut == stack.base
                ? "This worktree is on " + stack.checkedOut + " itself; cut a branch to start a stack."
                : "Only " + stack.checkedOut + " is here; nothing is stacked on it yet.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        VStack(alignment: .leading, spacing: Self.rowSpacing) {
            if let base = stack.base {
                row(branch: base, position: nil, isBase: true)
            }
            ForEach(Array(stack.branches.enumerated()), id: \.element) { position, branch in
                if branch != stack.base {
                    row(branch: branch, position: position + 1, isBase: false)
                }
            }
        }
        if excluded.isEmpty == false {
            Text("Left out").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: Self.rowSpacing) {
                ForEach(excluded, id: \.self) { branch in
                    excludedRow(branch)
                }
            }
        }
    }

    /// One branch of the stack: where it sits, what it is called and
    /// the way to say it does not belong. The base branch and the
    /// checked-out one stay, since neither can be argued with.
    private func row(branch: String, position: Int?, isBase: Bool) -> some View {
        HStack(spacing: Self.rowSpacing) {
            Text(position.map(String.init) ?? "–")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            Image(systemName: isBase ? "arrow.triangle.branch" : "square.stack.3d.up")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(branch)
                .lineLimit(1)
                .truncationMode(.middle)
                .fontWeight(branch == stack?.checkedOut ? .semibold : .regular)
            Spacer(minLength: 0)
            if branch == stack?.checkedOut {
                Text("checked out").font(.caption).foregroundStyle(.secondary)
            } else if isBase == false {
                Button {
                    Task { await exclude(branch) }
                } label: {
                    Image(systemName: "minus.circle")
                        .accessibilityLabel("Leave " + branch + " out of this stack")
                }
                .buttonStyle(.plain)
                .hoverHelp("Leave " + branch + " out of this stack; the branch itself is untouched")
            }
        }
    }

    private func excludedRow(_ branch: String) -> some View {
        HStack(spacing: Self.rowSpacing) {
            Text(branch)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Button {
                Task { await include(branch) }
            } label: {
                Image(systemName: "plus.circle")
                    .accessibilityLabel("Count " + branch + " as part of this stack again")
            }
            .buttonStyle(.plain)
            .hoverHelp("Count " + branch + " as part of this stack again")
        }
        .opacity(Self.excludedOpacity)
    }

    private func load() async {
        excluded = model.excludedStackBranches(for: item)
        stack = await model.inferredStack(for: item)
    }

    private func exclude(_ branch: String) async {
        model.setStackExclusion(branch: branch, excluded: true, for: item)
        await load()
    }

    private func include(_ branch: String) async {
        model.setStackExclusion(branch: branch, excluded: false, for: item)
        await load()
    }

    private func create() async {
        let branch = newBranch
        guard branch.isEmpty == false else {
            return
        }

        isCreating = true
        defer { isCreating = false }
        newBranch = ""
        await model.stackBranch(named: branch, on: item)
        onCreated()
    }
}
