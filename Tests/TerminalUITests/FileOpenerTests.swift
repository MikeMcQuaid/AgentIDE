@testable import TerminalUI
import Testing

struct FileOpenerTests {
    @Test
    func `repository paths cannot become absolute editor requests`() {
        #expect(FileOpener.safePath(relativePath: "/outside/file", worktreePath: "/repo") == nil)
        #expect(FileOpener.safePath(relativePath: "../outside/file", worktreePath: "/repo") == nil)
        #expect(FileOpener.safePath(relativePath: "Sources/file.swift", worktreePath: "/repo")
            == "/repo/Sources/file.swift")
    }
}
