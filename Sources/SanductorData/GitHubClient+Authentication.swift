import SanductorDomain

extension GitHubClient {
    func runGitHub(_ arguments: [String], in directory: String?) async throws -> ProcessResult {
        try Task.checkCancellation()
        return try await PerformanceLog.time(
            .network,
            "gh " + arguments.prefix(Self.loggedWords).joined(separator: " "),
            context: directory ?? "",
        ) {
            try await runner.run(
                ["gh"] + arguments, workingDirectory: directory, environment: ["GH_PROMPT_DISABLED": "1"],
            )
        }
    }

    static func isReadOnly(_ arguments: [String]) -> Bool {
        if arguments.starts(with: ["api", "graphql"]) {
            let queries = arguments.filter { $0.hasPrefix("query=") }
            guard queries.count == 1, let query = queries.first?.dropFirst("query=".count),
                  arguments.contains(where: { argument in
                      ["--input", "--raw-field=", "--field=", "-fquery=", "-Fquery="]
                          .contains { argument.hasPrefix($0) }
                  }) == false
            else {
                return false
            }

            return (query.hasPrefix("query") || query.hasPrefix("{"))
                && query.contains("mutation") == false && query.contains("subscription") == false
        }
        if arguments.first == "api" {
            return arguments.contains { argument in
                ["-f", "-F", "-X"].contains { argument.hasPrefix($0) }
                    || ["--field", "--raw-field", "--input", "--method"]
                    .contains { argument == $0 || argument.hasPrefix($0 + "=") }
            } == false
        }
        return arguments.count > 1 && ["pr", "issue", "repo", "run"].contains(arguments[0])
            && ["view", "list", "checks", "diff"].contains(arguments[1])
    }
}
