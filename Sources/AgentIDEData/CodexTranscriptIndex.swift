import AgentIDEDomain
import Foundation
import Synchronization

/// Indexes the flat Codex session tree by each session's embedded
/// working directory, so worktrees list and resume Codex
/// conversations even though nothing on disk is keyed by cwd, unlike
/// the other agent's per-directory transcripts. Heads parse once per
/// file change and cache, keeping the refresh poll cheap.
struct CodexTranscriptIndex {
    // MARK: Internal

    /// Decodes a fixed-size head read, dropping the final bytes when
    /// the cut landed inside a multi-byte character; the partial
    /// trailing line is skipped by the parse anyway.
    static func decodeHead(_ head: Data) -> String? {
        var bytes = head
        for _ in 0 ..< utf8CharacterBytes {
            if let text = String(bytes: bytes, encoding: .utf8) {
                return text
            }

            bytes = bytes.dropLast()
        }
        return nil
    }

    /// Sessions under `root` whose embedded working directory
    /// matches, newest first. The session id comes from the file's
    /// metadata line: the rollout file name is not the resume id.
    func sessions(inRoot root: String, workingDirectory: String) -> [TranscriptSession] {
        indexedEntries(root: root)
            .filter { $0.value.workingDirectory == workingDirectory }
            .map { path, entry in
                TranscriptSession(
                    id: entry.sessionID,
                    path: path,
                    agent: .codexCLI,
                    modifiedAt: entry.modifiedAt,
                    title: entry.title,
                )
            }
            .sorted { $0.modifiedAt > $1.modifiedAt }
    }

    // MARK: Private

    /// One parsed session head, keyed by file path in the cache.
    private struct Entry {
        let modifiedAt: Int
        let workingDirectory: String
        let sessionID: String
        let title: String
    }

    private struct Line: Decodable {
        let type: String?
        let payload: Payload?
    }

    private struct Payload: Decodable {
        // Absent from the JSON when a payload carries no content.
        // swiftlint:disable:next discouraged_optional_collection
        let content: [Content]?
        let type: String?
        let role: String?
        let cwd: String?
        let id: String?
        let sessionID: String?
        let message: String?
    }

    private struct Content: Decodable {
        let text: String?
    }

    /// One whole-tree listing per root within a refresh pass: the
    /// dashboard poll asks once per worktree in quick succession
    /// and the tree cannot meaningfully change between those asks.
    private struct Listing {
        let listedAt: ContinuousClock.Instant
        let entries: [String: Entry]
    }

    /// Heads are enough for the metadata and the first typed user
    /// message, which sits after Codex's large injected instruction
    /// and world-state lines; whole rollout files are larger still.
    private static let headBytes = 262_144

    /// A UTF-8 character spans at most this many bytes.
    private static let utf8CharacterBytes = 4

    /// The most sessions kept indexed, newest first.
    private static let entryCap = 2_000

    private static let cache: Mutex<[String: Entry]> = .init([:])

    private static let listings: Mutex<[String: Listing]> = .init([:])
    private static let listingLifetime: Duration = .seconds(1)

    /// Reads the file head: the metadata line names the session and
    /// its working directory, and the first user message titles it.
    private static func parseHead(path: String, modifiedAt: Int) -> Entry? {
        guard let handle = FileHandle(forReadingAtPath: path) else {
            return nil
        }

        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: headBytes),
              let text = decodeHead(head)
        else {
            return nil
        }

        let decoder = JSONDecoder()
        var workingDirectory: String?
        var sessionID: String?
        var title = ""
        for raw in text.split(separator: "\n") {
            guard let line = try? decoder.decode(Line.self, from: Data(raw.utf8)) else {
                continue
            }

            if line.type == "session_meta", let payload = line.payload {
                workingDirectory = payload.cwd
                sessionID = payload.id ?? payload.sessionID
            }
            if let typed = Self.typedUserMessage(line.payload) {
                title = typed
                    .split(separator: "\n")
                    .first
                    .map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
                break
            }
        }
        guard let workingDirectory, let sessionID else {
            return nil
        }

        return Entry(
            modifiedAt: modifiedAt,
            workingDirectory: workingDirectory,
            sessionID: sessionID,
            title: title,
        )
    }

    /// The text the user actually typed, from either rollout
    /// generation: current `message` payloads with a user role and
    /// content array, or the older flat `user_message`; Codex's
    /// injected instruction preambles do not count.
    private static func typedUserMessage(_ payload: Payload?) -> String? {
        guard let payload else {
            return nil
        }

        if payload.type == "user_message", let message = payload.message {
            return message
        }
        guard payload.type == "message", payload.role == "user" else {
            return nil
        }

        let text = (payload.content ?? []).compactMap(\.text).joined(separator: "\n")
        guard text.isEmpty == false, TranscriptReader.isInjectedCodexContext(text) == false else {
            return nil
        }

        return text
    }

    /// Every session file under the root, parsed or served from the
    /// caches when unchanged or recently listed.
    private func indexedEntries(root: String) -> [String: Entry] {
        let now = ContinuousClock.now
        if let listing = Self.listings.withLock({ $0[root] }), now - listing.listedAt < Self.listingLifetime {
            return listing.entries
        }

        let manager = FileManager.default
        var results = [String: Entry]()
        let enumerator = manager.enumerator(atPath: root)
        while let name = enumerator?.nextObject() as? String {
            guard name.hasSuffix(".jsonl") else {
                continue
            }

            let path = root + "/" + name
            let modifiedAt = Int(
                ((try? manager.attributesOfItem(atPath: path))?[.modificationDate] as? Date ?? .distantPast)
                    .timeIntervalSince1970,
            )
            let cached = Self.cache.withLock { $0[path] }
            if let cached, cached.modifiedAt == modifiedAt {
                results[path] = cached
            } else {
                // Unparseable heads cache as an empty sentinel, so
                // a bad file is not re-read on every poll; the empty
                // working directory can never match a worktree.
                results[path] = Self.parseHead(path: path, modifiedAt: modifiedAt)
                    ?? Entry(modifiedAt: modifiedAt, workingDirectory: "", sessionID: "", title: "")
            }
        }
        // The cache mirrors disk exactly and caps at the newest
        // entries, so deleted sessions drop out and it never grows
        // without bound.
        var bounded = results
        if bounded.count > Self.entryCap {
            let newest = bounded.sorted { $0.value.modifiedAt > $1.value.modifiedAt }.prefix(Self.entryCap)
            bounded = Dictionary(uniqueKeysWithValues: Array(newest))
        }
        Self.cache.withLock { $0 = bounded }
        Self.listings.withLock { $0[root] = Listing(listedAt: now, entries: bounded) }
        return bounded
    }
}
