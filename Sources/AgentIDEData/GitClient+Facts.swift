import AgentIDEDomain
import Foundation

// MARK: - BranchFacts

/// What the sidebar shows about one branch: how far it stands from
/// the default branch and from its own upstream, and when it last
/// took a commit.
public struct BranchFacts: Sendable {
    public let ahead: Int?
    public let behind: Int?

    /// Commits the upstream lacks, nil when there is no upstream or
    /// it has gone.
    public let aheadOfUpstream: Int?

    /// Commits the upstream has that this branch lacks, nil the
    /// same way: what says a branch is behind what was pushed.
    public let behindUpstream: Int?
    public let committedAt: Int
}

/// The two facts a repository does not change while the app runs:
/// read once each and remembered: see `RepositoryFacts`. Split from
/// the client body for length.
public extension GitClient {
    /// Every branch of a repository, with the counts and the date
    /// the sidebar shows. One process for a repository rather than
    /// three per worktree: `rev-list` twice and `log -1` for each of
    /// twenty-five worktrees, every poll, was most of the git time
    /// the app spent, and git computes all of it here internally.
    /// Only a worktree on a detached head falls back to asking about
    /// itself.
    func branchFacts(repositoryPath: String, baseRef: String?) async -> [String: BranchFacts] {
        let counts = baseRef.map { "%(ahead-behind:" + $0 + ")" } ?? ""
        let format = [
            "%(refname:short)",
            "%(upstream)",
            "%(upstream:track,nobracket)",
            counts,
            "%(committerdate:unix)",
        ].joined(separator: "\t")
        let result = try? await git(
            ["for-each-ref", "--format=" + format, "refs/heads/"],
            in: repositoryPath,
            allowFailure: true,
        )
        guard let result, result.succeeded else {
            return [:]
        }

        return Self.branchFacts(fromForEachRef: result.standardOutput)
    }

    /// Every branch and remote-tracking ref with the commit it
    /// points at, as one string. Deriving a stack costs thirty
    /// processes; this costs one, and nothing a derivation reads can
    /// change without changing it. The remotes are in it because the
    /// default branch is what every fork point is measured against:
    /// a fetch that moves it changes what a stack is while every
    /// local branch stays exactly where it was.
    func refFingerprint(worktreePath: String) async -> String {
        let result = try? await git(
            [
                "for-each-ref",
                "--format=%(refname) %(objectname)",
                "refs/heads/",
                "refs/remotes/",
            ],
            in: worktreePath,
            allowFailure: true,
        )
        return result?.standardOutput ?? ""
    }

    /// Parses what `for-each-ref` printed; separated for tests.
    static func branchFacts(fromForEachRef output: String) -> [String: BranchFacts] {
        var facts = [String: BranchFacts]()
        for line in output.split(separator: "\n") {
            var fields = line.components(separatedBy: "\t").makeIterator()
            guard let name = fields.next(), name.isEmpty == false,
                  let upstream = fields.next(), let track = fields.next(),
                  let counts = fields.next(), let committed = fields.next()
            else {
                continue
            }

            let distance = counts.split(separator: " ").compactMap { Int($0) }
            facts[name] = BranchFacts(
                ahead: distance.first,
                behind: distance.dropFirst().first,
                aheadOfUpstream: Self.upstreamCount("ahead", upstream: upstream, track: track),
                behindUpstream: Self.upstreamCount("behind", upstream: upstream, track: track),
                committedAt: Int(committed) ?? 0,
            )
        }
        return facts
    }

    /// One side of a branch's distance from its upstream, read from
    /// `upstream:track` (`ahead 2, behind 1`): empty means level
    /// with it, `gone` means it was deleted, and no upstream at all
    /// means there is nothing to count against.
    static func upstreamCount(_ side: String, upstream: String, track: String) -> Int? {
        guard upstream.isEmpty == false, track.contains("gone") == false else {
            return nil
        }
        guard let count = track
            .components(separatedBy: ", ")
            .first(where: { $0.hasPrefix(side + " ") })
        else {
            return 0
        }

        return Int(count.dropFirst(side.count + 1))
    }

    /// The repository's GitHub `owner/name`, parsed from the origin
    /// remote, nil for non-GitHub or remoteless repositories.
    func fullName(of repository: Repository) async -> String? {
        let modified = Self.configModified(at: repository.path)
        if let known = await RepositoryFacts.shared.name(of: repository.path, at: modified) {
            return known.value
        }

        let name = await readFullName(of: repository)
        await RepositoryFacts.shared.remember(name: name, of: repository.path, at: modified)
        return name
    }

    /// The base ref merges are judged against: the origin's default
    /// branch when known, otherwise a local main or master.
    func defaultBaseRef(of repository: Repository) async -> String? {
        if let known = await RepositoryFacts.shared.baseRef(of: repository.path) {
            return known.value
        }

        let ref = await readDefaultBaseRef(of: repository)
        await RepositoryFacts.shared.remember(baseRef: ref, of: repository.path)
        return ref
    }

    // MARK: Private

    /// When the repository's config was last written, which is what
    /// a remote's URL lives in; nil when there is no config to
    /// watch, and then nothing is remembered.
    private static func configModified(at repositoryPath: String) -> Date? {
        try? FileManager.default
            .attributesOfItem(atPath: repositoryPath + "/.git/config")[.modificationDate] as? Date
    }

    private func readFullName(of repository: Repository) async -> String? {
        let result = try? await git(
            ["remote", "get-url", "origin"],
            in: repository.path,
            allowFailure: true,
        )
        guard let result, result.succeeded else {
            return nil
        }

        return GitHubRemote.fullName(ofURL: result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func readDefaultBaseRef(of repository: Repository) async -> String? {
        let head = try? await git(
            ["symbolic-ref", "--short", "refs/remotes/origin/HEAD"],
            in: repository.path,
            allowFailure: true,
        )
        if let head, head.succeeded {
            return head.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        for candidate in ["main", "master"] where await branchExists(repository: repository, branch: candidate) {
            return candidate
        }
        return nil
    }

    /// Whether a ref's commit was ever this branch's own tip, read
    /// from the branch's reflog: how an amend's stale remote twin
    /// (once the tip here) is told from commits pushed elsewhere
    /// that this checkout has never seen.
    func refWasBranchTip(worktreePath: String, branch: String, ref: String) async -> Bool {
        guard
            let tip = try? await git(["rev-parse", ref], in: worktreePath)
            .standardOutput
            .trimmingCharacters(in: .whitespacesAndNewlines),
            let log = try? await git(["reflog", "show", "--format=%H", branch], in: worktreePath)
            .standardOutput
        else {
            return false
        }

        return log.split(separator: "\n").contains(Substring(tip))
    }

    /// The checkout that owns a linked worktree, read from its
    /// `.git` pointer (`gitdir: <owner>/.git/worktrees/<name>`);
    /// nil for a checkout of its own or an unreadable pointer.
    static func owningCheckout(of worktreePath: String) -> String? {
        let marker = "gitdir: "
        guard let pointer = try? String(contentsOfFile: worktreePath + "/.git", encoding: .utf8),
              pointer.hasPrefix(marker)
        else {
            return nil
        }

        let gitdir = pointer.dropFirst(marker.count).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let range = gitdir.range(of: "/.git/worktrees/") else {
            return nil
        }

        return String(gitdir[..<range.lowerBound])
    }

    /// The commit a ref names, nil when unreadable.
    func commitHash(of ref: String, worktreePath: String) async -> String? {
        await (try? git(["rev-parse", ref], in: worktreePath))?
            .standardOutput
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A leased push refused by git's integration check, retold in
    /// this app's terms. The app fetches constantly, so the bare
    /// lease always matches what was last fetched and this check is
    /// the one real protection: it refuses a remote tip that was
    /// never integrated locally. Git's own hint says to pull, which
    /// is not how this app works; the rebase integrates or sets
    /// aside, and the push after it carries the confirmation.
    internal func leaseRefusal(_ error: CommandError, branch: String, remote: String) -> CommandError {
        CommandError(command: error.command, result: ProcessResult(
            status: error.result.status,
            standardOutput: error.result.standardOutput,
            standardError: remote + "/" + branch + " was rewritten or moved from another checkout "
                + "and its tip was never integrated here, so the leased push refuses to overwrite "
                + "it. Fetch and Rebase, then Push: the rebase integrates the remote's commits, "
                + "or sets a conflicting version aside for Push to replace.",
        ))
    }
}
