import Foundation
@testable import SanductorRemote
import Testing

struct RemoteCreationTests {
    @Test
    func `creation needs only the root pane ID`() throws {
        let output = Data(#"{"result":{"root_pane":{"pane_id":"w2:p1"}}}"#.utf8)
        #expect(try JSONDecoder().decode(CreatedWorkspace.self, from: output).result.rootPane.paneID == "w2:p1")
    }
}
