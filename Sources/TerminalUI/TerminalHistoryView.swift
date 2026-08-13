import SwiftUI

/// A native, selectable view over a tmux pane's scrollback, shown
/// over the live terminal: scrolling and copying behave like any Mac
/// text, with none of tmux's modal copy-mode.
struct TerminalHistoryView: View {
    // MARK: Internal

    let capture: @MainActor () async -> String
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if hasLoaded == false {
                ProgressView("Loading scrollback…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                text
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .task { await reload() }
    }

    // MARK: Private

    /// Enough history to review a long run without SwiftUI laying
    /// out fifty thousand lines of text.
    private static let lineLimit = 2_000

    private static let padding: CGFloat = 6

    @State private var content = ""
    @State private var truncated = false
    @State private var hasLoaded = false

    private var header: some View {
        HStack(spacing: Self.padding) {
            Text("Scrollback").font(.subheadline.weight(.semibold))
            if truncated {
                Text("last \(Self.lineLimit) lines")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Refresh") { Task { await reload() } }
                .controlSize(.small)
                .hoverHelp("Capture the pane again; the live session keeps running underneath")
            Button("Done", action: onClose)
                .controlSize(.small)
                .keyboardShortcut(.cancelAction)
                .hoverHelp("Back to the live terminal; Escape works too")
        }
        .padding(Self.padding)
    }

    private var text: some View {
        ScrollViewReader { proxy in
            ScrollView([.vertical, .horizontal]) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(content.isEmpty ? "No scrollback yet." : content)
                        .font(CodeStyle.font)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(Self.padding)
                    Color.clear.frame(height: 1).id("bottom")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .hoverHelp("The pane's history as ordinary text: drag to select, Cmd-C to copy")
            .onAppear { proxy.scrollTo("bottom") }
        }
    }

    private func reload() async {
        let captured = await capture()
        var lines = captured.split(separator: "\n", omittingEmptySubsequences: false)
        // tmux pads the capture with trailing blank lines to the
        // pane height.
        while lines.last?.trimmingCharacters(in: .whitespaces).isEmpty == true {
            lines.removeLast()
        }
        truncated = lines.count > Self.lineLimit
        content = lines.suffix(Self.lineLimit).joined(separator: "\n")
        hasLoaded = true
    }
}
