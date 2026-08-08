import AgentIDEData
import AgentIDEDomain
import SwiftUI

/// A pull-request-style review of the worktree's changes with
/// per-line rejection, commit message editing and a file editor.
public struct ReviewView: View {
    // MARK: Lifecycle

    /// Creates the review view.
    public init(worktreePath: String, git: GitClient) {
        self.worktreePath = worktreePath
        _model = State(initialValue: ReviewModel(worktreePath: worktreePath, git: git))
    }

    // MARK: Public

    /// The toolbar, diff list and commit message editor.
    public var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            diffList
            Divider()
            footer
        }
        .task(id: worktreePath) { await model.reload() }
    }

    // MARK: Private

    private struct EditTarget: Identifiable {
        let path: String

        var id: String {
            path
        }
    }

    private static let spacing: CGFloat = 8
    private static let messageLineLimit = 1 ... 3

    @State private var model: ReviewModel
    @State private var editingFile: EditTarget?

    private let worktreePath: String

    private var toolbar: some View {
        HStack {
            Text(model.showsUncommitted ? "Uncommitted changes" : "Last commit")
                .font(.headline)
            Toggle("Show generated", isOn: $model.showsGenerated)
            Spacer()
            Button("Reject selected lines") { Task { await model.rejectSelected() } }
                .disabled(model.selections.values.allSatisfy(\.isEmpty))
            Button("Refresh") { Task { await model.reload() } }
        }
        .padding(Self.spacing)
    }

    private var diffList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Self.spacing) {
                ForEach(model.visibleFiles) { file in
                    DiffFileView(file: file, model: model) { editingFile = EditTarget(path: file.path) }
                }
                if model.visibleFiles.isEmpty {
                    ContentUnavailableView("No changes", systemImage: "checkmark.circle")
                }
            }
            .padding(Self.spacing)
        }
        .sheet(item: $editingFile) { target in
            FileEditorView(worktreePath: worktreePath, relativePath: target.path)
        }
    }

    private var footer: some View {
        HStack {
            TextField("Commit message", text: $model.commitMessage, axis: .vertical)
                .lineLimit(Self.messageLineLimit)
            Button("Amend message") { Task { await model.saveCommitMessage() } }
                .disabled(model.showsUncommitted)
            if let status = model.status {
                Text(status).font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(Self.spacing)
    }
}
