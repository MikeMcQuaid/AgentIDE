@testable import PRFeature
import SanductorData
import SanductorDomain
import Testing

extension PullRequestsModelTests {
    @Test(arguments: ["untouched", "whitespace", "title", "body", "cleared"])
    func `revisiting an unopened entry refreshes only unedited commit defaults`(edit: String) async {
        let model = makeModel(items: [item(branch: "feature", ahead: 1)])
        model.stacking.facts = { _ in
            StackFacts(stack: BranchStack(base: "main", branches: ["lower", "feature"], checkedOut: "feature"))
        }
        model.fetchCommitMessages = { _, range in
            range == "origin/HEAD..lower" ? ["Old title\n\nOld body."] : ["Upper title\n\nUpper body."]
        }
        await model.reload()
        switch edit {
        case "whitespace":
            model.prTitle = " Old  title\t"
            model.prBody = "\nOld\t body.\n"

        case "title":
            model.prTitle = "My title"

        case "body":
            model.prBody = "My body."

        case "cleared":
            model.prTitle = ""
            model.prBody = ""

        default:
            break
        }
        let savedTitle = model.prTitle
        let savedBody = model.prBody
        await model.show(branch: "feature")?.value
        #expect(model.prTitle == "Upper title")
        model.fetchCommitMessages = { _, _ in ["New title\n\nNew body."] }
        await model.show(branch: "lower")?.value

        let refreshes = edit == "untouched" || edit == "whitespace"
        #expect(model.prTitle == (refreshes ? "New title" : savedTitle))
        #expect(model.prBody == (refreshes ? "New body." : savedBody))
    }

    @Test(arguments: [false, true])
    func `a late commit description cannot replace another branch or new edits`(switchBranch: Bool) async throws {
        let model = makeModel(items: [item(branch: "feature", ahead: 1)])
        let worktree = try #require(model.branchItem?.worktree)
        model.fetchCommitMessages = { _, _ in
            if switchBranch {
                model.stacking.selected = "another"
            } else {
                model.prTitle = "Keep this title"
            }
            return ["Old title\n\nOld body"]
        }

        await model.prefillFromSingleCommit(worktree)

        #expect(model.prTitle == (switchBranch ? "" : "Keep this title"))
        #expect(model.prBody.isEmpty)
    }

    @Test
    func `an opened pull request is never automatically filled from commits`() async throws {
        let model = makeModel(items: [item(branch: "feature", ahead: 0)])
        let worktree = try #require(model.branchItem?.worktree)
        model.pullRequests.rememberListing(
            repositoryPath: model.repository.path,
            scope: .branch("feature"),
            summaries: [summary(1, head: "feature")],
        )
        model.fetchCommitMessages = { _, _ in ["New title\n\nNew body"] }

        await model.prefillFromSingleCommit(worktree)

        #expect(model.prTitle.isEmpty)
        #expect(model.prBody.isEmpty)
    }

    @Test
    func `saved defaults survive reopening and reset resumes automatic refresh`() async throws {
        let model = makeModel(items: [item(branch: "feature", ahead: 1)])
        model.fetchCommitMessages = { _, _ in ["Original\n\nOriginal body"] }
        await model.reload()
        model.prTemplate = "- [x] Tested"
        model.prLabels = ["ci"]
        let key = try #require(model.draftKey)
        let saved = try #require(model.store.load().pullRequestDrafts[key])
        let reopened = makeModel(items: [item(branch: "feature", ahead: 1)])
        reopened.store.update { $0.pullRequestDrafts[key] = saved }
        reopened.fetchCommitMessages = { _, _ in ["Amended\n\nAmended body"] }

        await reopened.reload()

        #expect(reopened.prTitle == "Amended")
        #expect(reopened.prBody == "Amended body")
        #expect(reopened.prTemplate == "- [x] Tested")
        #expect(reopened.prLabels == ["ci"])
        reopened.prTitle = "Edited"
        await reopened.resetToCommits()
        reopened.fetchCommitMessages = { _, _ in ["Amended again\n\nNewest body"] }
        await reopened.reload()
        #expect(reopened.prTitle == "Amended again")
        #expect(reopened.prBody == "Newest body")
    }

    @Test
    func `an explicit reset can update an opened pull request's edit form`() async throws {
        let model = makeModel(items: [item(branch: "feature", ahead: 0)])
        let worktree = try #require(model.branchItem?.worktree)
        model.selected = summary(1, head: "feature", body: "Opened body")
        model.beginEditing()
        model.fetchCommitMessages = { _, _ in ["Latest title\n\nLatest body"] }

        await model.resetToCommits()

        #expect(model.prTitle == "Latest title")
        #expect(model.prBody == "Latest body")
        model.fetchCommitMessages = { _, _ in ["Newer title\n\nNewer body"] }
        await model.prefillFromSingleCommit(worktree)
        #expect(model.prTitle == "Latest title")
        #expect(model.prBody == "Latest body")
    }
}
