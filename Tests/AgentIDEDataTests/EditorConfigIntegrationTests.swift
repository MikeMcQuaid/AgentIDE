import AgentIDEData
import AgentIDEDomain
import Foundation
import Testing

/// Finding the `.editorconfig` files that govern a file on disk: the
/// walk up from it, and where the walk stops.
struct EditorConfigIntegrationTests {
    @Test
    func `the walk up finds every configuration governing a file`() async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let root = world.repository.path
        try (
            "root = true\n\n[*]\nindent_style = space\nindent_size = 2\n"
                + "\n[*.swift]\nindent_size = 4\n"
        ).write(toFile: root + "/.editorconfig", atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(
            atPath: root + "/Vendor/Deep",
            withIntermediateDirectories: true,
        )
        try "[*.swift]\nindent_style = tab\n".write(
            toFile: root + "/Vendor/.editorconfig",
            atomically: true,
            encoding: .utf8,
        )

        let top = await world.service.editorConfigSettings(worktreePath: root, filePath: root + "/Sources/Thing.swift")
        #expect(top.indentUnit == "    ")
        #expect(top.insertsFinalNewline == .unspoken)

        // The nearer file wins where it speaks, the outer one still
        // supplying the rest.
        let vendored = await world.service.editorConfigSettings(
            worktreePath: root,
            filePath: root + "/Vendor/Deep/Thing.swift",
        )
        #expect(vendored.indentUnit == "\t")
        #expect(vendored.indentSize == 4)

        // A file governed only by the wildcard section.
        let plain = await world.service.editorConfigSettings(worktreePath: root, filePath: root + "/notes.txt")
        #expect(plain.indentUnit == "  ")
    }

    @Test
    func `a worktree without any configuration says nothing`() async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        let settings = await world.service.editorConfigSettings(
            worktreePath: world.repository.path,
            filePath: world.repository.path + "/README.md",
        )
        #expect(settings == EditorConfigSettings())
    }

    @Test
    func `a file outside the worktree is judged by nothing inside it`() async throws {
        let world = try await World.make()
        defer { world.tearDown() }
        try "root = true\n\n[*]\nindent_style = tab\n".write(
            toFile: world.repository.path + "/.editorconfig",
            atomically: true,
            encoding: .utf8,
        )
        let outside = await world.service.editorConfigSettings(
            worktreePath: world.repository.path,
            filePath: world.root + "/elsewhere/file.swift",
        )
        #expect(outside == EditorConfigSettings())
    }
}
