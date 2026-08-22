@testable import TerminalUI
import Testing

/// The completion chime's sound listing and its audio-only filter.
struct CompletionSoundTests {
    @Test
    func `the system listing offers the default chime`() {
        let sounds = CompletionSound.systemSounds()

        #expect(sounds.contains { $0.path == CompletionSound.defaultPath })
        #expect(sounds.contains { $0.name == "Glass" })
    }

    @Test
    func `every listed sound is a playable audio type`() {
        for sound in CompletionSound.systemSounds() {
            #expect(CompletionSound.isPlayable(sound.path), "\(sound.path) should be audio")
        }
    }

    @Test
    func `only audio file types pass the filter`() {
        #expect(CompletionSound.isPlayable("Glass.aiff"))
        #expect(CompletionSound.isPlayable("ding.wav"))
        #expect(CompletionSound.isPlayable("chime.m4a"))
        #expect(CompletionSound.isPlayable("notes.txt") == false)
        #expect(CompletionSound.isPlayable("movie.mov") == false)
        #expect(CompletionSound.isPlayable("no-extension") == false)
    }
}
