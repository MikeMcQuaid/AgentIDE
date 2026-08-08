import AgentIDEDomain
import SwiftUI

/// The sidebar listing worktrees grouped by repository, foreign
/// sessions and undeletable archives.
public struct DashboardView: View {
    // MARK: Lifecycle

    /// Creates the sidebar for a model.
    public init(model: DashboardModel) {
        self.model = model
    }

    // MARK: Public

    /// The grouped list with badges and lifecycle context menus.
    public var body: some View {
        List(selection: selectionBinding) {
            ForEach(model.groups) { group in
                if group.items.isEmpty == false {
                    section(for: group)
                }
            }
            foreignSection
            archivesSection
        }
        .toolbar {
            Button("New session", systemImage: "plus") { model.showsNewSession = true }
        }
        .overlay(alignment: .bottom) {
            if let status = model.status {
                Text(status).font(.callout).foregroundStyle(.secondary).padding(Self.statusPadding)
            }
        }
    }

    // MARK: Private

    private static let statusPadding: CGFloat = 4

    private let model: DashboardModel

    private var selectionBinding: Binding<WorktreeItem?> {
        Binding(get: { model.selection }, set: { model.selection = $0 })
    }

    @ViewBuilder private var foreignSection: some View {
        if model.foreign.isEmpty == false {
            Section("Foreign sessions") {
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
                }
            }
        }
    }

    @ViewBuilder private var archivesSection: some View {
        if model.archives.isEmpty == false {
            Section("Archives") {
                ForEach(model.archives) { archive in
                    Label {
                        VStack(alignment: .leading) {
                            Text("\(archive.repositoryName): \(archive.branch)")
                            Text(archive.archivedAt, format: .relative(presentation: .named))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "archivebox")
                    }
                    .contextMenu {
                        Button("Undelete") { Task { await model.undelete(archive: archive) } }
                    }
                }
            }
        }
    }

    private func section(for group: RepositoryGroup) -> some View {
        Section(group.repository.name) {
            ForEach(group.items) { item in
                WorktreeRowView(item: item)
                    .tag(item)
                    .contextMenu {
                        Button("Archive and delete") { Task { await model.archive(item: item) } }
                    }
            }
        }
    }
}
