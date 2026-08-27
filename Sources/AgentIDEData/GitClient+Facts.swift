import AgentIDEDomain
import Foundation

/// The two facts a repository does not change while the app runs:
/// read once each, remembered by `RepositoryFacts` and forgotten on
/// a fetch. Split from the client body for length.
public extension GitClient {
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
