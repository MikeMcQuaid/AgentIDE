import AgentIDEData
import AgentIDEDomain
import Foundation
@testable import PRFeature
import Testing

/// Push's availability and refusals: unpushed counts, the tip's
/// signature proven before the button lights, and a push that can
/// never error on an unsigned tip; split from the model tests for
/// length.
extension PullRequestsModelTests {
    @Test
    func `push needs unpushed commits and the form needs no open pull request`() async {
        let pushed = makeModel(items: [item(branch: "feature", ahead: 0)])
        await pushed.reload()
        #expect(pushed.canPush == false)
        #expect(pushed.needsCreateForm)

        let ahead = makeModel(items: [item(branch: "feature", ahead: 2)])
        await ahead.reload()
        #expect(ahead.canPush)

        let unpushed = makeModel(items: [item(branch: "feature", ahead: nil)])
        await unpushed.reload()
        #expect(unpushed.canPush)

        let open = makeModel(items: [item(branch: "feature", ahead: 1)])
        open.fetchList = { _, _ in [summary(7, head: "feature")] }
        await open.reload()
        #expect(open.needsCreateForm == false)

        let merged = makeModel(items: [item(branch: "feature", ahead: 1)])
        merged.fetchList = { _, _ in [summary(7, head: "feature", state: "MERGED")] }
        await merged.reload()
        #expect(merged.needsCreateForm)

        let elsewhere = makeModel()
        #expect(elsewhere.canPush == false)
        #expect(elsewhere.needsCreateForm == false)
    }

    @Test
    func `pushing dims the button until new commits arrive`() async {
        let model = makeModel(items: [item(branch: "feature", ahead: 2)])
        await model.reload()
        #expect(model.canPush)

        #expect(await model.push())
        #expect(model.isPushed)
        #expect(model.canPush == false)
        #expect(model.status == "Pushed.")

        // New commits move the tip, which is what a push has to
        // send again; the signature read the change kicks off is
        // what Push then waits on.
        model.fetchTipCommit = { _ in "amended" }
        model.items = [item(branch: "feature", ahead: 1)]
        #expect(model.canPush == false)
        await model.reload()
        #expect(model.canPush)
    }

    @Test
    func `a count gathered before the push cannot unpush the branch`() async {
        let model = makeModel(items: [item(branch: "feature", ahead: 1)])
        await model.reload()
        #expect(await model.push())
        #expect(model.canPush == false)
        #expect(model.isFullyPushed)

        // The sidebar's reading was in flight while the push ran, so
        // it still says one commit is unpushed. Push and Open PR both
        // stay as the push left them rather than swapping over until
        // the next reading lands.
        model.items = [item(branch: "feature", ahead: 1)]
        await model.reload()
        #expect(model.canPush == false)
        #expect(model.isFullyPushed)

        // And the reading that has caught up changes nothing either.
        model.items = [item(branch: "feature", ahead: 0)]
        await model.reload()
        #expect(model.canPush == false)
        #expect(model.isFullyPushed)
    }

    @Test
    func `push waits until the tip's signature is verified`() async {
        let model = makeModel(items: [item(branch: "feature", ahead: 2)])
        #expect(model.canPush == false)
        #expect(model.pushHelp.contains("Checking"))
        await model.reload()
        #expect(model.canPush)
    }

    @Test
    func `a tip that lost its signature never errors the push`() async {
        let model = makeModel(items: [item(branch: "feature", ahead: 2)])
        await model.reload()
        #expect(model.canPush)

        // Amended outside the app between the last read and the
        // click: the push re-reads the signature, declines quietly
        // and never reaches the remote.
        model.checkTipSigned = { _ in false }
        var pushed = false
        model.performPush = { _ in
            pushed = true
            return .origin
        }
        #expect(await model.push())
        #expect(pushed == false)
        #expect(model.canPush == false)
        #expect(model.status?.contains("unsigned") == true)
    }

    @Test
    func `an unsigned tip dims Push and explains itself`() async {
        let model = makeModel(items: [item(branch: "feature", ahead: 2)])
        model.checkTipSigned = { _ in false }
        await model.reload()
        #expect(model.canPush == false)
        #expect(model.pushHelp.contains("not GPG signed"))

        model.checkTipSigned = { _ in true }
        await model.reload()
        #expect(model.canPush)
    }

    @Test
    func `an unsigned tip with nothing to push reads as pushed`() async {
        let model = makeModel(items: [item(branch: "feature", ahead: 0)])
        model.checkTipSigned = { _ in false }
        await model.reload()
        #expect(model.pushHelp.contains("already pushed"))
    }

    @Test
    func `a tip that could not be read leaves the push mark alone`() async {
        let model = makeModel(items: [item(branch: "feature", ahead: 1)])
        await model.reload()
        #expect(await model.push())
        #expect(model.isPushed)

        // git answered nothing, which says the branch has moved
        // nowhere: taking that as a moved tip relit Push exactly as
        // the stale counts this mark exists to survive used to.
        model.fetchTipCommit = { _ in nil }
        model.items = [item(branch: "feature", ahead: 1)]
        await model.reload()
        #expect(model.canPush == false)
        #expect(model.isFullyPushed)

        // A tip that reads, and differs, still unpushes it.
        model.fetchTipCommit = { _ in "moved" }
        await model.reload()
        #expect(model.canPush)
    }

    @Test
    func `a failed push reports rather than dimming`() async {
        let model = makeModel(items: [item(branch: "feature", ahead: 2)])
        await model.reload()
        model.performPush = { _ in throw CocoaError(.fileNoSuchFile) }
        #expect(await model.push() == false)
        #expect(model.canPush)
    }
}
