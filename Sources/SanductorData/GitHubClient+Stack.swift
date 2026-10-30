import Foundation

public extension GitHubClient {
    /// Creates or extends a GitHub stack without changing existing membership.
    /// Numbers arrive bottom first, which need not be numerical order.
    func linkStack(worktreePath: String, numbers: [Int]) async throws {
        guard Set(numbers).count == numbers.count else {
            throw SessionServiceError("A pull request cannot appear twice in a stack.")
        }
        guard numbers.count > 1 else {
            return
        }

        let headers = [
            "--header", "Accept: application/vnd.github+json",
            "--header", "X-GitHub-Api-Version: 2026-03-10",
        ]
        let path = "repos/{owner}/{repo}/stacks"
        var existing: GitHubStack?
        for number in numbers where existing?.pullRequests.contains(where: { $0.number == number }) != true {
            let result = try await gh(["api", path + "?pull_request=" + String(number)] + headers, in: worktreePath)
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            for stack in try decoder.decode([GitHubStack].self, from: Data(result.standardOutput.utf8))
                where stack.open
            {
                guard existing == nil || existing?.number == stack.number else {
                    throw SessionServiceError("These pull requests belong to different GitHub stacks.")
                }

                existing = stack
            }
        }

        var missing = numbers
        var destination = path
        if let existing {
            let members = existing.pullRequests.map(\.number)
            let positions = numbers.compactMap { members.firstIndex(of: $0) }
            guard positions == positions.sorted() else {
                throw SessionServiceError("The pull request order differs from the existing GitHub stack.")
            }

            missing = numbers.filter { members.contains($0) == false }
            guard missing.isEmpty == false else {
                return
            }
            guard let top = members.last, let index = numbers.firstIndex(of: top),
                  Array(numbers.suffix(from: index + 1)) == missing,
                  numbers.prefix(through: index).allSatisfy({ members.contains($0) })
            else {
                throw SessionServiceError("New pull requests must follow the top of the existing GitHub stack.")
            }

            destination += "/" + String(existing.number) + "/add"
        }
        try await gh(
            ["api", "--method", "POST"] + headers + [destination]
                + missing.flatMap { ["--field", "pull_requests[]=" + String($0)] },
            in: worktreePath,
        )
    }
}

// MARK: - GitHubStack

private struct GitHubStack: Decodable {
    struct PullRequest: Decodable {
        let number: Int
    }

    let number: Int
    let open: Bool
    let pullRequests: [PullRequest]
}
