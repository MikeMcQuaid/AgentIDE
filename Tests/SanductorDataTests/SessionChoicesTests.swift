import Foundation
@testable import SanductorData
import Testing

/// What the app publishes for the `sanductor` command, which cannot
/// read Settings and so trusts this file for where things live.
struct SessionChoicesTests {
    // MARK: Internal

    @Test
    func `publishing the default directories replaces an override that was cleared`() async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        world.service.publishSessionChoices([
            ("repositories-directory", "/Users/Shared/custom/projects"),
            ("worktrees-directory", "/Users/Shared/custom/trees"),
            ("agent", "codex"),
        ])

        world.service.publishSessionChoices(world.service.locationChoices)

        let published = try Self.published(world)
        #expect(published.contains("repositories-directory=" + world.paths.sharedWorkspace + "/repositories"))
        #expect(published.contains("worktrees-directory=" + world.paths.sharedWorkspace + "/worktrees"))
        #expect(published.contains("custom") == false)
        #expect(published.contains("agent=codex"))
    }

    @Test
    func `a directory holding a newline is left out rather than split`() async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        world.service.publishSessionChoices([("repositories-directory", "/Users/Shared/old")])

        world.service.publishSessionChoices([("repositories-directory", "/Users/Shared/two\nlines")])

        let published = try Self.published(world)
        #expect(published.contains("repositories-directory") == false)
        #expect(published.contains("lines") == false)
    }

    @Test
    func `publishing what is already there leaves the file alone`() async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let file = world.paths.sanductorDirectory + "/session-defaults"
        world.service.publishSessionChoices(world.service.locationChoices)
        let past = Date(timeIntervalSinceNow: -3_600)
        try FileManager.default.setAttributes([.modificationDate: past], ofItemAtPath: file)

        world.service.publishSessionChoices(world.service.locationChoices)

        let modified = try #require(
            try FileManager.default.attributesOfItem(atPath: file)[.modificationDate] as? Date,
        )
        #expect(abs(modified.timeIntervalSince(past)) < 1)
    }

    @Test(arguments: [false, true])
    func `a planted link is replaced, never read through`(hard: Bool) async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let secret = world.root + "/secret"
        try "token=host-only\n".write(toFile: secret, atomically: true, encoding: .utf8)
        let directory = world.paths.sanductorDirectory
        let file = directory + "/session-defaults"
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        if hard {
            try FileManager.default.linkItem(atPath: secret, toPath: file)
        } else {
            try FileManager.default.createSymbolicLink(atPath: file, withDestinationPath: secret)
        }

        world.service.publishSessionChoices([("agent", "codex")])

        #expect(try String(contentsOfFile: file, encoding: .utf8) == "agent=codex\n")
        #expect(try String(contentsOfFile: secret, encoding: .utf8) == "token=host-only\n")
        #expect(try FileManager.default.attributesOfItem(atPath: file)[.type] as? FileAttributeType == .typeRegular)
    }

    @Test
    func `a planted directory link is never written through`() async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let elsewhere = world.root + "/elsewhere"
        try FileManager.default.createDirectory(atPath: elsewhere, withIntermediateDirectories: true)
        try "token=host-only\n".write(toFile: elsewhere + "/session-defaults", atomically: true, encoding: .utf8)
        let directory = world.paths.sanductorDirectory
        try? FileManager.default.removeItem(atPath: directory)
        try FileManager.default.createSymbolicLink(atPath: directory, withDestinationPath: elsewhere)

        world.service.publishSessionChoices([("agent", "codex")])
        world.service.publishHostDirectories(["/opt/homebrew"])

        #expect(try String(contentsOfFile: elsewhere + "/session-defaults", encoding: .utf8) == "token=host-only\n")
        #expect(try FileManager.default.contentsOfDirectory(atPath: elsewhere) == ["session-defaults"])
    }

    @Test
    func `a location outside the shared workspace is published as unset`() async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let inside = world.paths.sharedWorkspace + "/projects"

        #expect(world.service.publishedLocation(inside) == inside)
        #expect(world.service.publishedLocation(world.root + "/elsewhere").isEmpty)
        #expect(world.service.publishedLocation(world.paths.sandboxHome + "/trees").isEmpty)
    }

    @Test
    func `a listed directory holding a newline is left out`() async throws {
        let world = try await World.make()
        defer { world.tearDown() }

        world.service.publishHostDirectories(["/opt/two\nlines", "/opt/homebrew"])

        let published = try String(
            contentsOfFile: world.paths.sanductorDirectory + "/host-directories",
            encoding: .utf8,
        )
        #expect(published == "/opt/homebrew\n")
    }

    // MARK: Private

    private static func published(_ world: World) throws -> String {
        try String(contentsOfFile: world.paths.sanductorDirectory + "/session-defaults", encoding: .utf8)
    }
}
