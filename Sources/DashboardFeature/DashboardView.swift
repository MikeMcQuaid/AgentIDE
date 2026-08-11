import AgentIDEDomain
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
        // An inset, not an overlay: long git errors must never draw
        // over the rows. Clicking opens the full text, since two
        // lines truncate most command failures.
        .safeAreaInset(edge: .bottom) {
            if let status = model.status {
                Button {
                    showsFullStatus = true
                } label: {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(Self.statusLineLimit)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Self.statusPadding)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(.bar)
                .hoverHelp("Click for the full message")
                .popover(isPresented: $showsFullStatus) {
                    ScrollView {
                        Text(status)
                            .font(.caption)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                    .frame(width: Self.statusPopoverWidth, height: Self.statusPopoverHeight)
                }
            }
        }
    }

    // MARK: Private

    private static let statusPadding: CGFloat = 4
    private static let statusLineLimit = 2
    private static let headerTopPadding: CGFloat = 12
    private static let statusPopoverWidth: CGFloat = 420
    private static let statusPopoverHeight: CGFloat = 200
    private static let listPadding: CGFloat = 6
    private static let rowSpacing: CGFloat = 1
    private static let rowVerticalPadding: CGFloat = 3
    private static let rowHorizontalPadding: CGFloat = 6
    private static let rowIndent: CGFloat = 12
    private static let rowCornerRadius: CGFloat = 5
    private static let avatarSize: CGFloat = 14
    private static let avatarCornerRadius: CGFloat = 3
    private static let expandedChevronDegrees: Double = 90

    @AppStorage("collapsedRepositories")
    private var collapsedRepositories = ""

    @State private var showsFullStatus = false

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
                model.newSessionRepository = group.repository
                model.showsNewSession = true
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
            Text(group.repository.fullName ?? group.repository.name)
                .font(.callout.weight(.semibold))
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
        .padding(.vertical, Self.rowVerticalPadding)
        .contentShape(Rectangle())
    }

    /// Selected rows use the full accent fill with light content,
    /// matching native sidebar selection.
    private func row(for item: WorktreeItem) -> some View {
        let isSelected = model.selection?.id == item.id
        return Button {
            model.select(item)
        } label: {
            WorktreeRowView(
                item: item,
                pullRequest: model.pullRequest(for: item),
                stackDepth: model.stackDepth(for: item),
            )
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
    }

    @ViewBuilder
    private func contextActions(for item: WorktreeItem) -> some View {
        Button("Fetch") { Task { await model.fetch(item: item) } }
            .hoverHelp("git fetch all remotes of this repository")
        Button("Mark as unread") { Task { await model.markUnread(item: item) } }
            .hoverHelp("Show the unread dot until this worktree is next viewed")
        if item.worktree.path != item.worktree.repositoryPath {
            Button("Delete worktree") { Task { await model.delete(item: item) } }
                .hoverHelp("Deletes the worktree and branch; conversations stay on the repository page")
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
