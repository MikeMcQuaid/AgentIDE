@testable import AgentIDEData
import Foundation
import Testing

/// The wake the spool loop waits on: it has to keep waiting after a
/// timeout, which is exactly what the stream it replaced could not.
struct DirectoryWakeTests {
    @Test
    func `a timed-out wait does not make the next one return at once`() async {
        let wake = DirectoryWake()
        let timeout = Duration.milliseconds(40)

        let first = ContinuousClock.now
        await wake.wait(timeout: timeout)
        #expect(ContinuousClock.now - first >= timeout)

        // The regression: after one timeout every wait returned
        // immediately, and the loop scanned the spool flat out.
        let second = ContinuousClock.now
        await wake.wait(timeout: timeout)
        #expect(ContinuousClock.now - second >= timeout)
    }

    @Test
    func `a ring wakes the waiter early, or the next waiter once`() async {
        let wake = DirectoryWake()
        let long = Duration.seconds(30)

        // A ring before anyone waits is kept for the next wait, and
        // spent by it: the one after waits its full timeout.
        wake.ring()
        wake.ring()
        let kept = ContinuousClock.now
        await wake.wait(timeout: long)
        // Early means before the timeout, not fast: a loaded runner
        // can hold a task for seconds, and only the timeout would
        // have made it five.
        #expect(ContinuousClock.now - kept < long)
        let spent = ContinuousClock.now
        await wake.wait(timeout: .milliseconds(30))
        #expect(ContinuousClock.now - spent >= .milliseconds(30))

        // A ring while waiting ends the wait at once.
        let ringing = Task {
            try? await Task.sleep(for: .milliseconds(30))
            wake.ring()
        }
        let early = ContinuousClock.now
        await wake.wait(timeout: long)
        #expect(ContinuousClock.now - early < long)
        await ringing.value
    }

    @Test
    func `a ring landing as the waiter installs is never lost`() async {
        // The check for a pending ring and the installing of the
        // waiter were once two lock takes, and a ring between them
        // waited out the whole timeout. Raced two hundred times with
        // a two-second timeout, that version overran on some; every
        // wait here has to return well inside it.
        let wake = DirectoryWake()
        let timeout = Duration.seconds(2)
        let rounds = 200
        let started = ContinuousClock.now
        for _ in 0 ..< rounds {
            let ringing = Task { wake.ring() }
            await wake.wait(timeout: timeout)
            await ringing.value
        }
        #expect(ContinuousClock.now - started < timeout)
    }
}
