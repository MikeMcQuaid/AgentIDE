import Foundation

public extension GitHubClient {
    /// Unknown visibility never authorises human review automation.
    func isPrivate(repositoryPath: String, fresh: Bool = false) async -> Bool {
        guard let result = try? await gh(
            ["api", "repos/{owner}/{repo}"] + (fresh ? [] : ["--cache", "60s"]),
            in: repositoryPath,
        ), let repository = try? JSONDecoder().decode(RepositoryVisibility.self, from: Data(result.standardOutput.utf8))
        else {
            return false
        }

        return repository.isPrivate
    }

    /// Author association is not permission: unknown and failed reads stay ineligible.
    func hasWriteAccess(login: String, repositoryPath: String, fresh: Bool = true) async -> Bool {
        guard login.isEmpty == false,
              login.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" })
        else {
            return false
        }
        guard let result = try? await gh(
            ["api", "repos/{owner}/{repo}/collaborators/" + login + "/permission"]
                + (fresh ? [] : ["--cache", "60s"]),
            in: repositoryPath,
        ), let permission = try? JSONDecoder().decode(
            CollaboratorPermission.self,
            from: Data(result.standardOutput.utf8),
        )
        else {
            return false
        }

        return ["admin", "maintain", "write"].contains(permission.permission)
            || permission.user?.permissions?["push"] == true
    }
}

// MARK: - CollaboratorPermission

private struct CollaboratorPermission: Decodable {
    struct User: Decodable {
        // Nil when GitHub does not return detailed permissions.
        // swiftlint:disable:next discouraged_optional_collection
        let permissions: [String: Bool]?
    }

    let permission: String
    let user: User?
}

// MARK: - RepositoryVisibility

private struct RepositoryVisibility: Decodable {
    // MARK: Internal

    let isPrivate: Bool

    // MARK: Private

    private enum CodingKeys: String, CodingKey {
        case isPrivate = "private"
    }
}
