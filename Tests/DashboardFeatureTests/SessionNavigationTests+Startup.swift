import AppKit
@testable import DashboardFeature
import Foundation
import Testing

extension SessionNavigationTests {
    @Test(arguments: [false, true])
    func `repositories open a prompt unless a saved selection exists`(restoring: Bool) async throws {
        _ = NSApplication.shared
        let fixture = Fixture()
        defer { fixture.close() }
        try FileManager.default.createDirectory(atPath: fixture.repository.path, withIntermediateDirectories: true)
        let restore = Fixture.overriding(["selectedWorktreePath": restoring ? fixture.repository.path : ""])
        defer { restore() }
        await fixture.model.refresh()
        #expect(fixture.model.showsNewSession == (restoring == false))
        #expect(fixture.model.showsRepositoryFinder == false)
        #expect(fixture.model.newSessionRepository == nil)
        if restoring {
            #expect(fixture.model.selection?.worktree.path == fixture.repository.path)
        }
    }

    @Test
    func `a first launch without repositories opens the finder once`() async {
        _ = NSApplication.shared
        let fixture = Fixture()
        defer { fixture.close() }
        fixture.model.groups = []
        await fixture.model.refresh()
        #expect(fixture.model.showsRepositoryFinder)
        fixture.model.showsRepositoryFinder = false
        await fixture.model.refresh()
        #expect(fixture.model.showsRepositoryFinder == false)
    }
}
