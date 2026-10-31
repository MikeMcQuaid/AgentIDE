@testable import DashboardFeature
import Foundation
import SanductorDomain
import Synchronization
import Testing

@MainActor
extension SessionNavigationTests {
    @Test
    func `repository choices use the loaded sidebar without touching the filesystem`() {
        let fixture = Fixture()
        defer { try? FileManager.default.removeItem(atPath: fixture.root) }
        let model = fixture.model
        #expect(FileManager.default.fileExists(atPath: fixture.repository.path) == false)
        #expect(model.repositories == [fixture.repository])
        model.groups = []
        #expect(model.repositories.isEmpty)
    }

    @Test
    func `git safety checks read the power source once for all repositories`() {
        let fixture = Fixture()
        defer { try? FileManager.default.removeItem(atPath: fixture.root) }
        let model = fixture.model
        model.hasLoaded = true
        model.groups += [RepositoryGroup(repository: Repository(name: "second", path: "/second"), items: [])]
        let reads = Mutex(0)
        model.isOnBattery = { reads.withLock { $0 += 1 }; return true }
        _ = model.gitReadScope(forcing: [])
        #expect(reads.withLock { $0 } == 1)
    }
}
