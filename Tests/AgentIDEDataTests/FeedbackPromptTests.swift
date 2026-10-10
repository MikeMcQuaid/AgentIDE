@testable import AgentIDEData
import Foundation
import Testing

struct FeedbackPromptTests {
    @Test
    func `each feedback brief can change independently and empty values use defaults`() throws {
        let suite = "feedback-prompts-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        for kind in FeedbackPrompt.allCases {
            #expect(kind.text(defaults: defaults) == kind.defaultText)
            defaults.set("Custom " + kind.rawValue, forKey: kind.key)
        }
        for kind in FeedbackPrompt.allCases {
            #expect(kind.text(defaults: defaults) == "Custom " + kind.rawValue)
            defaults.set(" \n\t", forKey: kind.key)
            #expect(kind.text(defaults: defaults) == kind.defaultText)
        }
    }
}
