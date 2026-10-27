import AgentIDEDomain
import Foundation

public extension SessionService {
    /// Validates even local edits through the same boundary as phone requests.
    func handleSidebarRequest(_ request: SidebarRequest, groups: [RepositoryGroup]) async -> SidebarResponse {
        do {
            switch request {
            case .refreshStatus:
                break

            case let .sources(repositoryPath):
                guard let repository = groups.first(where: { $0.repository.path == repositoryPath })?.repository else {
                    throw SessionServiceError("That repository is no longer listed.")
                }

                async let issues = github.openIssues(repositoryPath: repository.path)
                async let pulls = openPullRequests(repository: repository)
                return try await SidebarResponse(issues: issues, pullRequests: pulls)

            case let .save(block):
                try editWorkBlocks(saving: [block], removing: [], groups: groups)

            case let .remove(block):
                try editWorkBlocks(saving: [], removing: [block], groups: groups)
            }
            return SidebarResponse()
        } catch {
            return SidebarResponse(error: error.localizedDescription)
        }
    }

    /// Validates the whole selection before committing any change.
    func editWorkBlocks(saving blocks: [WorkBlock], removing previous: [WorkBlock], groups: [RepositoryGroup]) throws {
        for block in blocks {
            try validateBlock(block, groups: groups)
        }
        for block in previous {
            guard groups.flatMap(\.items).contains(where: { block.applies(to: SidebarTarget($0.worktree)) }) else {
                throw SessionServiceError("That worktree or branch is no longer listed.")
            }
        }
        try store.updatePersisting { metadata in
            // A late removal cannot clear a newer edit.
            metadata.workBlocks.removeAll { previous.contains($0) }
            for block in blocks {
                metadata.workBlocks.removeAll { $0.applies(to: block.target) }
                metadata.workBlocks.append(block)
            }
        }
    }

    /// Only positive evidence clears a dependency; unavailable GitHub stays blocked.
    func resolveWorkBlocks() async {
        let blocks = store.load().workBlocks
        var resolved = Set<WorkBlock>()
        for block in blocks where await dependencyFinished(block.dependency, since: block.createdAt) {
            resolved.insert(block)
        }
        guard resolved.isEmpty == false else {
            return
        }

        store.update { $0.workBlocks.removeAll { resolved.contains($0) } }
    }

    // MARK: Private

    private func validateBlock(_ block: WorkBlock, groups: [RepositoryGroup]) throws {
        let targets = groups.flatMap(\.items)
            .filter { $0.worktree.isHostDirectory == false }
            .map { SidebarTarget($0.worktree) }
        guard targets.contains(block.target) else {
            throw SessionServiceError("That worktree or branch has changed. Refresh and try again.")
        }
        guard block.dependency.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
              block.dependency.label.utf8.count <= WorkBlock.maximumNoteBytes
        else {
            throw SessionServiceError("Enter a blocker of at most 2,000 bytes.")
        }

        switch block.dependency {
        case .note:
            break

        case let .worktree(target):
            guard targets.contains(target), block.applies(to: target) == false else {
                throw SessionServiceError("Choose another listed worktree.")
            }

        case let .issue(repositoryPath, number, _),
             let .pullRequest(repositoryPath, number, _):
            guard number > 0, groups.contains(where: { $0.repository.path == repositoryPath }) else {
                throw SessionServiceError("Choose an issue or pull request in a listed repository.")
            }
        }
    }

    private func dependencyFinished(_ dependency: BlockDependency, since createdAt: Date) async -> Bool {
        do {
            switch dependency {
            case .note:
                return false

            case let .worktree(target):
                // An absent directory proves removal; a listing failure does not.
                do {
                    _ = try FileManager.default.attributesOfItem(atPath: target.path)
                } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
                    return true
                } catch {
                    return false
                }
                let summaries = try await PullRequestStore(github: github, store: store).listing(
                    repositoryPath: target.repositoryPath, scope: .branch(target.branch),
                )
                return summaries.first.map { summary in
                    ["CLOSED", "MERGED"].contains(summary.state)
                        && (summary.closedAt ?? .distantPast) >= createdAt
                } ?? false

            case let .issue(repositoryPath, number, _):
                return try await github.blockerState(
                    repositoryPath: repositoryPath, number: number, isPullRequest: false,
                )
                    == "CLOSED"

            case let .pullRequest(repositoryPath, number, _):
                let state = try await github.blockerState(
                    repositoryPath: repositoryPath, number: number, isPullRequest: true,
                )
                return ["CLOSED", "MERGED"].contains(state)
            }
        } catch {
            PerformanceLog.recordMessage("Reading blocker: " + error.localizedDescription, isError: false)
            return false
        }
    }
}
