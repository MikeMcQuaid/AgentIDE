import AgentIDEDomain
import SwiftUI
import TerminalUI

/// Editing the uncommitted diff's lines in place, and the numbering
/// that says which working line each one is. Split from the view
/// body for length; internal rather than private throughout, since
/// the formatter deletes a private declaration nothing in its own
/// file reads.
extension DiffFileView {
    /// One line's text: highlighted, and in the uncommitted scope
    /// live for every line the working file still holds, which is
    /// every line but a removed one. A click turns the line into a
    /// field; Enter or leaving it writes the file, Escape lets the
    /// typing go. Typed newlines become new lines.
    @ViewBuilder
    func lineView(_ entry: NumberedLine, key: EditKey) -> some View {
        if editing == key, let number = entry.new {
            TextField("", text: draftBinding(key, initial: entry.line.content), axis: .vertical)
                .font(CodeStyle.font)
                .textFieldStyle(.plain)
                .focused($editing, equals: key)
                .onSubmit { commit(key, line: number) }
                .onExitCommand {
                    model.lineDrafts[draftID(key)] = nil
                    editing = nil
                }
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text(lineText(entry.line))
                .font(CodeStyle.font)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    if model.showsUncommitted, entry.new != nil {
                        editing = key
                    }
                }
                .hoverHelp(model.showsUncommitted && entry.new != nil
                    ? "Click to edit this line in the file; a removed line is history"
                    : "")
        }
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
    /// follows redraws the row as the diff now has it.
    func commit(_ key: EditKey, line number: Int) {
        let id = draftID(key)
        guard let draft = model.lineDrafts[id] else {
            editing = nil
            return
        }

        model.lineDrafts[id] = nil
        editing = nil
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
}
