@testable import DashboardFeature
import Foundation
import SanductorDomain
import Testing

extension SessionNavigationTests {
    @Test
    func `phone sidebar publishes public owners and ordered worktrees only when changed`() throws {
        let fixture = Fixture()
        defer { fixture.close() }
        let original = try #require(fixture.model.groups.first?.items.first)
        let host = WorktreeItem(
            worktree: Worktree(
                repositoryName: "repo",
                repositoryPath: fixture.repository.path,
                branch: "Private directory",
                path: "/private/directory",
                isHostDirectory: true,
            ),
            session: nil,
            isDirty: false,
            aheadOfUpstream: nil,
            hasUnread: false,
        )
        let groups = [
            RepositoryGroup(
                repository: Repository(name: "repo", path: fixture.repository.path, fullName: "Homebrew/remote-name"),
                items: [original, host],
                defaultBranch: "main",
            ),
        ]
        fixture.model.groups = groups
        fixture.model.cacheSidebar(groups)
        let file = fixture.root + "/shared/sanductor/sidebar-sanductor-dev.json"
        #expect(try JSONDecoder().decode([SidebarRepository].self, from: Data(contentsOf: URL(filePath: file))) == [
            SidebarRepository(
                name: "repo",
                owner: "Homebrew",
                worktrees: [fixture.repository.path],
                entries: [
                    SidebarEntry(
                        target: SidebarTarget(original.worktree), status: .defaultBranch, activity: nil, block: nil,
                    ),
                ],
                fullName: "Homebrew/remote-name",
                defaultBranch: "main",
            ),
        ])
        #expect(FileManager.default.fileExists(
            atPath: fixture.root + "/shared/sanductor/sidebar-sanductor.json",
        ) == false)

        let timestamp = Date(timeIntervalSince1970: 1)
        try FileManager.default.setAttributes([.modificationDate: timestamp], ofItemAtPath: file)
        fixture.model.cacheSidebar(groups)
        #expect(try FileManager.default.attributesOfItem(atPath: file)[.modificationDate] as? Date == timestamp)

        fixture.model.cacheSidebar([])
        #expect(try JSONDecoder().decode([SidebarRepository].self, from: Data(contentsOf: URL(filePath: file))).isEmpty)
    }
}
