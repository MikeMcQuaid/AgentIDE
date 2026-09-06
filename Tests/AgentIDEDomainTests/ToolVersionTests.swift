@testable import AgentIDEDomain
import Testing

/// Which of two tool versions is the older.
struct ToolVersionTests {
    @Test
    func `versions compare by number, not by text`() {
        #expect(ToolVersion.isOlder("0.152.1", than: "0.153.4"))
        #expect(ToolVersion.isOlder("0.153.4", than: "0.152.1") == false)
        // Text would put 0.9 after 0.153; numbers do not.
        #expect(ToolVersion.isOlder("0.9.0", than: "0.153.4"))
        #expect(ToolVersion.isOlder("0.153.4", than: "0.153.4") == false)
        // A shorter version is the older of two that agree so far.
        #expect(ToolVersion.isOlder("0.153", than: "0.153.4"))
    }
}
