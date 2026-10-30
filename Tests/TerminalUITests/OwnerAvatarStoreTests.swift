import Foundation
@testable import SanductorInterface
import Testing

@MainActor
struct OwnerAvatarStoreTests {
    // MARK: Internal

    @Test(arguments: [URLError.notConnectedToInternet, .timedOut, .cancelled])
    func `transport failures allow a later load to recover`(code: URLError.Code) async throws {
        let image = try #require(Data(base64Encoded: Self.encodedImage))
        let store = OwnerAvatarStore()
        var attempts = 0
        let download: (URL, String) throws -> Data? = { _, _ in
            attempts += 1
            if attempts == 1 {
                throw URLError(code)
            }
            return image
        }
        await store.load("owner", download: download)?.value
        #expect(store.images["owner"] == nil)
        await store.load("owner", download: download)?.value
        #expect(attempts == 2)
        #expect(store.images["owner"]?.width == 1)
        await store.load("owner", download: download)?.value
        #expect(attempts == 2)
    }

    @Test(arguments: [false, true])
    func `HTTP misses and invalid images are not repeatedly downloaded`(invalidImage: Bool) async {
        let store = OwnerAvatarStore()
        var attempts = 0
        let download: (URL, String) -> Data? = { _, _ in
            attempts += 1
            return invalidImage ? Data("not an image".utf8) : nil
        }
        for _ in 0 ..< 3 {
            await store.load("owner", download: download)?.value
        }
        #expect(attempts == 1)
        #expect(store.images["owner"] == nil)
    }

    @Test
    func `rows share downloads and reuse a successful image`() async throws {
        let image = try #require(Data(base64Encoded: Self.encodedImage))
        let store = OwnerAvatarStore()
        var attempts = 0
        let download: (URL, String) -> Data? = { _, _ in
            attempts += 1
            return image
        }
        let first = store.load("owner", download: download)
        #expect(store.load("owner", download: download) == nil)
        await first?.value
        #expect(store.images["owner"]?.width == 1)
        #expect(store.load("owner", download: download) == nil)
        #expect(attempts == 1)
    }

    // MARK: Private

    private static let encodedImage = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lE"
        + "QVR42mP8/x8AAwMCAO+aOtQAAAAASUVORK5CYII="
}
