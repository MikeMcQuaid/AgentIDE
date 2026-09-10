import AgentIDEData
import AgentIDEDomain
import TerminalUI

/// The explicit fetches a repository row offers. Split from the
/// model body for length.
public extension DashboardModel {
    /// Fetches the item's repository and refreshes, saying so when
    /// the default branch moved and the checkout followed it.
    func fetch(item: WorktreeItem) async {
        let repository = Repository(name: item.worktree.repositoryName, path: item.worktree.repositoryPath)
        do {
            let move = try await service.fetch(repository: repository)
            ErrorLog.shared.note("fetched" + Self.moved(move), about: repository.name)
            await refresh()
        } catch {
            ErrorLog.shared.report(error.localizedDescription)
        }
    }

    /// Fetches origin and hard-resets the main checkout to its
    /// default branch, following a moved default branch first, then
    /// refreshes.
    func fetchAndReset(item: WorktreeItem) async {
        let repository = Repository(name: item.worktree.repositoryName, path: item.worktree.repositoryPath)
        do {
            let (ref, move) = try await service.fetchAndReset(repository: repository)
            ErrorLog.shared.note("reset the checkout to `" + ref + "`" + Self.moved(move), about: repository.name)
            await refresh()
        } catch {
            ErrorLog.shared.report(error.localizedDescription)
        }
    }

    /// What a note says about a default branch that moved, or
    /// nothing when it did not.
    private static func moved(_ move: GitClient.DefaultBranchMove?) -> String {
        guard let move else {
            return ""
        }

        return "; the default branch moved from `" + move.previous + "` to `" + move.current
            + "`, and the checkout followed it"
    }
}
