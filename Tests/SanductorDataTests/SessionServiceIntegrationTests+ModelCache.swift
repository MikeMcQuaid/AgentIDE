import Foundation
import SanductorData
import Testing

extension SessionServiceIntegrationTests {
    @Test
    func `a model cache names the client that wrote it`() {
        let cache = Data(#"{"client_version": "0.152.1", "fetched_at": "2026-09-06T16:04:41Z", "models": []}"#.utf8)
        #expect(SessionService.clientVersion(inModelCache: cache) == "0.152.1")
        #expect(SessionService.clientVersion(inModelCache: Data("{}".utf8)) == nil)
        #expect(SessionService.clientVersion(inModelCache: Data("not json".utf8)) == nil)
    }
}
