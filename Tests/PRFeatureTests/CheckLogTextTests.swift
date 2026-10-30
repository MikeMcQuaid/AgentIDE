import AppKit
@testable import PRFeature
import SanductorData
import Testing

struct CheckLogTextTests {
    @Test(arguments: [
        ("error", "Error", NSColor.systemRed),
        ("warning", "Warning", NSColor.systemOrange),
        ("notice", "Notice", NSColor.systemBlue),
        ("debug", "Debug", NSColor.secondaryLabelColor),
    ])
    func `diagnostics show readable severity labels and semantic colours`(
        level: String, label: String, colour: NSColor,
    ) {
        let text = CheckLogText.attributed(
            CheckLogDocument("2026-10-17T19:22:49Z ##[" + level + "]message\nplain output"),
            showTimestamps: false,
            collapsedGroups: [],
            font: .monospacedSystemFont(ofSize: 12, weight: .regular),
        )
        #expect(text.string == label + ": message\nplain output")
        #expect(unsafe text.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == colour)
        #expect(unsafe text.attribute(.foregroundColor, at: text.length - 1, effectiveRange: nil) as? NSColor
            == .textColor)
    }

    @Test(arguments: ["[command]", "##[command]"], [false, true])
    func `commands render in bold without their marker`(marker: String, showTimestamps: Bool) throws {
        let command = "/opt/homebrew/bin/git config --global --add safe.directory "
            + "/Users/runner/work/Sanductor/Sanductor"
        let document = CheckLogDocument("""
        ##[group]Setup
        2026-10-17T19:22:49.6831900Z \(marker)\(command)
        Output mentions [command] literally
        ##[endgroup]
        """)
        let text = CheckLogText.attributed(
            document,
            showTimestamps: showTimestamps,
            collapsedGroups: [],
            font: .monospacedSystemFont(ofSize: 12, weight: .regular),
        )
        #expect(text.string == "▾ Setup\n" + (showTimestamps ? "19:22:49  " : "")
            + "  " + command + "\n  Output mentions [command] literally")
        let commandIndex = try NSRange(#require(text.string.range(of: command)), in: text.string).location
        let outputIndex = try NSRange(#require(text.string.range(of: "Output")), in: text.string).location
        let commandFont = try #require(unsafe text.attribute(.font, at: commandIndex, effectiveRange: nil)
            as? NSFont)
        let outputFont = try #require(unsafe text.attribute(.font, at: outputIndex, effectiveRange: nil)
            as? NSFont)
        #expect(commandFont.fontDescriptor.symbolicTraits.contains(.bold))
        #expect(outputFont.fontDescriptor.symbolicTraits.contains(.bold) == false)
        #expect(document.plainText(showTimestamps: false) == "Setup\n  " + command
            + "\n  Output mentions [command] literally")
    }

    @Test
    func `groups render as local disclosure links without interpreting output`() throws {
        let document = CheckLogDocument("""
        2026-10-17T19:22:49.6831900Z ##[group]Runner Image Provisioner
        2026-10-17T19:22:49.6836160Z <script>literal output</script>
        2026-10-17T19:22:49.6840000Z ##[endgroup]
        Done
        """)
        let expanded = CheckLogText.attributed(
            document,
            showTimestamps: false,
            collapsedGroups: [],
            font: .monospacedSystemFont(ofSize: 12, weight: .regular),
        )
        #expect(expanded.string == "▾ Runner Image Provisioner\n  <script>literal output</script>\nDone")
        let link = unsafe expanded.attribute(.link, at: 0, effectiveRange: nil) as? URL
        #expect(try #require(link).absoluteString == "sanductor-log-group://0")
        let collapsed = CheckLogText.attributed(
            document,
            showTimestamps: true,
            collapsedGroups: [0],
            font: .monospacedSystemFont(ofSize: 12, weight: .regular),
        )
        #expect(collapsed.string == "19:22:49  ▸ Runner Image Provisioner\nDone")
        #expect(unsafe collapsed.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
            == .secondaryLabelColor)
        #expect(unsafe collapsed.attribute(.toolTip, at: 0, effectiveRange: nil) as? String
            == "2026-10-17T19:22:49.6831900Z")
        #expect(document.plainText(showTimestamps: false).contains("<script>literal output</script>"))
    }

    @Test
    func `timestamps show only hours minutes and seconds while copies retain source precision`() {
        let document = CheckLogDocument("""
        2026-10-17T23:59:59.9999999Z Before midnight
        2026-10-18T00:00:00Z After midnight
        2026-10-18T00:00:00.1Z Later
        No timestamp
        """)
        let text = CheckLogText.attributed(
            document,
            showTimestamps: true,
            collapsedGroups: [],
            font: .monospacedSystemFont(ofSize: 12, weight: .regular),
        )
        #expect(text.string == """
        23:59:59  Before midnight
        00:00:00  After midnight
        00:00:00  Later
        No timestamp
        """)
        #expect(document.plainText(showTimestamps: true).hasPrefix("2026-10-17T23:59:59.9999999Z Before midnight"))
    }

    @Test
    func `empty lines survive rendering`() {
        let text = CheckLogText.attributed(
            CheckLogDocument("\n\ntext\n"),
            showTimestamps: false,
            collapsedGroups: [],
            font: .monospacedSystemFont(ofSize: 12, weight: .regular),
        )
        #expect(text.string == "\n\ntext\n")
    }
}
