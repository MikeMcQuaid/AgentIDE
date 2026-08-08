import AgentIDEDomain
import Testing

struct DiffParserTests {
    // MARK: Internal

    @Test
    func `parses files hunks and line kinds`() throws {
        let files = DiffParser.parse(Self.sample)
        #expect(files.map(\.path) == ["hello.txt", "new.txt"])

        let hunk = try #require(files.first?.hunks.first)
        #expect(hunk.oldStart == 1)
        #expect(hunk.newStart == 1)
        #expect(hunk.lines.map(\.kind) == [.context, .deletion, .addition, .context])
        #expect(hunk.lines.map(\.content) == ["one", "two", "TWO", "three"])

        let added = try #require(files.last?.hunks.first)
        #expect(added.lines.map(\.kind) == [.addition])
    }

    @Test
    func `ignores headers and junk outside hunks`() {
        #expect(DiffParser.parse("not a diff at all\n").isEmpty)
    }

    @Test
    func `a trailing blank line is not a context line`() throws {
        let diff = "diff --git a/f.txt b/f.txt\n--- a/f.txt\n+++ b/f.txt\n@@ -1,1 +1,1 @@\n-a\n+b\n\n"
        let hunk = try #require(DiffParser.parse(diff).first?.hunks.first)
        #expect(hunk.lines.map(\.kind) == [.deletion, .addition])
    }

    @Test
    func `a deleted file keeps its old path`() throws {
        let diff = """
        diff --git a/gone.txt b/gone.txt
        deleted file mode 100644
        --- a/gone.txt
        +++ /dev/null
        @@ -1,2 +0,0 @@
        -one
        -two
        """
        let file = try #require(DiffParser.parse(diff).first)
        #expect(file.path == "gone.txt")
        #expect(file.hunks.first?.lines.map(\.kind) == [.deletion, .deletion])
    }

    // MARK: Private

    private static let sample = """
    diff --git a/hello.txt b/hello.txt
    index 3b18e51..2f5e1a5 100644
    --- a/hello.txt
    +++ b/hello.txt
    @@ -1,3 +1,3 @@
     one
    -two
    +TWO
     three
    diff --git a/new.txt b/new.txt
    new file mode 100644
    --- /dev/null
    +++ b/new.txt
    @@ -0,0 +1 @@
    +fresh
    """
}
