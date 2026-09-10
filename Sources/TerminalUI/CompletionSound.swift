import AppKit
import Synchronization
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

    /// Plays a sound file in the app's own process, through
    /// `NSSound`, the way a Mac app plays a sound of its own, and off
    /// the main thread: the system's alert path handed a sound to
    /// the audio daemon, which replayed one whose completion it lost
    /// in a loop, and the same daemon can stall the first play for
    /// seconds, which on the main thread was the app hanging at
    /// launch with its "done" chimes. One at a time on a queue of
    /// its own, held there until it finishes. The empty path is
    /// silence by choice, a file that no longer plays is silence
    /// rather than an error, and a machine that has announced sleep
    /// is played nothing, since nobody is there to hear it. Whether
    /// a sound was handed to the queue.
    @discardableResult
    public static func play(path: String) -> Bool {
        guard path.isEmpty == false, FileManager.default.isReadableFile(atPath: path),
              isSleeping.withLock({ $0 == false })
        else {
            return false
        }

        queue.async {
            guard let sound = NSSound(contentsOfFile: path, byReference: true) else {
                return
            }

            sound.play()
            // Held here for as long as it plays, and cut off should
            // the machine announce sleep while it does.
            while sound.isPlaying {
                if isSleeping.withLock({ $0 }) {
                    sound.stop()
                    return
                }
                Thread.sleep(forTimeInterval: Self.pollSeconds)
            }
        }
        return true
    }

    /// Stops chiming, called when the machine announces sleep: a
    /// sound cut off then is silent, never stuck.
    public static func beginSleeping() {
        isSleeping.withLock { $0 = true }
    }

    /// Chimes again on wake.
    public static func endSleeping() {
        isSleeping.withLock { $0 = false }
    }

    // MARK: Internal

    /// Whether the machine is asleep or on its way there, which is
    /// the one time nothing is played.
    nonisolated static let isSleeping: Mutex<Bool> = .init(false)

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

    // MARK: Private

    /// How often a playing sound is checked for the sleep flag.
    private static let pollSeconds: TimeInterval = 0.05

    /// One sound at a time, away from the main thread.
    private static let queue: DispatchQueue = .init(label: "agentide.chime", qos: .userInitiated)
}
