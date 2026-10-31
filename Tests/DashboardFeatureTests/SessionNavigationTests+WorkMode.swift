@testable import DashboardFeature
import Foundation
import SanductorData
import SanductorDomain
import Testing

@MainActor
extension SessionNavigationTests {
    @Test
    func `work mode hides repositories and selection without dropping running state`() throws {
        let saved = AppSettings.workMode
        defer { AppSettings.workMode = saved }
        let fixture = Fixture()
        defer { try? FileManager.default.removeItem(atPath: fixture.root) }
        let model = fixture.model
        let original = try #require(model.groups.first)
        model.groups = [
            RepositoryGroup(
                repository: Repository(name: "repo", path: original.repository.path, fullName: "Work/repo"),
                items: original.items,
            ),
        ]
        model.selection = original.items.first
        var mode = WorkMode()
        mode.isEnabled = true
        mode.organisations = ["work"]
        mode.weekdays = []
        AppSettings.workMode = mode
        model.refreshWorkMode()
        #expect(model.visibleGroups.isEmpty)
        #expect(model.publishedSidebar.first?.isHidden == true)
        #expect(model.selection == nil)
        #expect(model.groups.first?.items.count == original.items.count)
        model.selection = original.items.first
        #expect(model.selection == nil)
        mode.isEnabled = false
        AppSettings.workMode = mode
        model.refreshWorkMode()
        #expect(model.visibleGroups == model.groups)
        #expect(model.publishedSidebar.first?.isHidden == false)
    }
}
