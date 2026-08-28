import AgentIDEData
import AgentIDEDomain
import SwiftUI
import TerminalUI

// MARK: - EditorPane

/// The editor tab: one field that either finds files by fuzzy name
/// or searches contents with ripgrep, toggled beside it, with the
/// picked file edited in place. Cmd-T focuses the finder.
public struct EditorPane: View {
    // MARK: Lifecycle

    /// Creates the pane for a worktree. `waitingEdit` is a file some
    /// command outside the app is blocked on, which takes the pane
    /// over until it is dealt with.
    public init(
        worktreePath: String,
        service: SessionService,
        onFinishedWaiting: (() -> Void)? = nil,
        waitingEdit: ExternalEdit? = nil,
    ) {
        self.worktreePath = worktreePath
        self.service = service
        self.waitingEdit = waitingEdit
        self.onFinishedWaiting = onFinishedWaiting
    }

    // MARK: Public

    /// The pinned finder field over results, over the embedded
    /// editor. Arrow keys move the highlight and return opens it.
    public var body: some View {
        VStack(spacing: 0) {
            if let edit = blockingEdit {
                // The finder is beside the point while a command is
                // stopped waiting on one particular file.
                FileEditorView(waitingOn: edit) { saved in finish(edit, saved: saved) }
                    .id(edit.id)
            } else {
                finder
            }
        }
        .task(id: worktreePath) {
            files = await service.listFiles(worktreePath: worktreePath)
            target = nil
            openStoredFile()
            if query.isEmpty == false {
                search()
            }
        }
        // Runs on mount and on later requests, so the menu's finder
        // shortcuts focus the field even when the pane was hidden.
        .task(id: finderFocusRequest) { consumeFocusRequest() }
        // Open-file requests from other panes and the previous run.
        .task(id: editorFileRequest) { openStoredFile() }
    }

    // MARK: Private

    /// One row of the result list: a file, or a content match with
    /// the matched line's text.
    private struct Result: Identifiable, Hashable {
        let file: String
        let line: Int?
        var preview: String?

        var id: String {
            file + ":" + String(line ?? 0)
        }
    }

    private static let padding: CGFloat = 6
    private static let fieldTopPadding: CGFloat = 4
    private static let fileResultLimit = 12
    private static let contentQueryMinimum = 3
    private static let resultsHeight: CGFloat = 180
    private static let fieldCornerRadius: CGFloat = 6
    private static let fieldBackgroundOpacity = 0.5
    private static let highlightOpacity = 0.25
    private static let rowVerticalPadding: CGFloat = 2

    @State private var files: [String] = []
    @State private var results: [Result] = []
    @State private var target: Result?
    @State private var highlighted = 0
    @State private var handledFocusRequest = 0

    /// The waiting file already dealt with, so the pane returns to
    /// the finder as soon as the buttons are pressed.
    @State private var finishedEdit: String?

    /// The query, mode and open file persist across restarts.
    @AppStorage("finderQuery")
    private var query = ""
    @AppStorage("finderSearchesContents")
    private var searchesContents = false
    @AppStorage("finderFocusRequest")
    private var finderFocusRequest = 0
    @AppStorage("editorFileRequest")
    private var editorFileRequest = 0
    @AppStorage("editorFilePath")
    private var editorFilePath = ""
    @AppStorage("editorFileLine")
    private var editorFileLine = 0
    @AppStorage("editorFileWorktree")
    private var editorFileWorktree = ""

    @FocusState private var finderFocused: Bool

    private let worktreePath: String
    private let service: SessionService
    private let waitingEdit: ExternalEdit?

    /// Told when a waiting file is dealt with, so the pane the
    /// command interrupted can come straight back.
    private let onFinishedWaiting: (() -> Void)?

    /// The file this pane is blocked on, until it is finished with:
    /// the answer takes a moment to reach the spool and come back,
    /// and the pane must not flash the file again in between.
    private var blockingEdit: ExternalEdit? {
        waitingEdit?.id == finishedEdit ? nil : waitingEdit
    }

    /// The finder over its results over the file being edited. Arrow
    /// keys move the highlight and return opens it.
    @ViewBuilder private var finder: some View {
        finderField
        if query.isEmpty == false, results.isEmpty == false {
            resultsList
            Divider()
        }
        if let target {
            editor(for: target)
        } else {
            ContentUnavailableView(
                "No file open",
                systemImage: "doc.text",
                description: Text("Cmd-T finds a file to edit."),
            )
        }
    }

    /// A search-field look: magnifier, plain field and a clear
    /// button, pinned above everything else.
    private var finderField: some View {
        HStack(spacing: Self.padding) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(searchesContents ? "Search contents" : "Find files", text: $query)
                .textFieldStyle(.plain)
                .focused($finderFocused)
                .onChange(of: query) { highlighted = 0; search() }
                .onSubmit { pickHighlighted() }
                .onKeyPress(.downArrow) { moveHighlight(by: 1) }
                .onKeyPress(.upArrow) { moveHighlight(by: -1) }
                // Escape clears the search, the way it cancels
                // anywhere else.
                .onExitCommand {
                    query = ""
                    results = []
                }
            modePicker
            if query.isEmpty == false {
                Button {
                    query = ""
                    results = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Clear search")
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Self.padding)
        .padding(.vertical, Self.padding - 1)
        .background(
            RoundedRectangle(cornerRadius: Self.fieldCornerRadius)
                .fill(.quaternary.opacity(Self.fieldBackgroundOpacity)),
        )
        .padding([.horizontal, .bottom], Self.padding)
        // A little air below the utility tab bar above.
        .padding(.top, Self.fieldTopPadding)
        .hoverHelp("Cmd-T focuses this; the toggle switches between fuzzy file names and ripgrep contents")
    }

    private var modePicker: some View {
        Picker("Mode", selection: $searchesContents) {
            Text("Files").tag(false)
            Text("Contents").tag(true)
        }
        .pickerStyle(.segmented)
        .controlSize(.small)
        .labelsHidden()
        .fixedSize()
        .onChange(of: searchesContents) { highlighted = 0; search() }
        .hoverHelp("Files matches paths fuzzily; Contents searches file text with ripgrep")
    }

    private var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                        FinderResultRow(
                            file: result.file,
                            line: result.line,
                            preview: result.preview,
                            isHighlighted: index == highlighted,
                        )
                        .onTapGesture { pick(result) }
                        .id(index)
                    }
                }
            }
            // Arrowing past the visible rows scrolls the highlight
            // into view rather than moving it off screen.
            .onChange(of: highlighted) { proxy.scrollTo(highlighted) }
        }
        .frame(maxHeight: Self.resultsHeight)
        .hoverHelp("Arrows move the highlight; return or a click opens")
    }

    private func editor(for result: Result) -> some View {
        FileEditorView(
            worktreePath: worktreePath,
            relativePath: result.file,
            service: service,
            jumpToLine: result.line,
        ) {
            target = nil
            editorFilePath = ""
        }
        .id(result.id)
    }

    /// Opens the stored file when it belongs to this worktree; the
    /// store survives restarts and other panes write it.
    private func openStoredFile() {
        guard editorFileWorktree == worktreePath, editorFilePath.isEmpty == false else {
            return
        }

        target = Result(file: editorFilePath, line: editorFileLine > 0 ? editorFileLine : nil)
    }

    /// Releases the command waiting on the file and returns the
    /// pane to its finder.
    private func finish(_ edit: ExternalEdit, saved: Bool) {
        finishedEdit = edit.id
        onFinishedWaiting?()
        Task { await service.finishEdit(edit, saved: saved) }
    }

    private func consumeFocusRequest() {
        guard finderFocusRequest > handledFocusRequest else {
            return
        }

        handledFocusRequest = finderFocusRequest
        finderFocused = true
    }

    private func moveHighlight(by offset: Int) -> KeyPress.Result {
        guard results.isEmpty == false else {
            return .ignored
        }

        highlighted = min(max(0, highlighted + offset), results.count - 1)
        return .handled
    }

    private func pickHighlighted() {
        guard results.indices.contains(highlighted) else {
            return
        }

        pick(results[highlighted])
    }

    /// Every open routes through the opener: the Editor tab by
    /// default, the external editor on Cmd-click.
    private func pick(_ result: Result?) {
        guard let result else {
            return
        }

        FileOpener.open(relativePath: result.file, line: result.line, worktreePath: worktreePath)
        query = ""
        results = []
    }

    private func search() {
        guard searchesContents else {
            let matches = FuzzyMatcher.rank(files, query: query)
                .prefix(Self.fileResultLimit)
                .map { Result(file: $0, line: nil) }
            results = Array(matches)
            return
        }

        results = []
        guard query.count >= Self.contentQueryMinimum else {
            return
        }

        Task {
            let hits = await service.search(worktreePath: worktreePath, query: query)
            guard searchesContents, query.count >= Self.contentQueryMinimum else {
                return
            }

            results = hits.map { hit in
                Result(
                    file: hit.file,
                    line: hit.line,
                    preview: hit.text.trimmingCharacters(in: .whitespaces),
                )
            }
        }
    }
}

// MARK: - FinderResultRow

/// One finder result row; its own view so the pane's type body
/// stays within the length limit.
private struct FinderResultRow: View {
    // MARK: Internal

    let file: String
    let line: Int?
    let preview: String?
    let isHighlighted: Bool

    var body: some View {
        HStack(spacing: Self.padding) {
            Image(systemName: line == nil ? "doc.text" : "text.magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(file + (line.map { ":" + String($0) } ?? ""))
                .font(CodeStyle.font)
                .lineLimit(1)
            if let preview {
                Text(preview)
                    .font(CodeStyle.font)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Self.padding)
        .padding(.vertical, Self.rowVerticalPadding)
        .background(isHighlighted ? Color.accentColor.opacity(Self.highlightOpacity) : .clear)
        .contentShape(Rectangle())
    }

    // MARK: Private

    private static let padding: CGFloat = 6
    private static let highlightOpacity = 0.25
    private static let rowVerticalPadding: CGFloat = 2
}
