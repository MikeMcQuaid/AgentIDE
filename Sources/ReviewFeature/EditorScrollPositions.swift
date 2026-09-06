import CoreGraphics
import Foundation

/// Where each file was last scrolled to in an editor, so a worktree
/// switch, a move to the other slot or a relaunch brings a file back
/// where it was rather than at its top.
///
/// Keyed by the file's own path: the two slots share one memory of a
/// file, since it is the same file. The set is capped so a year of
/// opened files never grows the defaults without bound; what falls
/// off the end is what was scrolled longest ago.
enum EditorScrollPositions {
    // MARK: Internal

    /// How many files are remembered; beyond this, the oldest go.
    static let capacity = 200

    /// The remembered origin for a file, nil for one never scrolled.
    static func position(for path: String, in defaults: UserDefaults = .standard) -> CGPoint? {
        guard let entry = entries(in: defaults).first(where: { $0.path == path }) else {
            return nil
        }

        return CGPoint(x: entry.across, y: entry.down)
    }

    /// Records where a file is scrolled to, moving it to the front
    /// of the line and dropping whatever has fallen off the end.
    static func remember(_ origin: CGPoint, for path: String, in defaults: UserDefaults = .standard) {
        var kept = entries(in: defaults).filter { $0.path != path }
        kept.insert(Entry(path: path, across: origin.x, down: origin.y), at: 0)
        let data = try? JSONEncoder().encode(Array(kept.prefix(capacity)))
        defaults.set(data, forKey: key)
    }

    // MARK: Private

    private struct Entry: Codable {
        let path: String
        let across: CGFloat
        let down: CGFloat
    }

    private static let key = "editorScrollPositions"

    private static func entries(in defaults: UserDefaults) -> [Entry] {
        guard let data = defaults.data(forKey: key) else {
            return []
        }

        return (try? JSONDecoder().decode([Entry].self, from: data)) ?? []
    }
}
