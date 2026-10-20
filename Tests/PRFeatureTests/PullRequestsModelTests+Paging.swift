import AgentIDEData
@testable import PRFeature
import Synchronization
import Testing

/// A page fetch and a reload that overtakes it.
extension PullRequestsModelTests {
    @Test
    func `a page fetch a reload overtook leaves the loading state to the reload`() async {
        let race = await overtakenPageFetch()
        race.releasePage.yield()
        await race.paging.value
        #expect(race.model.isLoading)
        #expect(race.model.page == 0)

        race.releaseReload.yield()
        await race.reloading.value
        #expect(race.model.isLoading == false)
    }

    @Test
    func `a page fetch a reload overtook leaves the reload's rows`() async {
        let race = await overtakenPageFetch()
        race.releaseReload.yield()
        await race.reloading.value
        race.releasePage.yield()
        await race.paging.value
        #expect(race.model.summaries.count == GitHubClient.listLimit)
        #expect(race.model.fetchedLimit == GitHubClient.listLimit)
    }

    /// A full first page, then Next's fetch and a reload both held
    /// in flight until the test releases each.
    private func overtakenPageFetch() async -> OvertakenPageFetch {
        let model = makeModel()
        let (pageGate, releasePage) = AsyncStream<Void>.makeStream()
        let (reloadGate, releaseReload) = AsyncStream<Void>.makeStream()
        let (asked, ask) = AsyncStream<Int>.makeStream()
        let holding = Mutex(false)
        model.fetchList = { _, limit in
            if holding.withLock({ $0 }) {
                ask.yield(limit)
                for await _ in limit == GitHubClient.listLimit ? reloadGate : pageGate {
                    break
                }
            }
            return (1 ... limit).map { self.summary($0, head: "branch-\($0)") }
        }
        await model.reload()
        holding.withLock { $0 = true }
        var asks = asked.makeAsyncIterator()

        let paging = Task {
            await model.showNextPage()
        }
        _ = await asks.next()
        let reloading = Task {
            await model.reload()
        }
        _ = await asks.next()
        return OvertakenPageFetch(
            model: model,
            releasePage: releasePage,
            releaseReload: releaseReload,
            paging: paging,
            reloading: reloading,
        )
    }
}

// MARK: - OvertakenPageFetch

/// The model and the two fetches `overtakenPageFetch` holds.
private struct OvertakenPageFetch {
    let model: PullRequestsModel
    let releasePage: AsyncStream<Void>.Continuation
    let releaseReload: AsyncStream<Void>.Continuation
    let paging: Task<Void, Never>
    let reloading: Task<Void, Never>
}
