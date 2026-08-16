import AgentIDEData
import AgentIDEDomain
import AppKit
import SwiftUI
import TerminalUI

/// The sidebar listing worktrees grouped by repository and foreign
/// sessions. Built on a plain scroll view rather than a list: the
/// outline-backed list both crashed and ignored collapses when
/// sections removed their rows, and rows here are simple enough not
/// to need one.
public struct DashboardView: View {
    // MARK: Lifecycle

    /// Creates the sidebar for a model.
    public init(model: DashboardModel) {
        self.model = model
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
                foreignSection
            }
            .padding(Self.listPadding)
        }
        // The traffic lights occupy the top-left; Open repository
        // sits at the band's right end, and the inset spaces the
        // first repository row beneath it.
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Spacer()
                Button("Open repository", systemImage: "plus") { model.showsRepositoryFinder = true }
                    .labelStyle(.iconOnly)
                    // The glass bubble the split view's own floating
                    // toggle used to draw.
                    .buttonStyle(.glass)
                    .hoverHelp("Find a repository across your GitHub organisations; open it here or clone it")
            }
            .padding(.trailing, Self.listPadding)
            .padding(.top, Self.headerTopPadding)
            .padding(.bottom, Self.statusPadding)
        }
    }

    // MARK: Private

    private static let statusPadding: CGFloat = 4
    private static let headerTopPadding: CGFloat = 12
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

    @AppStorage("collapsedRepositories")
    private var collapsedRepositories = ""

    /// The pending confirmed deletion: which worktree, and what the
    /// merge-safe path refused about it (nil for a plain Delete
    /// worktree, which always confirms since it always forces).
    @State private var pendingForceDelete: (path: String, refusal: SessionService.CleanupRefusal?)?

    private let model: DashboardModel

    @ViewBuilder private var foreignSection: some View {
        if model.foreign.isEmpty == false {
            Text("Foreign sessions")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.top, Self.rowIndent)
            ForEach(model.foreign) { session in
                Label {
                    VStack(alignment: .leading) {
                        Text(session.name)
                        if let directory = session.workingDirectory {
                            Text(directory).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } icon: {
                    Image(systemName: "questionmark.circle")
                }
                .padding(.leading, Self.rowIndent)
            }
        }
    }

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
    }

    private func headerLabel(for group: RepositoryGroup) -> some View {
        HStack(spacing: Self.statusPadding) {
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .rotationEffect(.degrees(isExpanded(group.repository.path) ? Self.expandedChevronDegrees : 0))
                .accessibilityHidden(true)
            avatar(for: group.repository)
            // The avatar already names the owner, so the text keeps
            // to the repository name alone.
            Text(group.repository.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
            if group.items.count > 1 {
                Text("(" + String(group.items.count - 1) + ")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .hoverHelp("Worktrees beyond the default branch")
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, Self.headerVerticalPadding)
        .contentShape(Rectangle())
    }

    /// Selected rows use the full accent fill with light content,
    /// matching native sidebar selection.
    private func row(for item: WorktreeItem) -> some View {
        let isSelected = model.selection?.id == item.id
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
                stackDepth: model.stackDepth(for: item),
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
        .foregroundStyle(isSelected ? Color.white : Color.primary)
        .tint(isSelected ? Color.white : Color.accentColor)
        .background(
            RoundedRectangle(cornerRadius: Self.rowCornerRadius)
                .fill(isSelected ? Color.accentColor : Color.clear),
        )
        .padding(.leading, Self.rowIndent)
        .contextMenu { contextActions(for: item) }
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
        Button("Copy branch name") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(item.worktree.branch, forType: .string)
        }
        .hoverHelp("Copy this worktree's branch name")
        Button("Copy path") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(item.worktree.path, forType: .string)
        }
        .hoverHelp("Copy this worktree's full path")
        Button("Fetch") { Task { await model.fetch(item: item) } }
            .hoverHelp("git fetch all remotes of this repository")
        if item.worktree.path == item.worktree.repositoryPath {
            Button("Fetch and Reset") { Task { await model.fetchAndReset(item: item) } }
                .hoverHelp(
                    "git fetch origin, then hard-reset to origin's default branch; local changes are lost",
                )
        }
        Button("Mark as unread") { Task { await model.markUnread(item: item) } }
            .hoverHelp("Show the unread dot until this worktree is next viewed")
        // Cleanup is the merge-time tidy, offered by hand for merges
        // the poll has not noticed yet or made outside GitHub; on the
        // main checkout it only makes sense off the default branch.
        if item.worktree.path != item.worktree.repositoryPath || model.isOffDefaultBranch(item) {
            Button("Clean up after merge") { Task { await cleanUpOrOffer(item) } }
                .hoverHelp(
                    item.worktree.path == item.worktree.repositoryPath
                        ? "Return to the default branch and safely delete this merged branch; "
                        + "dirty checkouts are left alone"
                        : "Remove this worktree once its branch is merged and clean; "
                        + "anything that would lose work asks first",
                )
        }
        if item.worktree.path != item.worktree.repositoryPath {
            Button("Delete worktree", role: .destructive) { pendingForceDelete = (item.worktree.path, nil) }
                .hoverHelp("Force-deletes the worktree and branch after confirming what would be lost")
        }
    }

    private func avatar(for repository: Repository) -> some View {
        AsyncImage(url: avatarURL(for: repository)) { image in
            image.resizable()
        } placeholder: {
            Image(systemName: "folder.fill").font(.caption2)
        }
        .frame(width: Self.avatarSize, height: Self.avatarSize)
        .clipShape(RoundedRectangle(cornerRadius: Self.avatarCornerRadius))
        .accessibilityHidden(true)
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

    private func isExpanded(_ path: String) -> Bool {
        collapsedRepositories.split(separator: "\n").map(String.init).contains(path) == false
    }

    /// Collapsed repositories persist across launches as a
    /// newline-joined path list.
    private func toggleExpansion(of path: String) {
        var collapsed = Set(collapsedRepositories.split(separator: "\n").map(String.init))
        if collapsed.contains(path) {
            collapsed.remove(path)
        } else {
            collapsed.insert(path)
        }
        collapsedRepositories = collapsed.sorted().joined(separator: "\n")
    }

    private func avatarURL(for repository: Repository) -> URL? {
        repository.owner.flatMap { URL(string: "https://github.com/" + $0 + ".png?size=64") }
    }
}
