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

    /// Every branch and the commit it points at, as one string.
    /// Deriving a stack costs thirty processes; this costs one, and
    /// nothing about a stack can change without changing it.
    func refFingerprint(worktreePath: String) async -> String {
        let result = try? await git(
            ["for-each-ref", "--format=%(refname:short) %(objectname)", "refs/heads/"],
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
                aheadOfUpstream: Self.aheadOfUpstream(upstream: upstream, track: track),
                committedAt: Int(committed) ?? 0,
            )
        }
        return facts
    }

    /// The commits an upstream lacks, read from `upstream:track`:
    /// empty means level with it, `gone` means it was deleted, and
    /// no upstream at all means there is nothing to count against.
    static func aheadOfUpstream(upstream: String, track: String) -> Int? {
        guard upstream.isEmpty == false, track.contains("gone") == false else {
            return nil
        }
        guard let ahead = track
            .components(separatedBy: ", ")
            .first(where: { $0.hasPrefix("ahead ") })
        else {
            return 0
        }

        return Int(ahead.dropFirst("ahead ".count))
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

        let url = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let range = url.range(of: "github.com") else {
            return nil
        }

        let path = url[range.upperBound...].trimmingCharacters(in: CharacterSet(charactersIn: ":/"))
        let components = path.split(separator: "/").map(String.init)
        guard let owner = components.first, let repo = components.dropFirst().first else {
            return nil
        }

        let name = repo.hasSuffix(".git") ? String(repo.dropLast(".git".count)) : repo
        return owner + "/" + name
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
}
