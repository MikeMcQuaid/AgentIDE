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
            tmux: TmuxClient(
                runner: runner,
                launcher: SandvaultLauncher(hostUser: "test"),
                isInsideSandbox: true,
                socketDirectory: base + "/socket",
            ),
            github: GitHubClient(runner: runner),
            transcripts: TranscriptReader(),
            spool: EventSpool(directory: paths.eventsDirectory),
            store: MetadataStore(file: paths.metadataFile),
            runners: [],
        )
        let model = PullRequestsModel(
            repository: Repository(name: "repo", path: "/repo"),
            branch: "feature",
            items: items,
            github: GitHubClient(runner: runner),
            service: service,
            store: MetadataStore(file: paths.metadataFile),
        )
        model.fetchList = { _, _ in [] }
        model.fetchSummary = { _ in nil }
        model.fetchHasMergeQueue = { false }
        model.fetchRemediationContext = { _ in "" }
        model.fetchCurrentBranch = { _ in nil }
        model.fetchRebaseNeed = { _ in .nothing }
        model.fetchFullName = { nil }
        model.performPush = { _ in
            // Succeeds without side effects.
        }
        model.performRebase = { _ in
            // Succeeds without side effects.
        }
        model.checkTipSigned = { _ in true }
        return model
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
