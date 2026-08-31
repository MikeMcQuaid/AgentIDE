import AgentIDEData
import AgentIDEDomain
import SwiftUI
import TerminalUI

/// A syntax-highlighted editor for one file, with line numbers,
/// visible invisibles and uncommitted-line markers, for review-time
/// fixes and for the files commands outside the app wait on.
struct FileEditorView: View {
    // MARK: Lifecycle

    /// Creates an editor for a file relative to the worktree,
    /// optionally jumping to a line. `move` offers sending the file
    /// to the other editor slot; `onClose` closes an embedding
    /// owner; `showsClose: false` suits inline embeddings that have
    /// nothing to close.
    init(
        worktreePath: String,
        relativePath: String,
        service: SessionService,
        jumpToLine: Int? = nil,
        showsClose: Bool = true,
        move: PaneMove? = nil,
        onClose: (() -> Void)? = nil,
    ) {
        // A hostile repository could put `../` in a diff path, so a
        // file that resolves outside the worktree gets no path at
        // all and the editor refuses to read or write it.
        let base = URL(fileURLWithPath: worktreePath).standardizedFileURL.path
        // A path of its own is the file: `agentide` can be handed
        // something outside every worktree, which opens in whichever
        // one is on screen rather than not at all.
        let target = relativePath.hasPrefix("/")
            ? URL(fileURLWithPath: relativePath).standardizedFileURL.path
            : URL(fileURLWithPath: worktreePath + "/" + relativePath).standardizedFileURL.path
        path = target == base || target.hasPrefix(base + "/") ? target : nil
        title = relativePath
        language = SyntaxLanguage.language(forPath: relativePath)
        changedLines = { await service.changedLineNumbers(worktreePath: worktreePath, file: relativePath) }
        self.jumpToLine = jumpToLine
        self.showsClose = showsClose
        self.move = move
        self.onClose = onClose
        onFinish = nil
    }

    /// Creates an editor for a file a command is waiting on, which
    /// is regularly outside every worktree: git keeps a linked
    /// worktree's rebase todo list in the repository's own `.git`
    /// directory. Finishing releases the command, and cancelling
    /// fails it, which is how a rebase is aborted.
    init(waitingOn edit: ExternalEdit, onFinish: @escaping (Bool) -> Void) {
        path = edit.path
        title = edit.name
        language = SyntaxLanguage.language(forPath: edit.path)
        changedLines = nil
        jumpToLine = nil
        showsClose = false
        move = nil
        onClose = nil
        self.onFinish = onFinish
    }

    // MARK: Internal

    /// Sending the open file to the other editor slot: what the
    /// button looks like and what it runs once the file is saved.
    struct PaneMove {
        let action: () -> Void
        let icon: String
        let help: String
    }

    /// The editor under its header. Save enables only with unsaved
    /// changes and reports Saved after writing; a file some command
    /// waits on says so and finishes it instead of closing.
    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(Self.padding)
            Divider()
            if rendersMarkdown, isMarkdown {
                ScrollView {
                    MarkdownText(content)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Self.padding)
                }
            } else {
                HighlightingTextEditor(
                    text: $content,
                    language: language,
                    jumpToLine: jumpToLine,
                    changedLines: markedLines,
                )
            }
        }
        .onAppear { load() }
        // A displaced editor keeps its typing: the pane can go off
        // screen without a close (a worktree switch, a session
        // appearing, a move to the other slot), and losing the
        // buffer there would be silent. The Close button stays the
        // one deliberate discard, and a waiting file must never be
        // written behind its command's back.
        .onDisappear {
            if onFinish == nil, closedWithoutSaving == false, hasChanges {
                save()
            }
        }
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
    private static let failedStatus = "Not saved."

    @State private var content = ""
    @State private var saved = ""
    @State private var markedLines: Set<Int> = []
    @State private var status: String?
    @State private var rendersMarkdown = false

    /// Whether Close discarded the buffer, which the disappearing
    /// autosave must honour rather than writing it anyway.
    @State private var closedWithoutSaving = false

    @Environment(\.dismiss)
    private var dismiss

    /// The file, absolute and already checked; nil when the path
    /// resolved outside the worktree it claimed to be in.
    private let path: String?
    private let title: String
    private let language: SyntaxLanguage?

    /// Which lines the gutter marks as uncommitted, absent for a
    /// file that belongs to no worktree.
    private let changedLines: (() async -> Set<Int>)?
    private let jumpToLine: Int?
    private let showsClose: Bool
    private let move: PaneMove?
    private let onClose: (() -> Void)?

    /// Releases the command waiting on this file, saved or not.
    private let onFinish: ((Bool) -> Void)?

    private var hasChanges: Bool {
        content != saved
    }

    /// Whether the file is Markdown, the one kind the render button
    /// appears for.
    private var isMarkdown: Bool {
        title.lowercased().hasSuffix(".md") || title.lowercased().hasSuffix(".markdown")
    }

    /// The file's name beside what can be done to it. The primary
    /// action exists only while a command waits, since that is the
    /// only time closing the editor decides anything.
    private var header: some View {
        HStack {
            Text(title).font(.headline.monospaced())
            if onFinish != nil {
                Text("A command is waiting").font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            if let status {
                Text(status).font(.callout).foregroundStyle(.secondary)
            }
            if isMarkdown {
                markdownToggle
            }
            if let move {
                // Only a file that reached the disk moves: the other
                // slot re-reads it from there, so moving an unsaved
                // buffer would silently drop the typing.
                Button("Move to other pane", systemImage: move.icon) {
                    if hasChanges == false || save() {
                        move.action()
                    }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .hoverHelp(move.help)
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
            waitingActions
        }
    }

    /// The Markdown-only toggle between source and rendered views;
    /// the render is read-only, so Save keeps meaning the source.
    private var markdownToggle: some View {
        Button("Render Markdown", systemImage: rendersMarkdown ? "doc.plaintext" : "doc.richtext") {
            rendersMarkdown.toggle()
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .hoverHelp(
            rendersMarkdown
                ? "Show the Markdown source for editing"
                : "Render the Markdown in place",
        )
    }

    /// What a file some command is waiting on offers instead of a
    /// close: finish it, or fail it and let the command deal with
    /// that, which is how a rebase is aborted.
    @ViewBuilder private var waitingActions: some View {
        if let onFinish {
            Button("Cancel") { onFinish(false) }
                .buttonStyle(.glass)
                .hoverHelp("Leave the file as it was and fail the waiting command, which aborts a rebase")
            // Only a file that actually reached the disk lets the
            // command carry on: a failed write would otherwise leave
            // git rebasing with the edit it never got.
            Button("Save and close") {
                if save() {
                    onFinish(true)
                }
            }
            .buttonStyle(.glassProminent)
            .keyboardShortcut(.return, modifiers: .command)
            .hoverHelp("Write the file and let the waiting command carry on (Cmd-Return)")
        }
    }

    private func load() {
        guard let path else {
            ErrorLog.shared.report("Refusing to open a path outside the worktree.")
            return
        }

        content = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        saved = content
        reloadChangedLines()
    }

    /// Writes the buffer back, reporting whether it landed.
    @discardableResult
    private func save() -> Bool {
        guard let path else {
            // The header says so too: a button that only writes to
            // the errors tab reads as a button that does nothing.
            status = Self.failedStatus
            ErrorLog.shared.report("Refusing to write a path outside the worktree.")
            return false
        }

        do {
            content = Whitespace.strippingTrailingWhitespace(content)
            try content.write(toFile: path, atomically: true, encoding: .utf8)
            saved = content
            status = Self.savedStatus
            reloadChangedLines()
            return true
        } catch {
            ErrorLog.shared.report(error.localizedDescription)
            status = Self.failedStatus
            return false
        }
    }

    private func close() {
        closedWithoutSaving = true
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }

    /// Marks lines uncommitted against HEAD in the gutter; buffer
    /// edits count only once saved to disk.
    private func reloadChangedLines() {
        guard let changedLines else {
            return
        }

        Task { markedLines = await changedLines() }
    }
}
