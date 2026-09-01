@testable import AgentIDEDomain
import Testing

/// The `.editorconfig` files the editor reads: how one file parses,
/// which sections a path matches and how a chain of them resolves.
struct EditorConfigTests {
    @Test
    func `a file parses into its root flag and sections in order`() {
        let file = EditorConfigFile.parse(
            """
            # The repository's own, as this one is
            root = true

            [*]
            indent_style = space
            indent_size = 2
            insert_final_newline = true

            [*.swift]
            indent_size = 4
            """,
            directory: "/repo",
        )
        #expect(file.isRoot)
        #expect(file.sections.map(\.glob) == ["*", "*.swift"])
        #expect(file.sections.first?.properties["indent_size"] == "2")
        // Keys lowercase and values keep their case only where it
        // matters; both sides are trimmed.
        #expect(file.sections.first?.properties["insert_final_newline"] == "true")
    }

    @Test
    func `globs match the editorconfig way`() {
        #expect(EditorConfig.matches(glob: "*", path: "deep/file.swift"))
        #expect(EditorConfig.matches(glob: "*.swift", path: "Sources/Thing.swift"))
        #expect(EditorConfig.matches(glob: "*.swift", path: "Sources/Thing.rb") == false)
        // A glob with a slash anchors at the file's own directory.
        #expect(EditorConfig.matches(glob: "Sources/*.swift", path: "Sources/Thing.swift"))
        #expect(EditorConfig.matches(glob: "Sources/*.swift", path: "Sources/Deep/Thing.swift") == false)
        #expect(EditorConfig.matches(glob: "Sources/**.swift", path: "Sources/Deep/Thing.swift"))
        #expect(EditorConfig.matches(glob: "/Package.swift", path: "Package.swift"))
        #expect(EditorConfig.matches(glob: "/Package.swift", path: "Deep/Package.swift") == false)
        // Braces and character classes, the shapes real files use.
        #expect(EditorConfig.matches(glob: "*.{js,ts}", path: "app.ts"))
        #expect(EditorConfig.matches(glob: "*.{js,ts}", path: "app.rb") == false)
        #expect(EditorConfig.matches(glob: "file?.txt", path: "file1.txt"))
        #expect(EditorConfig.matches(glob: "[Mm]akefile", path: "makefile"))
        #expect(EditorConfig.matches(glob: "[!x]akefile", path: "makefile"))
    }

    @Test
    func `the nearest file wins and later sections beat earlier ones`() {
        let top = EditorConfigFile.parse(
            """
            root = true

            [*]
            indent_style = space
            indent_size = 2
            trim_trailing_whitespace = true

            [*.swift]
            indent_size = 4
            """,
            directory: "/repo",
        )
        let nested = EditorConfigFile.parse(
            """
            [*.swift]
            indent_style = tab
            """,
            directory: "/repo/Vendor",
        )

        let swift = EditorConfig.settings(forPath: "/repo/Sources/Thing.swift", files: [top])
        #expect(swift.indentStyle == .space)
        #expect(swift.indentSize == 4)
        #expect(swift.trimsTrailingWhitespace == .enabled)
        #expect(swift.indentUnit == "    ")

        let ruby = EditorConfig.settings(forPath: "/repo/Rakefile.rb", files: [top])
        #expect(ruby.indentUnit == "  ")

        // Nearest first, as the walk up finds them.
        let vendored = EditorConfig.settings(forPath: "/repo/Vendor/Thing.swift", files: [nested, top])
        #expect(vendored.indentStyle == .tab)
        #expect(vendored.indentUnit == "\t")
        // The outer file still supplies what the inner one leaves out.
        #expect(vendored.trimsTrailingWhitespace == .enabled)
    }

    @Test
    func `the walk stops at a root file and unset clears a property`() {
        let outer = EditorConfigFile.parse("[*]\nindent_size = 8\n", directory: "/")
        let inner = EditorConfigFile.parse(
            "root = true\n\n[*]\nindent_style = space\nindent_size = 2\n",
            directory: "/repo",
        )
        let settings = EditorConfig.settings(forPath: "/repo/file.txt", files: [inner, outer])
        #expect(settings.indentSize == 2)

        let cleared = EditorConfigFile.parse(
            "root = true\n\n[*]\nindent_style = space\n\n[*.txt]\nindent_style = unset\n",
            directory: "/repo",
        )
        #expect(EditorConfig.settings(forPath: "/repo/file.txt", files: [cleared]).indentStyle == nil)
    }

    @Test
    func `an indent size of tab follows the tab width`() {
        let file = EditorConfigFile.parse(
            "root = true\n\n[*]\nindent_style = space\nindent_size = tab\ntab_width = 3\n",
            directory: "/repo",
        )
        let settings = EditorConfig.settings(forPath: "/repo/file.txt", files: [file])
        #expect(settings.indentSize == 3)
        #expect(settings.indentUnit == "   ")

        // Nothing usable said: the editor falls back to the file's
        // own shape, which is nil here.
        let quiet = EditorConfigFile.parse("[*]\nend_of_line = lf\n", directory: "/repo")
        #expect(EditorConfig.settings(forPath: "/repo/file.txt", files: [quiet]).indentUnit == nil)
    }

    @Test
    func `booleans read as written and anything else is ignored`() {
        let file = EditorConfigFile.parse(
            """
            [*]
            trim_trailing_whitespace = FALSE
            insert_final_newline = true

            [*.md]
            trim_trailing_whitespace = maybe
            """,
            directory: "/repo",
        )
        let plain = EditorConfig.settings(forPath: "/repo/notes.txt", files: [file])
        #expect(plain.trimsTrailingWhitespace == .disabled)
        #expect(plain.insertsFinalNewline == .enabled)

        // An unreadable value leaves the inherited one alone.
        let markdown = EditorConfig.settings(forPath: "/repo/notes.md", files: [file])
        #expect(markdown.trimsTrailingWhitespace == .disabled)
    }
}
