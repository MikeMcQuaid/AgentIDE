import AgentIDEDomain
import SwiftUI
import TerminalUI

/// Editing the uncommitted diff's lines in place, and the numbering
/// that says which working line each one is. Split from the view
/// body for length; internal rather than private throughout, since
/// the formatter deletes a private declaration nothing in its own
/// file reads.
extension DiffFileView {
    /// One line's text. In the uncommitted scope every line the
    /// working file still holds, which is every line but a removed
    /// one, is a field once the file is live: type into it and click
    /// away or press Enter to write the file, typed newlines becoming
    /// new lines. Before that, and everywhere else, the highlighted
    /// text; a click on an uncommitted line arms its file and lands
    /// in that line. Selection stays off those lines, since a
    /// selectable text swallows the click.
    @ViewBuilder
    func lineView(_ entry: NumberedLine, key: EditKey, arm: @escaping () -> Void, isLive: Bool) -> some View {
        if model.showsUncommitted, isLive, let number = entry.new {
            TextField("", text: draftBinding(key, initial: entry.line.content), axis: .vertical)
                .font(CodeStyle.font)
                .textFieldStyle(.plain)
                .focused($editing, equals: key)
                .onSubmit { commit(key, line: number) }
                .background(entry.line.kind == .addition ? Color.green.opacity(Self.changeOpacity) : .clear)
                .frame(maxWidth: .infinity, alignment: .leading)
                .hoverHelp("Edit the file here; Enter or clicking away writes it")
        } else if model.showsUncommitted, entry.new != nil {
            Text(lineText(entry.line))
                .font(CodeStyle.font)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    arm()
                    editing = key
                }
                .hoverHelp("Click to edit this file's lines here")
        } else {
            Text(lineText(entry.line))
                .font(CodeStyle.font)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Writes whatever was typed into the line just left; the
    /// focus change is what says it was left.
    func commitFocusLoss(from previous: EditKey?) {
        guard let previous, previous != editing,
              file.hunks.indices.contains(previous.hunkIndex)
        else {
            return
        }

        let lines = numbered(file.hunks[previous.hunkIndex])
        guard lines.indices.contains(previous.lineIndex), let number = lines[previous.lineIndex].new else {
            return
        }

        commit(previous, line: number)
    }

    /// The draft's key in the model: this file, hunk and line.
    func draftID(_ key: EditKey) -> String {
        file.path + "#" + String(key.hunkIndex) + "#" + String(key.lineIndex)
    }

    func draftBinding(_ key: EditKey, initial: String) -> Binding<String> {
        let id = draftID(key)
        return Binding(
            get: { model.lineDrafts[id] ?? initial },
            set: { model.lineDrafts[id] = $0 },
        )
    }

    /// Writes the typed line back when it changed; the reload that
    /// follows redraws the row as the diff now has it. Nothing typed
    /// is nothing to write.
    func commit(_ key: EditKey, line number: Int) {
        let id = draftID(key)
        guard let draft = model.lineDrafts[id] else {
            return
        }

        model.lineDrafts[id] = nil
        Task { await model.replaceLine(in: file, newLineNumber: number, with: draft) }
    }

    /// Joins each line with its old and new line numbers; deletions
    /// advance only the old side, additions only the new. The new
    /// number rides along on its own: it is the line the working
    /// file holds, which editing writes to.
    func numbered(_ hunk: DiffHunk) -> [NumberedLine] {
        var old = hunk.oldStart
        var new = hunk.newStart
        return hunk.lines.map { line in
            let numbers: String
            let held: Int?
            switch line.kind {
            case .context:
                numbers = Self.pad(old) + " " + Self.pad(new)
                held = new
                old += 1
                new += 1

            case .deletion:
                numbers = Self.pad(old) + " " + Self.pad(nil)
                held = nil
                old += 1

            case .addition:
                numbers = Self.pad(nil) + " " + Self.pad(new)
                held = new
                new += 1
            }
            return NumberedLine(line: line, numbers: numbers, new: held)
        }
    }

    /// A hunk's lines as the file holds them: the displayed text
    /// stands a space in for a blank line so its change colour has
    /// something to paint, and copying that would put a space where
    /// the file has nothing at all.
    static func copyText(of hunk: DiffHunk) -> String {
        hunk.lines.map(\.content).joined(separator: "\n")
    }
}
