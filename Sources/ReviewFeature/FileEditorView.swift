import AgentIDEData
import AgentIDEDomain
import SwiftUI
import TerminalUI

/// A syntax-highlighted editor for one file in the worktree, with
/// line numbers, visible invisibles and uncommitted-line markers,
/// for review-time fixes.
struct FileEditorView: View {
    // MARK: Lifecycle

    /// Creates an editor for a file relative to the worktree,
    /// optionally jumping to a line. `onClose` closes an embedding
    /// owner; `showsClose: false` suits inline embeddings that have
    /// nothing to close.
    init(
        worktreePath: String,
        relativePath: String,
        service: SessionService,
        jumpToLine: Int? = nil,
        showsClose: Bool = true,
        onClose: (() -> Void)? = nil,
    ) {
        self.worktreePath = worktreePath
        self.relativePath = relativePath
        self.service = service
        self.jumpToLine = jumpToLine
        self.showsClose = showsClose
        self.onClose = onClose
    }

    // MARK: Internal

    /// The editor with icon save and close actions. Save enables
    /// only with unsaved changes and reports Saved after writing.
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(relativePath).font(.headline.monospaced())
                Spacer()
                if let status {
                    Text(status).font(.callout).foregroundStyle(.secondary)
                }
                Button("Save", systemImage: "square.and.arrow.down") { save() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .disabled(hasChanges == false)
                    .keyboardShortcut("s", modifiers: .command)
                    .hoverHelp("Write the buffer back to the file (Cmd-S); dims until there are changes")
                if showsClose {
                    Button("Close", systemImage: "xmark") { close() }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .hoverHelp("Close the editor without saving")
                }
            }
            .padding(Self.padding)
            Divider()
            HighlightingTextEditor(
                text: $content,
                language: SyntaxLanguage.language(forPath: relativePath),
                jumpToLine: jumpToLine,
                changedLines: changedLines,
            )
        }
        .onAppear { load() }
        // Editing again invalidates the save report, but real error
        // messages stay until resolved.
        .onChange(of: content) {
            if status == Self.savedStatus {
                status = nil
            }
        }
    }

    // MARK: Private

    private static let padding: CGFloat = 8
    private static let savedStatus = "Saved."

    @State private var content = ""
    @State private var saved = ""
    @State private var changedLines: Set<Int> = []
    @State private var status: String?

    @Environment(\.dismiss)
    private var dismiss

    private let worktreePath: String
    private let relativePath: String
    private let service: SessionService
    private let jumpToLine: Int?
    private let showsClose: Bool
    private let onClose: (() -> Void)?

    private var hasChanges: Bool {
        content != saved
    }

    /// The resolved path, but only when it stays inside the worktree:
    /// a hostile repository could put `../` in a diff path.
    private var safePath: String? {
        let base = URL(fileURLWithPath: worktreePath).standardizedFileURL.path
        let target = URL(fileURLWithPath: worktreePath + "/" + relativePath).standardizedFileURL.path
        return target == base || target.hasPrefix(base + "/") ? target : nil
    }

    private func load() {
        guard let safePath else {
            ErrorLog.shared.report("Refusing to open a path outside the worktree.")
            return
        }

        content = (try? String(contentsOfFile: safePath, encoding: .utf8)) ?? ""
        saved = content
        reloadChangedLines()
    }

    private func save() {
        guard let safePath else {
            ErrorLog.shared.report("Refusing to write a path outside the worktree.")
            return
        }

        do {
            content = Whitespace.strippingTrailingWhitespace(content)
            try content.write(toFile: safePath, atomically: true, encoding: .utf8)
            saved = content
            status = Self.savedStatus
            reloadChangedLines()
        } catch {
            ErrorLog.shared.report(error.localizedDescription)
        }
    }

    private func close() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }

    /// Marks lines uncommitted against HEAD in the gutter; buffer
    /// edits count only once saved to disk.
    private func reloadChangedLines() {
        Task {
            changedLines = await service.changedLineNumbers(worktreePath: worktreePath, file: relativePath)
        }
    }
}
