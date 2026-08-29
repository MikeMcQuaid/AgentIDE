@testable import AgentIDEData
import Foundation
import Testing

/// Drafts saved before labels existed still decode.
struct PullRequestFormDraftTests {
    @Test
    func `a draft without labels decodes with none`() throws {
        let old = Data(#"{"title":"t","body":"b","template":""}"#.utf8)
        let draft = try JSONDecoder().decode(PullRequestFormDraft.self, from: old)
        #expect(draft.labels.isEmpty)
        let labelled = PullRequestFormDraft(title: "t", body: "b", template: "", labels: ["ci"])
        let encoded = try JSONEncoder().encode(labelled)
        #expect(try JSONDecoder().decode(PullRequestFormDraft.self, from: encoded).labels == ["ci"])
    }
}
