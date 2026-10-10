import AgentIDEDomain

extension SessionService {
    func automationSummary(_ state: PullRequestAutomation, fresh: Bool) async throws -> PullRequestSummary? {
        if state.localWorktreePath != nil {
            return await localAutofixSummary(state)
        }
        if fresh {
            return try await github.pullRequestSummary(
                repositoryPath: state.repositoryPath,
                number: state.number,
                requiredChecks: pullRequests.requiredChecksReader(repositoryPath: state.repositoryPath),
            )
        }
        return try await pullRequests.summary(repositoryPath: state.repositoryPath, number: state.number)
    }

    func automationThreads(_ state: PullRequestAutomation, fresh: Bool) async throws -> [ReviewThread] {
        if fresh {
            return try await github.reviewThreads(repositoryPath: state.repositoryPath, number: state.number)
        }
        let conversation = try await pullRequests.conversation(
            repositoryPath: state.repositoryPath, number: state.number, seededBody: "",
        )
        guard conversation.graphQLFailure == nil else {
            throw SessionServiceError("Waiting for GitHub review threads")
        }

        return conversation.threads
    }

    func automationWriters(_ state: PullRequestAutomation, threads: [ReviewThread], fresh: Bool) async -> Set<String> {
        guard await github.isPrivate(repositoryPath: state.repositoryPath, fresh: fresh) else {
            return []
        }

        var verified = Set<String>()
        let authors = Set(threads.flatMap(\.comments).filter { $0.authorType == "User" }.map(\.author))
        for author in authors where await github.hasWriteAccess(
            login: author, repositoryPath: state.repositoryPath, fresh: fresh,
        ) {
            verified.insert(author)
        }
        return verified
    }

    static func automationTarget(
        _ state: PullRequestAutomation,
        summary: PullRequestSummary,
        groups: [RepositoryGroup],
    ) -> AutofixDriver.Target? {
        guard let group = groups.first(where: { $0.repository.path == state.repositoryPath }),
              let defaultBranch = group.defaultBranch, summary.headBranch != defaultBranch,
              let item = group.items.first(where: { item in
                  item.worktree.branch == summary.headBranch
                      && (state.localWorktreePath == nil || item.worktree.path == state.localWorktreePath)
              }),
              let session = item.session, session.status == .running, session.agent != nil,
              session.paneID != nil, item.worktree.isHostDirectory == false
        else {
            return nil
        }

        return AutofixDriver.Target(
            worktree: item.worktree,
            session: session,
            allowsUncommitted: state.attempt == nil,
        )
    }
}
