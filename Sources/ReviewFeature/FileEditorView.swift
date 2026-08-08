import SwiftUI

/// A plain text editor for one file in the worktree, for review-time
/// fixes.
struct FileEditorView: View {
    // MARK: Lifecycle

    /// Creates an editor for a file relative to the worktree.
    init(worktreePath: String, relativePath: String) {
        self.worktreePath = worktreePath
        self.relativePath = relativePath
    }

    // MARK: Internal

    /// The editor with save and close actions.
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(relativePath).font(.headline.monospaced())
                Spacer()
                if let status {
                    Text(status).font(.callout).foregroundStyle(.secondary)
                }
                Button("Save") { save() }
                Button("Close") { dismiss() }
            }
            .padding(Self.padding)
            Divider()
            TextEditor(text: $content)
                .font(.body.monospaced())
        }
        .frame(minWidth: Self.minimumWidth, minHeight: Self.minimumHeight)
        .onAppear { load() }
    }

    // MARK: Private

    private static let padding: CGFloat = 8
    private static let minimumWidth: CGFloat = 640
    private static let minimumHeight: CGFloat = 480

    @State private var content = ""
    @State private var status: String?

    @Environment(\.dismiss)
    private var dismiss

    private let worktreePath: String
    private let relativePath: String

    /// The resolved path, but only when it stays inside the worktree:
    /// a hostile repository could put `../` in a diff path.
    private var safePath: String? {
        let base = URL(fileURLWithPath: worktreePath).standardizedFileURL.path
        let target = URL(fileURLWithPath: worktreePath + "/" + relativePath).standardizedFileURL.path
        return target == base || target.hasPrefix(base + "/") ? target : nil
    }

    private func load() {
        guard let safePath else {
            status = "Refusing to open a path outside the worktree."
            return
        }

        content = (try? String(contentsOfFile: safePath, encoding: .utf8)) ?? ""
    }

    private func save() {
        guard let safePath else {
            status = "Refusing to write a path outside the worktree."
            return
        }

        do {
            try content.write(toFile: safePath, atomically: true, encoding: .utf8)
            status = "Saved."
        } catch {
            status = error.localizedDescription
        }
    }
}
