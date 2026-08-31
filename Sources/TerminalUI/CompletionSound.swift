import AppKit
import AudioToolbox
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

    /// Plays a sound file as an alert, so the system's alert volume
    /// and accessibility flash apply. The empty path is silence by
    /// choice, and a file that no longer plays is silence rather
    /// than an error: a missing sound must never break the
    /// notification it rode.
    public static func play(path: String) {
        guard path.isEmpty == false else {
            return
        }

        var sound: SystemSoundID = 0
        let made = AudioServicesCreateSystemSoundID(URL(fileURLWithPath: path) as CFURL, &sound)
        guard made == kAudioServicesNoError else {
            NSSound(contentsOfFile: path, byReference: true)?.play()
            return
        }

        lingering.withLock { _ = $0.insert(sound) }
        AudioServicesPlayAlertSoundWithCompletion(sound, Self.disposal(of: sound))
    }

    /// Disposes every sound whose completion never ran, called on
    /// wake: sleep can interrupt an alert mid-play and swallow its
    /// completion, and the audio daemon then replays the undisposed
    /// sound in a loop until something disposes it (playing any
    /// other alert did too, which is why a Settings preview used to
    /// stop the noise).
    public static func stopLingering() {
        let stuck = lingering.withLock { sounds in
            let all = sounds
            sounds = []
            return all
        }
        for sound in stuck {
            AudioServicesDisposeSystemSoundID(sound)
        }
    }

    // MARK: Internal

    /// The sounds playing right now, each removed by whoever
    /// disposes it, so a drain and a late completion can never
    /// dispose one sound twice.
    nonisolated static let lingering: Mutex<Set<SystemSoundID>> = .init([])

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

    /// The completion runs on the sound service's own queue, so it
    /// must not be a main-actor closure: the runtime's executor
    /// check traps there. Formed in a nonisolated context it stays
    /// free of any actor. Only the closure that still finds its
    /// sound registered disposes it; a wake drain may have got
    /// there first.
    private nonisolated static func disposal(of sound: SystemSoundID) -> @Sendable () -> Void {
        {
            guard lingering.withLock({ $0.remove(sound) != nil }) else {
                return
            }

            AudioServicesDisposeSystemSoundID(sound)
        }
    }
}
