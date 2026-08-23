import AppKit
import UniformTypeIdentifiers

/// The chime played when an agent finishes its work, stored on the
/// storage bus as a sound file's path so the menu bar can offer
/// macOS's own sounds, any audio file or silence, and no audio ever
/// ships in the repository.
public enum CompletionSound {
    // MARK: Public

    /// The storage-bus key holding the chosen sound's file path;
    /// the empty string is silence.
    public static let key = "completionSound"

    /// The default chime, one of macOS's own sounds.
    public static let defaultPath = "/System/Library/Sounds/Glass.aiff"

    /// The types the file chooser admits: exactly what playback
    /// accepts, so a picked file always sounds.
    public static let allowedTypes: [UTType] = [.audio]

    /// The chosen sound's path, defaulting to the system chime.
    public static var chosenPath: String {
        UserDefaults.standard.string(forKey: key) ?? defaultPath
    }

    /// The sound files the system offers: macOS's own, then the
    /// machine's and the user's additions, each directory sorted by
    /// name. Listed live so a newly added sound appears on the next
    /// menu open.
    public static func systemSounds() -> [(name: String, path: String)] {
        let directories = [
            "/System/Library/Sounds",
            "/Library/Sounds",
            NSHomeDirectory() + "/Library/Sounds",
        ]
        var sounds = [(name: String, path: String)]()
        for directory in directories {
            let entries = (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []
            for entry in entries.sorted() where isPlayable(entry) {
                sounds.append((
                    name: URL(filePath: entry).deletingPathExtension().lastPathComponent,
                    path: directory + "/" + entry,
                ))
            }
        }
        return sounds
    }

    /// Plays a sound file. The empty path is silence by choice, and
    /// a file that no longer plays is silence rather than an error:
    /// a missing sound must never break the notification it rode.
    public static func play(path: String) {
        guard path.isEmpty == false else {
            return
        }

        NSSound(contentsOfFile: path, byReference: true)?.play()
    }

    // MARK: Internal

    /// Whether a file name carries an audio type playback accepts.
    static func isPlayable(_ name: String) -> Bool {
        let pieces = name.split(separator: ".")
        guard pieces.count > 1, let suffix = pieces.last,
              let type = UTType(filenameExtension: String(suffix))
        else {
            return false
        }

        return allowedTypes.contains { type.conforms(to: $0) }
    }
}
