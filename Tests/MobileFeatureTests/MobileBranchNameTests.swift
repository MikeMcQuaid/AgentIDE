import Foundation
@testable import MobileFeature
import SanductorDomain
import Testing

struct MobileBranchNameTests {
    @Test(arguments: ["chore/eol-terraform", "literal%2Fbranch"])
    func `directory fallbacks decode once while Git branch names stay literal`(branch: String) throws {
        let directory = try "/worktrees/repo/" + #require(branch.addingPercentEncoding(
            withAllowedCharacters: .alphanumerics,
        ))
        let snapshot = try HerdrSnapshot.decode(Data(#"""
        {"result":{"snapshot":{
          "workspaces":[{"workspace_id":"w1","label":"sanductor--repo--work--claude"}],
          "panes":[{"workspace_id":"w1","pane_id":"w1:p1","cwd":"\#(directory)"}]
        }}}
        """#.utf8))
        #expect(MobileSession.sessions(in: snapshot).first?.branch == branch)
        let status = GitWorktreeStatus(porcelain: "# branch.head literal%2Fcurrent\0")
        #expect(MobileSession.sessions(in: snapshot, worktrees: [directory: status])
            .first?
            .branch == "literal%2Fcurrent")
        #expect(MobileSession.sessions(in: snapshot).first?.directory == directory)
    }
}
