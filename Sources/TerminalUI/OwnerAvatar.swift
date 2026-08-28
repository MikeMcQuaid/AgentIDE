import AppKit
import SwiftUI

// MARK: - OwnerAvatarStore

/// GitHub owner avatars, fetched once per owner and kept on disk.
///
/// Every repository of an owner shares one image, so a sidebar of
/// twenty repositories under three owners fetches three times, not
/// twenty. The disk copy is the point of the cache rather than a
/// nicety: GitHub goes down, and an outage should not blank the
/// sidebar's icons.
@preconcurrency
@Observable
@MainActor
public final class OwnerAvatarStore {
    // MARK: Lifecycle

    private init() {
        // One store for the whole app.
    }

    deinit {
        // The store lives for the process.
    }

    // MARK: Public

    /// The one store every sidebar row reads.
    public static let shared: OwnerAvatarStore = .init()

    /// The owner's avatar when one is known: memory first, then the
    /// disk copy, then a fetch that fills both.
    public func image(for owner: String) -> NSImage? {
        if let image = images[owner] {
            return image
        }
        guard missing.contains(owner) == false else {
            return nil
        }

        if let image = Self.diskImage(for: owner) {
            images[owner] = image
            return image
        }

        fetch(owner)
        return nil
    }

    // MARK: Private

    /// An avatar that is not a 200 is not an avatar; nonisolated so
    /// the off-main download can read it.
    private nonisolated static let httpOK = 200

    /// Resolved once: the sidebar reads a file per row per render,
    /// and each read was also a `createDirectory` call.
    private static let directory: URL = {
        let base = URL(fileURLWithPath: NSHomeDirectory())
            .appending(path: "Library/Application Support/AgentIDE/Avatars")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }()

    /// Owners already being fetched, so a redrawing sidebar asks
    /// once rather than once per row per frame, and owners whose
    /// fetch failed, remembered for the run: without the negative
    /// cache a missing avatar re-read the disk and re-fetched on
    /// every render.
    private var inFlight: Set<String> = []
    private var missing: Set<String> = []
    private var images: [String: NSImage] = [:]

    /// The cached file for an owner; the name is percent encoded, so
    /// an owner with a slash or a dot cannot escape the directory.
    private static func file(for owner: String) -> URL {
        let safe = owner.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? owner
        return directory.appending(path: safe + ".png")
    }

    private static func diskImage(for owner: String) -> NSImage? {
        guard let data = try? Data(contentsOf: file(for: owner)) else {
            return nil
        }

        return NSImage(data: data)
    }

    /// Fetches an avatar and keeps a copy, away from the main
    /// actor: `@concurrent` because a plain nonisolated async
    /// function would run on its caller's actor, which is the one
    /// drawing the sidebar.
    @concurrent
    private nonisolated static func download(from url: URL, to file: URL) async -> Data? {
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == httpOK
        else {
            return nil
        }

        try? data.write(to: file, options: .atomic)
        return data
    }

    /// Fetches an owner's avatar and keeps it. A failure is silent
    /// on purpose: the icon is decoration, the disk copy covers an
    /// outage, and the messages pane is for things the user can act
    /// on.
    private func fetch(_ owner: String) {
        guard inFlight.contains(owner) == false,
              let url = URL(string: "https://github.com/" + owner + ".png?size=64")
        else {
            return
        }

        inFlight.insert(owner)
        Task { [weak self] in
            // The fetch and the disk write run off the main actor;
            // only the small decode and the state update come back
            // to it, so a sidebar of owners cannot stutter the UI.
            let data = await Self.download(from: url, to: Self.file(for: owner))
            self?.inFlight.remove(owner)
            guard let data, let image = NSImage(data: data) else {
                // Remembered for the run: an owner with no avatar
                // is not fetched again per render.
                self?.missing.insert(owner)
                return
            }

            self?.images[owner] = image
        }
    }
}

// MARK: - OwnerAvatar

/// One owner's avatar, from the shared per-owner cache, falling back
/// to a folder glyph until an image exists.
public struct OwnerAvatar: View {
    // MARK: Lifecycle

    /// Creates the avatar for an owner, nil when the repository has
    /// no known owner.
    public init(owner: String?, size: CGFloat) {
        self.owner = owner
        self.size = size
    }

    // MARK: Public

    public var body: some View {
        Group {
            if let image = owner.flatMap({ store.image(for: $0) }) {
                Image(nsImage: image).resizable()
            } else {
                Image(systemName: "folder.fill").font(.caption)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    // MARK: Private

    private var store: OwnerAvatarStore = .shared

    private let owner: String?
    private let size: CGFloat
}
