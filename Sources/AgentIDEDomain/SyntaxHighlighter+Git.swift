/// The files git hands an editor: a rebase todo list and the message
/// buffers. Both are read positionally rather than by the general
/// tokenizer, which would take an apostrophe for a string and colour
/// the rest of the line with it.
extension SyntaxHighlighter {
    /// Rebase todo lines are `<command> <commit> <subject>`, under a
    /// block of instructions git appends as comments. Highlighting
    /// the command and the commit is what makes such a list scannable
    /// while it is being rearranged.
    static func rebaseTokens(line: String) -> [SyntaxToken] {
        let indent = line.prefix { $0 == " " || $0 == "\t" }
        let body = line.dropFirst(indent.count)
        guard body.isEmpty == false else {
            return [SyntaxToken(kind: .plain, text: line)]
        }
        guard body.first != "#" else {
            return [SyntaxToken(kind: .comment, text: line)]
        }

        // Each piece keeps its own spacing, so the tokens still
        // reproduce the line exactly.
        let command = body.prefix { $0 != " " }
        let afterCommand = body.dropFirst(command.count)
        let spacing = afterCommand.prefix { $0 == " " }
        let target = afterCommand.dropFirst(spacing.count).prefix { $0 != " " }
        let subject = afterCommand.dropFirst(spacing.count + target.count)

        var tokens = indent.isEmpty ? [] : [SyntaxToken(kind: .plain, text: String(indent))]
        let isCommand = SyntaxLanguage.rebaseCommands.contains(String(command))
        tokens.append(SyntaxToken(kind: isCommand ? .keyword : .plain, text: String(command)))
        if spacing.isEmpty == false {
            tokens.append(SyntaxToken(kind: .plain, text: String(spacing)))
        }
        if target.isEmpty == false {
            tokens.append(SyntaxToken(kind: isCommit(target) ? .number : .plain, text: String(target)))
        }
        if subject.isEmpty == false {
            tokens.append(SyntaxToken(kind: .plain, text: String(subject)))
        }
        return merge(tokens)
    }

    /// Commit messages colour only the block git appends and strips,
    /// so what is left is what will be committed.
    static func messageTokens(line: String) -> [SyntaxToken] {
        line.drop { $0 == " " || $0 == "\t" }.first == "#"
            ? [SyntaxToken(kind: .comment, text: line)]
            : [SyntaxToken(kind: .plain, text: line)]
    }

    /// Whether a word reads as an abbreviated commit, which is what
    /// separates `pick a1b2c3d` from `label branch-name`.
    private static func isCommit(_ word: Substring) -> Bool {
        word.count >= commitPrefixLength && word.allSatisfy(\.isHexDigit)
    }

    /// The shortest abbreviated commit git will print.
    private static let commitPrefixLength = 4
}
