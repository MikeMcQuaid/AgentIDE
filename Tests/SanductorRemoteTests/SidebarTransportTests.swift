import Foundation
import SanductorDomain
@testable import SanductorRemote
import Testing

struct SidebarTransportTests {
    @Test
    func `phone requests transmit notes literally and clean up after acknowledgement`() throws {
        let root = FileManager.default.currentDirectoryPath + "/.test-scratch/sidebar-" + UUID().uuidString
        let directory = root + "/sanductor/sidebar-requests-sanductor-dev"
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: root) }
        let identifier = UUID().uuidString
        let response = try JSONEncoder().encode(SidebarResponse(error: "Keep waiting"))
        try response.write(to: URL(filePath: directory + "/" + identifier + ".response"))
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        process.executableURL = URL(filePath: "/bin/sh")
        process.arguments = ["-c", RemoteHerdr.sidebarRequestScript, "sanductor-sidebar", identifier]
        process.environment = ["SHARED_WORKSPACE": root, "HERDR_SESSION": "sanductor-dev", "PATH": "/usr/bin:/bin"]
        process.standardInput = input
        process.standardOutput = output
        try process.run()
        try input.fileHandleForWriting.write(contentsOf: Data("$(touch should-not-exist) `false`\n'quoted'".utf8))
        try input.fileHandleForWriting.close()
        let received = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        #expect(try JSONDecoder().decode(SidebarResponse.self, from: received).error == "Keep waiting")
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory).isEmpty)
    }
}
