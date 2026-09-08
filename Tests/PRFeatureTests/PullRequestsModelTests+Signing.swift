@testable import PRFeature
import Synchronization
import Testing

/// A tip that reads unsigned after a rebase is read again after a
/// moment, then rebased once more, before anyone is asked to press
/// anything.
extension PullRequestsModelTests {
    @Test
    func `a tip read too early is read again, not rebased again`() async {
        let model = makeModel(items: [item(branch: "feature", ahead: 1)])
        let rebases = Mutex(0)
        let readsAfterRebase = Mutex(0)
        model.performRebase = { _ in
            rebases.withLock { $0 += 1 }
            return "origin/main"
        }
        // The first read after the rebase lands before the rebase
        // did; the next reads it signed.
        model.checkTipSigned = { _ in
            guard rebases.withLock({ $0 }) > 0 else {
                return false
            }

            return readsAfterRebase.withLock { reads in
                reads += 1
                return reads >= 2
            }
        }
        await model.reload()

        #expect(await model.rebaseSigned())
        #expect(rebases.withLock { $0 } == 1)
        #expect(model.tipSignature == .signed)
    }

    @Test
    func `a tip still unsigned after a rebase and a second read is rebased once more`() async {
        let model = makeModel(items: [item(branch: "feature", ahead: 1)])
        let rebases = Mutex(0)
        model.performRebase = { _ in
            rebases.withLock { $0 += 1 }
            return "origin/main"
        }
        // Unsigned however often it is read until the second rebase.
        model.checkTipSigned = { _ in rebases.withLock { $0 } >= 2 }
        await model.reload()

        #expect(await model.rebaseSigned())
        #expect(rebases.withLock { $0 } == 2)
        #expect(model.tipSignature == .signed)
    }

    @Test
    func `a tip unsigned after two rebases is reported, not rebased again`() async {
        let model = makeModel(items: [item(branch: "feature", ahead: 1)])
        let rebases = Mutex(0)
        model.performRebase = { _ in
            rebases.withLock { $0 += 1 }
            return "origin/main"
        }
        model.checkTipSigned = { _ in false }
        await model.reload()

        #expect(await model.rebaseSigned() == false)
        #expect(rebases.withLock { $0 } == 2)
    }
}
