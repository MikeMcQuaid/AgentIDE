import AgentIDEData
import AgentIDEDomain
import Foundation
@testable import PRFeature

/// The shared fixtures behind the pull request model tests, split
/// from the test body for length.
extension PullRequestsModelTests {
    /// A model against a throwaway store whose every fetch and
    /// service seam is replaced; nothing real is reached by these
    /// tests.
    func makeModel(
        items: [WorktreeItem] = [],
        metadataFile: String? = nil,
    ) -> PullRequestsModel {
        let model = makeBareModel(items: items, metadataFile: metadataFile)
        model.fetchList = { _, _ in [] }
        model.fetchSummary = { _ in nil }
        model.fetchHasMergeQueue = { false }
        model.fetchThreads = { _ in [] }
        model.performCreate = { _, _, _ in "" }
        model.fetchTemplate = { _ in nil }
        model.fetchCommitMessages = { _, _ in [] }
        model.generateDescription = { _ in nil }
        model.fillTemplate = { _, _ in nil }
        model.performMergeChange = { _ in
            // Succeeds without side effects.
        }
        model.performPostMergeCleanup = { _, _ in
            // Succeeds without side effects.
        }
        model.fetchCurrentBranch = { _ in nil }
        model.fetchRebaseNeed = { _ in .nothing }
        model.performPush = { _ in .origin }
        model.performRebase = { _ in
            // Succeeds without side effects.
        }
        model.checkTipSigned = { _ in true }
        return model
    }

    /// The model against a throwaway store, before any seams are
    /// replaced; split from `makeModel` for function length.
    private func makeBareModel(items: [WorktreeItem], metadataFile: String?) -> PullRequestsModel {
        let runner = FoundationProcessRunner()
        let base = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("agentide-prmodel-" + UUID().uuidString, isDirectory: true)
            .path
        let paths = WorkspacePaths(
            hostUser: "test",
            sharedWorkspace: base + "/shared",
            sandboxHome: base + "/home",
            metadataFile: metadataFile ?? base + "/state.json",
        )
        let service = SessionService(
            paths: paths,
            git: GitClient(runner: runner),
            herdr: HerdrClient(
                runner: runner,
                launcher: SandvaultLauncher(hostUser: "test"),
                isInsideSandbox: true,
                configHome: base + "/herdr",
            ),
            github: GitHubClient(runner: runner),
            transcripts: TranscriptReader(),
            spool: EventSpool(directory: paths.eventsDirectory),
            store: MetadataStore(file: paths.metadataFile),
            runners: [],
        )
        return PullRequestsModel(
            repository: Repository(name: "repo", path: "/repo"),
            branch: "feature",
            worktreePath: nil,
            defaultBranch: "main",
            items: items,
            github: GitHubClient(runner: runner),
            service: service,
            store: MetadataStore(file: paths.metadataFile),
        )
    }

    func summary(
        _ number: Int,
        head: String,
        base: String = "main",
        state: String = "OPEN",
    ) -> PullRequestSummary {
        PullRequestSummary(
            number: number,
            title: "Title \(number)",
            url: "",
            headBranch: head,
            mergeable: "",
            reviewDecision: "",
            checks: "",
            baseBranch: base,
            state: state,
        )
    }

    func item(branch: String, ahead: Int?) -> WorktreeItem {
        WorktreeItem(
            worktree: Worktree(
                repositoryName: "repo",
                repositoryPath: "/repo",
                branch: branch,
                path: "/worktrees/" + branch,
            ),
            session: nil,
            isDirty: false,
            aheadOfUpstream: ahead,
            hasUnread: false,
        )
    }
}
