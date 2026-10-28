import SanductorData
import Testing

struct CheckLogDocumentTests {
    @Test
    func `action groups hide markers and retain precise optional timestamps`() {
        let log = """
        2026-10-17T19:22:49.6831900Z ##[group]Runner Image Provisioner
         2026-10-17T19:22:49.6836160Z ##[endgroup]
        2026-10-17T19:22:50Z Done
        """
        let document = CheckLogDocument(log)
        #expect(document.lines.count == 2)
        #expect(document.lines[0].endIndex == 1)
        #expect(document.plainText(showTimestamps: false) == "Runner Image Provisioner\nDone")
        #expect(document.plainText(showTimestamps: true) == """
        2026-10-17T19:22:49.6831900Z Runner Image Provisioner
        2026-10-17T19:22:50Z Done
        """)
        #expect(document.visibleIndices(collapsedGroups: [0]) == [0, 1])
    }

    @Test
    func `nested groups with repeated titles collapse independently and copies stay complete`() {
        let document = CheckLogDocument("""
        before
        ##[group]Build
        output
        ##[group]Build
        error: compile failed
        ##[endgroup]
        after inner group
        ##[endgroup]
        after outer group
        """)
        #expect(document.visibleIndices(collapsedGroups: [1]) == [0, 1, 6])
        #expect(document.visibleIndices(collapsedGroups: [3]) == [0, 1, 2, 3, 5, 6])
        #expect(document.visibleIndices(collapsedGroups: [1, 3]) == [0, 1, 6])
        #expect(document.plainText(showTimestamps: false) == """
        before
        Build
          output
          Build
            error: compile failed
          after inner group
        after outer group
        """)
    }

    @Test
    func `unfinished groups and literal markers preserve output`() {
        let document = CheckLogDocument("##[endgroup]\nexample ##[group]literal\n##[group]Open\n  output\n")
        #expect(document.lines[1].endIndex == 4)
        #expect(document.visibleIndices(collapsedGroups: [1]) == [0, 1])
        #expect(document.plainText(showTimestamps: false) == "example ##[group]literal\nOpen\n    output\n  ")
    }

    @Test
    func `timestamp toggles preserve blank lines indentation and timestamps inside messages`() {
        let document = CheckLogDocument("\r\n2026-10-17T19:22:50.123Z   indented\r\n" +
            "2026-10-17T19:22:51Z logged 2026-10-16T10:00:00Z\r\n\r\n")
        #expect(document.plainText(showTimestamps: false) == "\n  indented\nlogged 2026-10-16T10:00:00Z\n\n")
        #expect(document.plainText(showTimestamps: true).contains("2026-10-17T19:22:50.123Z   indented"))
    }

    @Test
    func `processed diagnostics retain severity and literal message contents in copies`() {
        let document = CheckLogDocument("""
        2026-10-17T19:22:49.6831900Z ##[error]compile failed
        ##[warning]deprecated option
        ##[notice]<b>literal</b> %0A %25
        ##[debug]file.swift:3:4
        ##[warning]
        """)
        #expect(document.plainText(showTimestamps: false) == """
        Error: compile failed
        Warning: deprecated option
        Notice: <b>literal</b> %0A %25
        Debug: file.swift:3:4
        """ + "\nWarning: ")
        #expect(document.plainText(showTimestamps: true)
            .hasPrefix("2026-10-17T19:22:49.6831900Z Error: compile failed"))
    }

    @Test
    func `raw workflow commands and embedded or unsupported markers stay literal`() {
        let log = """
        ::stop-commands::token
        ::error file=app.js,line=1::Missing semicolon
        ::warning::literal warning
        ::group::literal group
        ::endgroup::
        ::token::
        ::add-mask::***
        ::echo::off
        ::save-state name=processID::12345
        example ##[error]literal
        ##[unknown]text
        """
        let document = CheckLogDocument(log)
        #expect(document.plainText(showTimestamps: false) == log)
        #expect(document.lines.allSatisfy { $0.endIndex == nil && $0.depth == 0 })
    }
}
