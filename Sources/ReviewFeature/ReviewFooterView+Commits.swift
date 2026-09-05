import SwiftUI
import TerminalUI

/// The commit listing under a multi-commit review, and the single
/// commit a click on it opens; split from the footer for length.
extension ReviewFooterView {
    /// Fills the subject and body from the diff, beside the field it
    /// fills rather than among the actions that use what it wrote.
    var draftButton: some View {
        BusyButton(
            "",
            busy: "",
            systemImage: "sparkles",
            accessibilityLabel: "Draft commit message",
            disabled: model.showsUncommitted == false
                || model.commitMessage.trimmingCharacters(in: .whitespaces).isEmpty == false,
        ) {
            // The model reports its own refusal to the messages
            // pane, which is where every other failure here lands.
            _ = await model.generateCommitMessage()
        }
        .hoverHelp(
            "Draft the commit message from the uncommitted diff with the on-device model; "
                + "only fills an empty message",
        )
    }

    /// The URL scheme a commit line links to; nothing opens it but
    /// this file's own handler.
    static var commitScheme: String {
        "agentide-commit"
    }

    /// The commit listing coloured like git log: hashes orange,
    /// subjects bold and the trailing ref decorations green, all in
    /// one attributed block so selection still spans lines.
    var styledCommits: AttributedString {
        var whole = AttributedString()
        for (index, line) in model.branchCommits.enumerated() {
            if index > 0 {
                whole += AttributedString("\n")
            }
            whole += Self.styledCommitLine(line)
        }
        return whole
    }

    /// Which commit is under review, and the way back to the list it
    /// was picked from.
    var singleCommitHeader: some View {
        HStack(spacing: Self.footerPadding) {
            Button("All commits", systemImage: "chevron.left") { show(commit: String?.none) }
                .buttonStyle(.plain)
                .hoverHelp("Back to every commit under review")
            Text("Commit " + (model.commitTarget ?? ""))
                .font(.headline.monospaced())
                .textSelection(.enabled)
            Spacer()
            Text("read-only")
                .font(.caption)
                .foregroundStyle(.secondary)
                .hoverHelp("Only the last commit can be amended or have its lines rejected")
        }
    }

    /// Reviews the clicked commit on its own. Any other kind of
    /// link is left to the system, though the listing carries none.
    func show(commit url: URL) -> OpenURLAction.Result {
        guard url.scheme == Self.commitScheme else {
            return .systemAction
        }

        show(commit: String(url.absoluteString.dropFirst(Self.commitScheme.count + 1)))
        return .handled
    }

    /// Reviews one commit, or the whole scope again when nil.
    func show(commit: String?) {
        model.commitTarget = commit
        Task { await model.reload() }
    }

    /// One commit line: its hash, subject and ref decorations, the
    /// whole line linking to that commit so clicking anywhere on it
    /// reviews it alone.
    private static func styledCommitLine(_ line: String) -> AttributedString {
        let hashEnd = line.firstIndex(of: " ") ?? line.endIndex
        var hash = AttributedString(String(line[..<hashEnd]))
        hash.foregroundColor = .orange
        let target = URL(string: commitScheme + ":" + String(line[..<hashEnd]))
        var rest = String(line[hashEnd...])
        var trailing = ""
        if rest.hasSuffix(")"), let open = rest.range(of: " (", options: .backwards) {
            trailing = String(rest[open.lowerBound...])
            rest = String(rest[..<open.lowerBound])
        }
        var subject = AttributedString(rest)
        subject.font = .caption.monospaced().weight(.semibold)
        // Named explicitly so the link the whole line carries cannot
        // paint the listing in accent colour.
        subject.foregroundColor = .primary
        var decorations = AttributedString(trailing)
        decorations.foregroundColor = .green
        var whole = hash + subject + decorations
        whole.link = target
        return whole
    }
}
