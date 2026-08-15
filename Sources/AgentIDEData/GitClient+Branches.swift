import Foundation

/// Branch inspection and the repository-local exclude file, split
/// from the client body for length.
public extension GitClient {
    /// The branch actually checked out in a worktree, nil when
    /// detached or unreadable; agents sometimes switch away from the
    /// branch the worktree was created for. The full symbolic ref
    /// with the prefix stripped by hand, because shortening git-side
    /// (`--abbrev-ref`) answered `heads/main` whenever an agent left
    /// a stray ref named `main` elsewhere in the repository.
    func currentBranch(worktreePath: String) async -> String? {
        let name = await (try? git(["symbolic-ref", "HEAD"], in: worktreePath, allowFailure: true))
            .flatMap { $0.succeeded ? $0.standardOutput : nil }?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = "refs/heads/"
        guard let name, name.hasPrefix(prefix) else {
            return nil
        }

        return String(name.dropFirst(prefix.count))
    }

    /// Whether a commit carries a verifying GPG signature: good, or
    /// good from a key git does not trust. Unsigned, bad and
    /// unverifiable signatures all fail, keeping the push gate shut
    /// when in doubt.
    func isCommitSigned(worktreePath: String, ref: String = "HEAD") async -> Bool {
        let state = try? await git(["log", "-1", "--format=%G?", ref], in: worktreePath)
            .standardOutput
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Self.signedStates.contains(state ?? "")
    }

    /// Whether every commit in a range carries a verifying
    /// signature; an empty range counts as signed and an unreadable
    /// one does not.
    func allCommitsSigned(worktreePath: String, range: String) async -> Bool {
        guard let output = try? await git(["log", "--format=%G?", range], in: worktreePath)
            .standardOutput
        else {
            return false
        }

        return output.split(separator: "\n").allSatisfy { Self.signedStates.contains(String($0)) }
    }

    /// Whether origin already carries the branch, after a fetch.
    func remoteBranchExists(worktreePath: String, branch: String) async -> Bool {
        let result = try? await git(
            ["rev-parse", "--verify", "--quiet", "refs/remotes/origin/" + branch],
            in: worktreePath,
            allowFailure: true,
        )
        return result?.succeeded ?? false
    }

    /// How many commits a range spans, nil when unreadable.
    func commitCount(worktreePath: String, range: String) async -> Int? {
        let result = try? await git(["rev-list", "--count", range], in: worktreePath, allowFailure: true)
        guard let result, result.succeeded else {
            return nil
        }

        return Int(result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// The branch's full commit messages beyond the base ref,
    /// oldest first, for drafting pull request descriptions.
    func commitMessages(worktreePath: String, baseRef: String) async -> [String] {
        let result = try? await git(
            ["log", "--reverse", "--format=%B%x1e", baseRef + "..HEAD"],
            in: worktreePath,
            allowFailure: true,
        )
        return (result?.standardOutput ?? "")
            .split(separator: "\u{1e}")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
    }

    /// The branch's commits beyond the base ref, newest first, one
    /// line each.
    func branchCommits(worktreePath: String, baseRef: String) async -> [String] {
        let result = try? await git(
            ["log", "--format=%h %s%d", baseRef + "..HEAD"],
            in: worktreePath,
            allowFailure: true,
        )
        var lines = (result?.standardOutput ?? "").split(separator: "\n").map(String.init)
        // The base commit anchors the list: its ref decorations name
        // where the branch forks from the local and remote log.
        // Plain local branches pointing there are already merged, so
        // only the default and remote names survive the filter.
        let base = try? await git(
            ["log", "-1", "--format=%h %s%d", baseRef],
            in: worktreePath,
            allowFailure: true,
        )
        if let line = base?.standardOutput.split(separator: "\n").first {
            lines.append(Self.filteredBaseDecorations(String(line)))
        }
        return lines
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

    /// The `%G?` states that count as signed: a good signature, or a
    /// good one from an untrusted key.
    private static var signedStates: Set<String> {
        ["G", "U"]
    }
}
