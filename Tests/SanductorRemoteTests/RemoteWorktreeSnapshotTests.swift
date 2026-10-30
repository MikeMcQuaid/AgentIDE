import Foundation
import SanductorDomain
@testable import SanductorRemote
import Testing

struct RemoteWorktreeSnapshotTests {
    @Test
    func `compact rows preserve request order and unknown values`() throws {
        let statuses = RemoteHerdr.parseWorktreeStatuses(
            "\nmain\t0\t0\t0\n\t\t\t1\nfeature\t4\t2\t1\n",
            paths: ["/missing", "/main", "/detached", "/feature"],
        )
        #expect(statuses["/missing"] == nil)
        let main = try #require(statuses["/main"])
        #expect(main.branch == "main")
        #expect(main.aheadOfUpstream == 0)
        #expect(main.behindUpstream == 0)
        #expect(main.summary.isEmpty)
        let detached = try #require(statuses["/detached"])
        #expect(detached.branch == nil)
        #expect(detached.aheadOfUpstream == nil)
        #expect(detached.behindUpstream == nil)
        #expect(detached.summary == "±")
        #expect(statuses["/feature"]?.summary == "↑4 ↓2 ±")
    }

    @Test
    func `panes share a Git reading and refresh it when activity changes`() throws {
        let data = #"""
        {"result":{"snapshot":{
          "workspaces":[{"workspace_id":"w1","label":"sanductor--repo--branch--claude"},
                        {"workspace_id":"w2","label":"unrelated"}],
          "panes":[{"workspace_id":"w1","pane_id":"w1:p1","agent_status":"working","cwd":"/repo"},
                   {"workspace_id":"w1","pane_id":"w1:p2","cwd":"/repo","foreground_cwd":""},
                   {"workspace_id":"w2","pane_id":"w2:p1","cwd":"/foreign"}]
        }}}
        """#
        let versions = try RemoteHerdr.worktreeVersions(in: HerdrSnapshot.decode(Data(data.utf8)))
        #expect(versions.count == 1)
        #expect(versions["/repo"]?.count == 2)
        let changed = data.replacing("working", with: "done")
        #expect(try RemoteHerdr.worktreeVersions(in: HerdrSnapshot.decode(Data(changed.utf8))) != versions)
    }
}
