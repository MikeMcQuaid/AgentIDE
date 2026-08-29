import AgentIDEDomain
import AppKit
@testable import DashboardFeature
import SwiftUI
import Testing

/// Renders real views to PNGs under `.build/shots` so the UI is
/// reviewable without a display.
@MainActor
struct SnapshotTests {
    // MARK: Internal

    @Test
    func `renders the worktree row to an inspectable image`() throws {
        let item = WorktreeItem(
            worktree: Worktree(
                repositoryName: "AgentIDE",
                repositoryPath: "/tmp/AgentIDE",
                branch: "agent/fix-crash",
                path: "/tmp/worktrees/1234/agent-fix-crash",
            ),
            session: AgentSession(
                name: "agentide--agentide--agent-fix-crash--claude",
                agent: .claudeCode,
                status: .running,
            ),
            isDirty: true,
            aheadOfUpstream: 2,
            hasUnread: true,
            aheadOfDefault: 3,
            behindDefault: 1,
        )
        let pullRequest = PullRequestSummary(
            number: 12,
            title: "Fix crash",
            url: "https://github.com/MikeMcQuaid/AgentIDE/pull/12",
            headBranch: "agent/fix-crash",
            mergeable: "MERGEABLE",
            reviewDecision: "",
            checks: "SUCCESS",
        )
        let width: CGFloat = 320
        let view = WorktreeRowView(
            item: item,
            pullRequest: pullRequest,
            standing: StackStanding(position: 1, height: 1),
        )
        .frame(width: width)
        .padding()

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try #require(renderer.cgImage)
        #expect(image.width > 0)

        try Self.write(image, name: "worktree-row")
    }

    // MARK: Private

    private static func write(_ image: CGImage, name: String) throws {
        let directory = FileManager.default.currentDirectoryPath + "/.build/shots"
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let representation = NSBitmapImageRep(cgImage: image)
        let png = try #require(representation.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: directory + "/" + name + ".png"))
    }
}
