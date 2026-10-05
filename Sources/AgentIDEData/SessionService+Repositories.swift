import AgentIDEDomain
import Foundation

/// The repository finder's service surface: what the user can reach
/// on GitHub, and cloning a pick into the shared workspace.
public extension SessionService {
    /// The user's login and organisations, for the repository
    /// finder's owner step. Empty when GitHub is unreachable.
    func organisations() async -> [String] {
        await (try? github.organisations(directory: paths.repositoriesDirectory)) ?? []
    }

    /// Every repository under one owner on GitHub. Empty when GitHub
    /// is unreachable.
    func repositories(owner: String) async -> [String] {
        await (try? github.repositories(owner: owner, directory: paths.repositoriesDirectory)) ?? []
    }

    /// Clones a repository into the shared workspace when it is not
    /// already there, returning it either way. A checkout is named
    /// after the repository unless another owner's clone holds that
    /// name, then `<owner>-<name>`, so a fork and its upstream can
    /// sit side by side.
    func cloneRepository(fullName: String) async throws -> Repository {
        for candidate in [
            fullName.split(separator: "/").last.map(String.init) ?? fullName,
            fullName.replacing("/", with: "-"),
        ] {
            let path = paths.repositoriesDirectory + "/" + candidate
            guard FileManager.default.fileExists(atPath: path) else {
                try await github.clone(fullName: fullName, into: paths.repositoriesDirectory, as: candidate)
                return Repository(name: candidate, path: path, fullName: fullName)
            }

            let checkout = await Repository(
                name: candidate,
                path: path,
                fullName: git.fullName(of: Repository(name: candidate, path: path)),
            )
            if checkout.isNamed(fullName) {
                return checkout
            }
        }
        throw SessionServiceError("Every checkout name for \(fullName) is taken by another repository.")
    }
}
