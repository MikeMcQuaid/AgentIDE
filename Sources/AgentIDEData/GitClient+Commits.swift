import Foundation

/// The commit listings the review pane shows under a diff, split
/// from the branch inspection for length.
public extension GitClient {
    /// The branch's commits beyond the base ref, newest first, one
    /// line each.
    func branchCommits(worktreePath: String, baseRef: String) async -> [String] {
        let result = try? await git(
            ["log", "--format=%h %s%d", baseRef + "..HEAD"],
            in: worktreePath,
            allowFailure: true,
        )
        let lines = (result?.standardOutput ?? "").split(separator: "\n").map(String.init)
        return await lines + baseLine(worktreePath: worktreePath, baseRef: baseRef)
    }

    /// The commits the upstream lacks by patch rather than by hash,
    /// newest first, one line each, over the decorated upstream
    /// row; see `unpushedCommits` for why hashes will not do.
    func unpushedCommitLines(worktreePath: String, upstreamRef: String, baseRef: String?) async -> [String] {
        let hashes = await unpushedCommits(worktreePath: worktreePath, upstreamRef: upstreamRef, baseRef: baseRef)
        var lines = [String]()
        if hashes.isEmpty == false {
            let result = try? await git(
                ["log", "--no-walk=unsorted", "--format=%h %s%d"] + hashes.reversed(),
                in: worktreePath,
                allowFailure: true,
            )
            lines = (result?.standardOutput ?? "").split(separator: "\n").map(String.init)
        }
        return await lines + baseLine(worktreePath: worktreePath, baseRef: upstreamRef)
    }

    /// The base commit's own line, which anchors a list: its ref
    /// decorations name where the branch forks from the local and
    /// remote log. Plain local branches pointing there are already
    /// merged, so only the default and remote names survive the
    /// filter. Empty when the base cannot be read.
    private func baseLine(worktreePath: String, baseRef: String) async -> [String] {
        let base = try? await git(
            ["log", "-1", "--format=%h %s%d", baseRef],
            in: worktreePath,
            allowFailure: true,
        )
        guard let line = base?.standardOutput.split(separator: "\n").first else {
            return []
        }

        return [Self.filteredBaseDecorations(String(line))]
    }

    /// Rewrites a decorated base log line, dropping local branch
    /// names other than the default: any branch pointing at the base
    /// is fully merged there, so only `origin/*`, `main`, `master`
    /// and `HEAD` arrows orient the reader.
    internal static func filteredBaseDecorations(_ line: String) -> String {
        // Decorations sit at the line's end, after the subject, so
        // the last parenthesis pair is theirs even when the subject
        // contains its own.
        guard let open = line.lastIndex(of: "("),
              let close = line[open...].firstIndex(of: ")"),
              line[line.index(after: close)...].isEmpty
        else {
            return line
        }

        let refs = line[line.index(after: open) ..< close]
            .components(separatedBy: ", ")
            .filter { ref in
                ref.hasPrefix("origin/") || ref == "main" || ref == "master" || ref.contains("HEAD")
                    || ref.hasPrefix("tag: ")
            }
        let decorations = refs.isEmpty ? "" : " (" + refs.joined(separator: ", ") + ")"
        // %d wraps decorations in " (…)", so the space before the
        // parenthesis goes with them.
        let head = line[..<open].hasSuffix(" ") ? String(line[..<open].dropLast()) : String(line[..<open])
        return head + decorations + String(line[line.index(after: close)...])
    }
}
