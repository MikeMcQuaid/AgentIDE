import Foundation
import ImageIO
import SwiftUI

// MARK: - OwnerAvatarStore

/// One cached image per owner, shared by every repository on both platforms.
@Observable
final class OwnerAvatarStore {
    // MARK: Lifecycle

    init() { /* The app shares one store; tests own isolated caches. */ }

    deinit { /* The shared store lives for the process. */ }

    // MARK: Internal

    static let shared: OwnerAvatarStore = .init()

    private(set) var images: [String: CGImage] = [:]

    @discardableResult
    func load(
        _ owner: String,
        download: @escaping (URL, String) async throws -> Data? = OwnerAvatarStore.download,
    ) -> Task<Void, Never>? {
        guard images[owner] == nil, missing.contains(owner) == false,
              owner.range(of: "^[A-Za-z0-9-]+$", options: .regularExpression) != nil,
              let url = URL(string: "https://github.com/" + owner + ".png?size=64"),
              inFlight.insert(owner).inserted
        else {
            return nil
        }

        // A row scrolling away must not cancel another row's shared download.
        return Task {
            defer { inFlight.remove(owner) }
            let data: Data?
            do {
                data = try await download(url, owner)
            } catch {
                return
            }
            guard let data, let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
            else {
                // A missing avatar must not retry on every row render.
                missing.insert(owner)
                return
            }

            images[owner] = image
        }
    }

    // MARK: Private

    private nonisolated static let httpOK = 200
    private nonisolated static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        return URLSession(configuration: configuration)
    }()

    private var inFlight: Set<String> = []
    private var missing: Set<String> = []

    /// Disk reads and downloads stay outside view evaluation and the main actor.
    @concurrent
    private nonisolated static func download(from url: URL, owner: String) async throws -> Data? {
        let directory = URL.applicationSupportDirectory.appending(path: "Sanductor/Avatars")
        let file = directory.appending(path: owner + ".png")
        if let data = try? Data(contentsOf: file) {
            return data
        }
        let (data, response) = try await session.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == httpOK else {
            return nil
        }

        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
        return data
    }
}

// MARK: - OwnerAvatar

/// A public GitHub avatar with a placeholder and a per-owner disk cache.
public struct OwnerAvatar: View {
    // MARK: Lifecycle

    /// Creates an avatar for a GitHub login, nil when unknown.
    public init(owner: String?, size: CGFloat, placeholder: String = "folder.fill") {
        self.owner = owner?.lowercased()
        self.size = size
        self.placeholder = placeholder
    }

    // MARK: Public

    public var body: some View {
        Group {
            if let image = owner.flatMap({ store.images[$0] }) {
                Image(decorative: image, scale: 1).resizable()
            } else {
                Image(systemName: placeholder).interfaceFont(.caption)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .task(id: owner) {
            if let owner {
                store.load(owner)
            }
        }
    }

    // MARK: Private

    private var store: OwnerAvatarStore = .shared
    private let owner: String?
    private let size: CGFloat
    private let placeholder: String
}
