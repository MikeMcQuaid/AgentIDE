import AppKit
@testable import PRFeature
import SanductorData
import SanductorDomain
import TerminalUI
import Testing

extension PullRequestsModelTests {
    @Test
    func `copying checks reads only finished failing jobs in a running workflow`() async throws {
        let completed = PullRequestCheck(
            name: "build",
            status: "COMPLETED",
            conclusion: "FAILURE",
            requirement: .required,
            link: "https://github.com/o/r/actions/runs/1/job/2",
        )
        let running = PullRequestCheck(
            name: "tests",
            status: "IN_PROGRESS",
            conclusion: "FAILURE",
            requirement: .required,
            link: "https://github.com/o/r/actions/runs/1/job/3",
        )
        let optional = PullRequestCheck(
            name: "optional",
            status: "COMPLETED",
            conclusion: "FAILURE",
            requirement: .optional,
            link: "https://github.com/o/r/actions/runs/1/job/4",
        )
        let summary = PullRequestSummary(
            number: 1,
            title: "Work",
            url: "https://github.com/o/r/pull/1",
            headBranch: "feature",
            mergeable: "",
            reviewDecision: "",
            checks: "FAILURE",
            failingCheckLinks: [completed.link, running.link],
            checkDetails: [completed, running, optional],
        )
        let model = makeModel()
        model.fetchFailedRunLog = { _ in "UNRELATED OPTIONAL FAILURE" }
        model.fetchCheckLog = { jobID in
            #expect(jobID == 2)
            return "required failure"
        }
        #expect(PullRequestsModel.copyableFailingChecks(in: summary) == [completed])
        #expect(try await model.failingLogs(for: summary) == "## build\nrequired failure")
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("stale", forType: .string)
        model.fetchCheckLog = { _ in
            #expect(pasteboard.string(forType: .string) == nil)
            return "required failure"
        }
        #expect(await model.copyFailingLogs(summary, pasteboard: pasteboard))
        #expect(pasteboard.string(forType: .string) == "## build\nrequired failure")
    }

    @Test(arguments: [1, 2])
    func `unfinished failing checks report their count and live log links`(count: Int) async throws {
        let checks = (1 ... count).map { job in
            PullRequestCheck(
                name: "Job " + String(job),
                status: "IN_PROGRESS",
                conclusion: "FAILURE",
                requirement: .required,
                link: "https://github.com/o/r/actions/runs/1/job/" + String(job),
            )
        }
        let summary = PullRequestSummary(
            number: 1,
            title: "Work",
            url: "https://github.com/o/r/pull/1",
            headBranch: "feature",
            mergeable: "",
            reviewDecision: "",
            checks: "FAILURE",
            failingCheckLinks: checks.map(\.link),
            checkDetails: checks,
        )
        let model = makeModel()
        model.fetchCheckLog = { _ in
            Issue.record("An unfinished job has no downloadable log")
            return ""
        }
        #expect(PullRequestsModel.copyableFailingChecks(in: summary).isEmpty)
        let error = try #require(await #expect(throws: GitHubClient.RunLogsUnavailable.self) {
            try await model.failingLogs(for: summary)
        })
        #expect(error.failedJobs == count)
        #expect(error.links == checks.map(\.link))
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("stale", forType: .string)
        #expect(await model.copyFailingLogs(summary, pasteboard: pasteboard) == false)
        #expect(pasteboard.string(forType: .string) == nil)
        let message = ErrorLog.shared.entries.last?.message ?? ""
        #expect(message.contains("only once the job has finished"))
        #expect(message.contains("no job in this run has failed yet") == false)
        #expect(checks.allSatisfy { message.contains($0.link) })
    }

    @Test
    func `optional copy scope persists per PR and cancellation without logs is normal`() async throws {
        let cancelled = PullRequestCheck(
            name: "cancelled",
            status: "COMPLETED",
            conclusion: "CANCELLED",
            requirement: .required,
            link: "https://github.com/o/r/actions/runs/1/job/2",
            startedAt: .now,
        )
        let optional = PullRequestCheck(
            name: "optional",
            status: "COMPLETED",
            conclusion: "FAILURE",
            requirement: .optional,
            link: "https://github.com/o/r/actions/runs/1/job/3",
        )
        let summary = PullRequestSummary(
            number: 1,
            title: "Work",
            url: "https://github.com/o/r/pull/1",
            headBranch: "feature",
            mergeable: "",
            reviewDecision: "",
            checks: "FAILURE",
            failingCheckLinks: [cancelled.link],
            checkDetails: [cancelled, optional],
        )
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        defer { try? FileManager.default.removeItem(atPath: root) }
        let metadata = root + "/state.json"
        let model = makeModel(metadataFile: metadata)
        model.fetchCheckLog = { jobID in
            if jobID == 2 {
                throw GitHubClient.JobLogUnavailable()
            }
            return "optional failure"
        }
        #expect(try await model.failingLogs(for: summary) == "Cancelled or skipped checks produced no logs.")
        model.setIncludesOptionalLogs(true, for: summary)
        #expect(model.includesOptionalLogs(for: summary))
        #expect(model.includesOptionalLogs(for: self.summary(2, head: "another")) == false)
        #expect(try await model.failingLogs(for: summary) == "## optional\noptional failure")
        #expect(makeModel(metadataFile: metadata).includesOptionalLogs(for: summary))
        model.setIncludesOptionalLogs(false, for: summary)
        model.fetchCheckLog = { _ in throw URLError(.notConnectedToInternet) }
        await #expect(throws: URLError.self) { try await model.failingLogs(for: summary) }
    }
}
