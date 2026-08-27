import Foundation

/// The two things about a repository that only a rename or a change
/// of default branch moves: its GitHub `owner/name` and the branch
/// merges are judged against. Both were read from git on every poll
/// of every row, and the name again before every conditional GitHub
/// request, which came to thousands of shell-outs an hour for two
/// answers that never changed.
///
/// The name is remembered against the modification date of the file
/// the remote lives in, so repointing a remote is seen at once for
/// the cost of one stat rather than a `git remote` for every row.
/// The default branch has no such file to watch and is remembered
/// until a fetch, which is when the app itself could move it.
actor RepositoryFacts {
    // MARK: Internal

    /// An answer already read, which may be that there is none;
    /// distinct from never having asked.
    struct Answer {
        let value: String?
    }

    static let shared: RepositoryFacts = .init()

    /// The remembered name, unless the file it was read against has
    /// been written since.
    func name(of repositoryPath: String, at modified: Date?) -> Answer? {
        guard let modified, let stamped = names[repositoryPath], stamped.modified == modified else {
            return nil
        }

        return Answer(value: stamped.value)
    }

    func remember(name: String?, of repositoryPath: String, at modified: Date?) {
        guard let modified else {
            return
        }

        names[repositoryPath] = Stamped(value: name, modified: modified)
    }

    func baseRef(of repositoryPath: String) -> Answer? {
        baseRefs[repositoryPath]
    }

    func remember(baseRef: String?, of repositoryPath: String) {
        baseRefs[repositoryPath] = Answer(value: baseRef)
    }

    /// Forgets a path's default branch, for a fetch that may have
    /// moved it.
    func forget(_ repositoryPath: String) {
        baseRefs[repositoryPath] = nil
    }

    // MARK: Private

    /// An answer and the moment the file it was read from carried.
    private struct Stamped {
        let value: String?
        let modified: Date
    }

    private var names: [String: Stamped] = [:]
    private var baseRefs: [String: Answer] = [:]
}
