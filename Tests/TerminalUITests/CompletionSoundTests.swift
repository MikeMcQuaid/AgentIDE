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

    @Test
    func `waking disposes sounds whose completion never came`() {
        // A sound sleep interrupted mid-play: its completion never
        // ran, so its id is still registered. The stray id stands in
        // for one the audio daemon holds; disposing an unknown id is
        // a harmless error.
        CompletionSound.lingering.withLock { _ = $0.insert(9_999_999) }
        CompletionSound.play(path: CompletionSound.defaultPath)

        CompletionSound.stopLingering()
        // Read outside the macro: the expansion cannot carry the
        // non-copyable mutex.
        let drained = CompletionSound.lingering.withLock(\.isEmpty)
        #expect(drained)

        // A drain with nothing playing is a quiet no-op.
        CompletionSound.stopLingering()
        let still = CompletionSound.lingering.withLock(\.isEmpty)
        #expect(still)
    }
}
