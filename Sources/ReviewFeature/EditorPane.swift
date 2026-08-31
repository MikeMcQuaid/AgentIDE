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

    /// Creates the pane for a worktree. `role` names the slot this
    /// instance fills, whose persisted state stays its own;
    /// `onMoveFile`, when given, offers sending the open file to the
    /// other slot; `waitingEdit` is a file some command outside the
    /// app is blocked on, which takes the pane over until it is
    /// dealt with.
    public init(
        worktreePath: String,
        service: SessionService,
        role: Role = .utility,
        onMoveFile: ((_ file: String, _ line: Int?) -> Void)? = nil,
        onFinishedWaiting: (() -> Void)? = nil,
        waitingEdit: ExternalEdit? = nil,
    ) {
        self.worktreePath = worktreePath
        self.service = service
        self.role = role
        self.onMoveFile = onMoveFile
        self.waitingEdit = waitingEdit
        self.onFinishedWaiting = onFinishedWaiting
        _query = AppStorage(wrappedValue: "", role.key("finderQuery"))
        _searchesContents = AppStorage(wrappedValue: false, role.key("finderSearchesContents"))
        _finderFocusRequest = AppStorage(wrappedValue: 0, role.key("finderFocusRequest"))
        _editorFileRequest = AppStorage(wrappedValue: 0, role.key("editorFileRequest"))
        _editorFilePath = AppStorage(wrappedValue: "", role.key("editorFilePath"))
        _editorFileLine = AppStorage(wrappedValue: 0, role.key("editorFileLine"))
        _editorFileWorktree = AppStorage(wrappedValue: "", role.key("editorFileWorktree"))
    }

    // MARK: Public

    /// The slot an editor pane fills. Each slot keeps its own finder
    /// and open file under key-suffixed defaults, so two mounted
    /// editors never answer one request twice; the window routes
    /// requests between them by these names.
    public enum Role: String, CaseIterable, Sendable {
        // The case names are the persisted key suffixes (SwiftFormat
        // strips explicit raw values); keep names stable or migrate
        // deliberately. Centre first: a file open in both slots
        // routes to the visible centre before the side.
        // swiftlint:disable explicit_enum_raw_value
        case centre
        case utility
        // swiftlint:enable explicit_enum_raw_value

        /// The slot's defaults key for one of the shared base names.
        public func key(_ base: String) -> String {
            base + "." + rawValue
        }

        /// The other slot, where a moved file lands.
        public var other: Role {
            self == .centre ? .utility : .centre
        }
    }

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

    @State private var files: [String] = []
    @State private var results: [Result] = []
    @State private var target: Result?
    @State private var highlighted = 0
    @State private var handledFocusRequest = 0

    /// The waiting file already dealt with, so the pane returns to
    /// the finder as soon as the buttons are pressed.
    @State private var finishedEdit: String?

    /// The query, mode and open file persist across restarts, each
    /// under the slot's own keys, set in the initialiser from the
    /// role.
    @AppStorage private var query: String
    @AppStorage private var searchesContents: Bool
    @AppStorage private var finderFocusRequest: Int
    @AppStorage private var editorFileRequest: Int
    @AppStorage private var editorFilePath: String
    @AppStorage private var editorFileLine: Int
    @AppStorage private var editorFileWorktree: String

    @FocusState private var finderFocused: Bool

    private let worktreePath: String
    private let service: SessionService
    private let role: Role
    private let waitingEdit: ExternalEdit?

    /// Sends the open file to the other slot; absent when the other
    /// slot cannot take one right now.
    private let onMoveFile: ((_ file: String, _ line: Int?) -> Void)?

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
            move: paneMove(for: result),
        ) {
            target = nil
            editorFilePath = ""
        }
        .id(result.id)
    }

    /// The move-to-other-pane action for the open file, which clears
    /// this slot before handing the file over.
    private func paneMove(for result: Result) -> FileEditorView.PaneMove? {
        onMoveFile.map { move in
            // The closure stays a non-final argument: the formatter
            // rewrites a trailing one after a multiline call.
            FileEditorView.PaneMove(
                action: {
                    target = nil
                    editorFilePath = ""
                    move(result.file, result.line)
                },
                icon: role == .centre ? "arrow.right.square" : "arrow.left.square",
                help: role == .centre
                    ? "Save and move this file to the utility pane's editor"
                    : "Save and move this file to the centre editor",
            )
        }
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
