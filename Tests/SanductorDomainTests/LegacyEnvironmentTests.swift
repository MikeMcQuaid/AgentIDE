@testable import SanductorDomain
import Testing

struct LegacyEnvironmentTests {
    @Test
    func `legacy variables warn without exposing values and canonical values win`() {
        var warnings = [String]()
        #expect(LegacyEnvironment.value(
            for: "SANDUCTOR_EDITS",
            warning: { warnings.append($0) },
            environment: ["AGENTIDE_EDITS": "private value"],
        ) == "private value")
        #expect(warnings == ["Warning: AGENTIDE_EDITS is deprecated; use SANDUCTOR_EDITS instead."])
        warnings.removeAll()
        #expect(LegacyEnvironment.value(
            for: "SANDUCTOR_EDITS",
            warning: { warnings.append($0) },
            environment: ["AGENTIDE_EDITS": "old", "SANDUCTOR_EDITS": ""],
        )?.isEmpty == true)
        #expect(warnings.isEmpty)
    }
}
