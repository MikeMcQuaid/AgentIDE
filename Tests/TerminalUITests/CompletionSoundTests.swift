@testable import TerminalUI
import Testing

/// The completion chime's sound listing, its audio-only filter and
/// its silence through sleep.
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

    @Test
    func `a machine going to sleep is played nothing at all`() {
        // Sleep is announced before it happens: a chime started now
        // is the one nobody hears, and the one the old alert path
        // brought back looping.
        CompletionSound.beginSleeping()
        #expect(CompletionSound.play(path: CompletionSound.defaultPath) == false)

        // Waking gives the chimes back.
        CompletionSound.endSleeping()
        #expect(CompletionSound.play(path: CompletionSound.defaultPath))
        #expect(CompletionSound.play(path: "") == false)
        #expect(CompletionSound.play(path: "/nowhere/missing.aiff") == false)
    }
}
