import Foundation

/// Labels: the repository's own, and reading and changing a pull
/// request's, split from the client body for length.
public extension GitHubClient {
    /// The repository's labels by name, for the pickers; an
    /// unreadable answer is no labels rather than an error.
    func labels(repositoryPath: String) async -> [String] {
        let output = try? await gh(
            ["label", "list", "--json", "name", "--limit", "200", "--jq", ".[].name"],
            in: repositoryPath,
        ).standardOutput
        return Self.names(fromLines: output ?? "")
    }

    /// The labels on one pull request, by name.
    func pullRequestLabels(repositoryPath: String, number: Int) async -> [String] {
        let output = try? await gh(
            ["pr", "view", String(number), "--json", "labels", "--jq", ".labels[].name"],
            in: repositoryPath,
        ).standardOutput
        return Self.names(fromLines: output ?? "")
    }

    /// Adds and removes labels on a pull request in one edit.
    func editLabels(repositoryPath: String, number: Int, add: [String], remove: [String]) async throws {
        let arguments = ["pr", "edit", String(number)]
            + add.flatMap { ["--add-label", $0] }
            + remove.flatMap { ["--remove-label", $0] }
        try await gh(arguments, in: repositoryPath)
    }

    private static func names(fromLines output: String) -> [String] {
        output.split(separator: "\n").map(String.init).sorted()
    }
}
