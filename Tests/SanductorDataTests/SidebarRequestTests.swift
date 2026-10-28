import Darwin
import Foundation
@testable import SanductorData
import SanductorDomain
import Testing

struct SidebarRequestTests {
    @Test
    func `sidebar requests reject links pipes oversized and malformed input`() throws {
        let root = try TestSupport.temporaryDirectory("sidebar-requests")
        defer { try? FileManager.default.removeItem(atPath: root) }
        let data = try JSONEncoder().encode(SidebarRequest.sources(repositoryPath: "/repo"))
        let valid = UUID().uuidString
        try data.write(to: URL(filePath: root + "/" + valid + ".request"))
        try data.write(to: URL(filePath: root + "/invalid-name.request"))
        try Data("invalid".utf8).write(to: URL(filePath: root + "/" + UUID().uuidString + ".request"))
        try Data(repeating: 0, count: SidebarRequest.maximumBytes + 1)
            .write(to: URL(filePath: root + "/" + UUID().uuidString + ".request"))
        try FileManager.default.createSymbolicLink(
            atPath: root + "/" + UUID().uuidString + ".request", withDestinationPath: root + "/" + valid + ".request",
        )
        #expect(unsafe mkfifo(root + "/" + UUID().uuidString + ".request", 0o600) == 0)
        let requests = SessionService.readSidebarRequests(in: root)
        #expect(requests.map(\.id) == [valid])
        if case let .sources(repositoryPath) = try #require(requests.first).request {
            #expect(repositoryPath == "/repo")
        } else {
            Issue.record("Lost the picker request")
        }
        try Data().write(to: URL(filePath: root + "/" + valid + ".response"))
        #expect(SessionService.readSidebarRequests(in: root).isEmpty)
    }
}
