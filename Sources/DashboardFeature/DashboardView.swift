import AgentIDEData
import AgentIDEDomain
import SwiftUI
import TerminalUI

// MARK: - DashboardView

/// The sidebar listing worktrees grouped by repository. Built on a
/// plain scroll view rather than a list: the
/// outline-backed list both crashed and ignored collapses when
/// sections removed their rows, and rows here are simple enough not
/// to need one.
public struct DashboardView: View {
    // MARK: Lifecycle

    /// Creates the sidebar for a model. `isFullScreen` says the
    /// traffic lights are hidden, so the rows may start higher.
    public init(model: DashboardModel, isFullScreen: Bool = false) {
        self.model = model
        self.isFullScreen = isFullScreen
    }

    // MARK: Public

    /// The grouped rows with status badges per worktree.
    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Self.rowSpacing) {
                ForEach(model.groups) { group in
                    header(for: group)
                    if isExpanded(group.repository.path) {
                        ForEach(group.items) { item in
                            row(for: item)
                        }
                    }
                }
                NewRepositoryRow { model.showsRepositoryFinder = true }
            }
            .padding(Self.listPadding)
        }
        // The traffic lights occupy the top-left band; the inset
        // keeps the first repository row beneath it. Opening a
        // repository lives at the list's end as its last row, not
        // floating up here.
        .safeAreaInset(edge: .top, spacing: 0) {
            Color.clear.frame(height: isFullScreen ? Self.listPadding : Self.titlebarClearance)
        }
    }

    // MARK: Private

    private static let statusPadding: CGFloat = 4
    private static let listPadding: CGFloat = 6
    private static let rowSpacing: CGFloat = 1
    private static let rowVerticalPadding: CGFloat = 3
    private static let headerVerticalPadding: CGFloat = 5
    private static let deletingOpacity = 0.35
    private static let rowHorizontalPadding: CGFloat = 6
    private static let rowIndent: CGFloat = 12
    private static let rowCornerRadius: CGFloat = 5
    private static let avatarSize: CGFloat = 14
    private static let avatarCornerRadius: CGFloat = 3
    private static let expandedChevronDegrees: Double = 90

    /// Clears the traffic lights alone, which is all that occupies
    /// the band now; fullscreen hides them entirely and keeps only
    /// the list's own padding, reclaiming the band for rows.
    private static let titlebarClearance: CGFloat = 26

    @AppStorage("collapsedRepositories")
    private var collapsedRepositories = ""

    /// Whether the window is key, which decides how selection paints.
    @Environment(\.controlActiveState)
    private var controlActiveState

    /// The pending confirmed deletion: which worktree, and what the
    /// merge-safe path refused about it (nil for a plain Delete
    /// worktree, which always confirms since it always forces).
    @State private var pendingForceDelete: (path: String, refusal: SessionService.CleanupRefusal?)?

    /// The worktree whose stack is being looked over: a menu cannot
    /// hold a popover, so the sidebar holds it. The branch switcher
    /// is held the same way.
    @State private var pendingStack: WorktreeItem?
    @State private var pendingBranchSwitch: WorktreeItem?

    private let model: DashboardModel

    /// Whether the window is fullscreen, with the lights hidden.
    private let isFullScreen: Bool

    /// The disclosure button and a trailing new-session plus are
    /// siblings: a button nested inside another button never
    /// receives its clicks.
    private func header(for group: RepositoryGroup) -> some View {
        HStack(spacing: Self.statusPadding) {
            Button {
                toggleExpansion(of: group.repository.path)
            } label: {
                headerLabel(for: group)
            }
            .buttonStyle(.plain)
            .hoverHelp("Click to show or hide this repository's worktrees")
            Button {
                model.openNewSession(for: group.repository)
            } label: {
                Image(systemName: "plus")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("New session in " + group.repository.name)
            }
            .buttonStyle(.plain)
            .hoverHelp("Start a new agent session in this repository")
        }
        .modifier(RepositoryMenu(group: group, model: model))
    }

    private func headerLabel(for group: RepositoryGroup) -> some View {
        HStack(spacing: Self.statusPadding) {
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .rotationEffect(.degrees(isExpanded(group.repository.path) ? Self.expandedChevronDegrees : 0))
                // The standard disclosure affordance turns, never
                // jumps.
                .animation(Motion.quick, value: isExpanded(group.repository.path))
                .accessibilityHidden(true)
            avatar(for: group.repository)
            // The avatar already names the owner, so the text keeps
            // to the repository name alone.
            Text(group.repository.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
            // The main checkout is not a worktree, and neither is a
            // directory of your own.
            let worktrees = group.items.count { $0.worktree.isHostDirectory == false } - 1
            if worktrees > 0 {
                Text("(" + String(worktrees) + ")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .hoverHelp("Worktrees beyond the default branch")
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, Self.headerVerticalPadding)
        .contentShape(Rectangle())
    }

    /// Selected rows use the system selection colours, which follow
    /// the user's highlight choice and grey out when the window is
    /// not key, the way every native sidebar's selection does; the
    /// literal accent-and-white pair stayed saturated in inactive
    /// windows and fell below contrast on light accents.
    private func row(for item: WorktreeItem) -> some View {
        let isSelected = model.selection?.id == item.id
        let isEmphasised = isSelected && controlActiveState != .inactive
        let isDeleting = model.deletingPaths.contains(item.worktree.path)
        return Button {
            // A worktree mid-deletion cannot be re-entered; the row
            // only becomes selectable again if the deletion fails.
            guard isDeleting == false else {
                return
            }

            model.select(item)
        } label: {
            WorktreeRowView(
                item: item,
                pullRequest: model.pullRequest(for: item),
                standing: model.stackStanding(for: item),
            )
            // Deleting takes a moment; the row fades the instant the
            // click lands so the click visibly took.
            .opacity(model.deletingPaths.contains(item.worktree.path) ? Self.deletingOpacity : 1)
            .padding(.vertical, Self.rowVerticalPadding)
            .padding(.horizontal, Self.rowHorizontalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isEmphasised ? Color(nsColor: .alternateSelectedControlTextColor) : Color.primary)
        .tint(isEmphasised ? Color(nsColor: .alternateSelectedControlTextColor) : Color.accentColor)
        .background(
            RoundedRectangle(cornerRadius: Self.rowCornerRadius)
                .fill(selectionFill(isSelected: isSelected, isEmphasised: isEmphasised)),
        )
        .padding(.leading, Self.rowIndent)
        .contextMenu { contextActions(for: item) }
        .popover(isPresented: pendingBinding($pendingStack, for: item), arrowEdge: .trailing) {
            StackPopover(item: item, model: model)
        }
        .popover(isPresented: pendingBinding($pendingBranchSwitch, for: item), arrowEdge: .trailing) {
            BranchSwitchPopover(item: item, model: model) { pendingBranchSwitch = nil }
        }
        .confirmationDialog(
            forceDeleteTitle(for: item),
            isPresented: forceDeleteBinding(for: item),
            titleVisibility: .visible,
        ) {
            Button("Delete worktree and branch", role: .destructive) {
                pendingForceDelete = nil
                Task { await model.delete(item: item) }
            }
            Button("Cancel", role: .cancel) { pendingForceDelete = nil }
        } message: {
            Text(forceDeleteMessage(for: item))
        }
    }

    @ViewBuilder
    private func contextActions(for item: WorktreeItem) -> some View {
        if item.worktree.isHostDirectory {
            HostDirectoryActions(item: item, model: model)
        } else {
            WorktreeActions(
                item: item,
                model: model,
                onCleanUp: { await cleanUpOrOffer(item) },
                pendingForceDelete: $pendingForceDelete,
                pendingStack: $pendingStack,
                pendingBranchSwitch: $pendingBranchSwitch,
            )
        }
    }

    /// One image per owner, cached on disk: every repository of an
    /// owner shares it, and a GitHub outage leaves the icons alone.
    private func avatar(for repository: Repository) -> some View {
        OwnerAvatar(owner: repository.owner, size: Self.avatarSize)
            .clipShape(RoundedRectangle(cornerRadius: Self.avatarCornerRadius))
    }

    /// One shape serves both popovers: shown while the pending item
    /// is this row's, cleared when its popover closes.
    private func pendingBinding(
        _ pending: Binding<WorktreeItem?>,
        for item: WorktreeItem,
    ) -> Binding<Bool> {
        Binding(
            get: { pending.wrappedValue?.id == item.id },
            set: { shown in
                if shown == false, pending.wrappedValue?.id == item.id {
                    pending.wrappedValue = nil
                }
            },
        )
    }

    private func forceDeleteBinding(for item: WorktreeItem) -> Binding<Bool> {
        Binding(
            get: { pendingForceDelete?.path == item.worktree.path },
            set: { shown in
                if shown == false, pendingForceDelete?.path == item.worktree.path {
                    pendingForceDelete = nil
                }
            },
        )
    }

    private func forceDeleteTitle(for item: WorktreeItem) -> String {
        "Delete the worktree for \(item.worktree.branch)?"
    }

    /// Names exactly what forcing would destroy, so the choice is
    /// never made on a generic warning.
    private func forceDeleteMessage(for item: WorktreeItem) -> String {
        var losses = [String]()
        if item.isDirty || pendingForceDelete?.refusal == .dirty {
            losses.append("its uncommitted changes")
        }
        if pendingForceDelete?.refusal == .unmerged || (item.aheadOfDefault ?? 0) > 0 {
            losses.append("commits not on the default branch")
        }
        let loss = losses.isEmpty
            ? "The worktree and its branch are removed."
            : "This permanently discards " + losses.joined(separator: " and ") + "."
        return loss + " Conversations stay readable on the repository page."
    }

    /// Cleans up merge-safely and, when refused, offers the confirmed
    /// force delete instead of silently doing nothing.
    private func cleanUpOrOffer(_ item: WorktreeItem) async {
        if let refusal = await model.cleanUp(item: item) {
            pendingForceDelete = (item.worktree.path, refusal)
        }
    }

    /// The selection background: the system's emphasised colour in
    /// a key window, its grey unemphasised one otherwise.
    private func selectionFill(isSelected: Bool, isEmphasised: Bool) -> Color {
        guard isSelected else {
            return .clear
        }

        return isEmphasised
            ? Color(nsColor: .selectedContentBackgroundColor)
            : Color(nsColor: .unemphasizedSelectedContentBackgroundColor)
    }

    private func isExpanded(_ path: String) -> Bool {
        collapsedRepositories.split(separator: "\n").map(String.init).contains(path) == false
    }

    /// Collapsed repositories persist across launches as a
    /// newline-joined path list. The rows animate in and out rather
    /// than popping.
    private func toggleExpansion(of path: String) {
        var collapsed = Set(collapsedRepositories.split(separator: "\n").map(String.init))
        if collapsed.contains(path) {
            collapsed.remove(path)
        } else {
            collapsed.insert(path)
        }
        withAnimation(Motion.quick) {
            collapsedRepositories = collapsed.sorted().joined(separator: "\n")
        }
    }
}

// MARK: - NewRepositoryRow

/// The sidebar's last row: opening a repository not listed yet. A
/// row of the list rather than a button floating above it, with the
/// trailing plus saying it adds rather than selects; its own view
/// for the sidebar's type length.
private struct NewRepositoryRow: View {
    // MARK: Internal

    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: Self.spacing) {
                Text("New repository")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "plus")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, Self.verticalPadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, Self.spacing)
        .hoverHelp("Find a repository across your GitHub organisations; open it here or clone it")
    }

    // MARK: Private

    private static let spacing: CGFloat = 4
    private static let verticalPadding: CGFloat = 5
}
