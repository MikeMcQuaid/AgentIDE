@testable import AgentIDEData
import Testing

/// Reading `ps` into a pane's cost: what the tree sums to and which
/// process in it is doing the work.
struct ProcessSampleTests {
    @Test
    func `a tree sums its descendants and names the heaviest`() {
        // A pane's shell, the agent under it and the linter the agent
        // ran, which is where the machine actually went.
        let listing = """
        100 1 0.4 2048 /bin/zsh
        200 100 3.1 500000 /opt/homebrew/bin/claude
        300 200 707.0 20608 /opt/homebrew/bin/actionlint
        400 1 90.0 784000 /usr/bin/ruby
        """
        let samples = SessionService.processSamples(fromPS: listing)
        #expect(samples.count == 4)

        let usage = SessionService.treeUsage(root: 100, samples: samples)
        // The unrelated ruby belongs to another pane and stays out.
        #expect(Int(usage.cpuPercent) == 710)
        #expect(usage.busiest == "actionlint")
        #expect(usage.megabytes == 510)
    }

    @Test
    func `a command with spaces in its path survives the split`() {
        let listing = "1 0 2.0 1024 /Applications/My App.app/Contents/MacOS/My App"
        let samples = SessionService.processSamples(fromPS: listing)
        #expect(samples.first?.command == "/Applications/My App.app/Contents/MacOS/My App")

        let usage = SessionService.treeUsage(root: 1, samples: samples)
        #expect(usage.busiest == "My App")
    }

    @Test
    func `a pane whose shell has gone costs nothing`() {
        let samples = SessionService.processSamples(fromPS: "1 0 2.0 1024 /bin/zsh")
        let usage = SessionService.treeUsage(root: 999, samples: samples)

        #expect(usage.cpuPercent == 0)
        #expect(usage.busiest.isEmpty)
    }
}
