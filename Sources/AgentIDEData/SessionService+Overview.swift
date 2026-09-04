import AgentIDEDomain
import Foundation

// MARK: - SessionOverview

/// One agent session for the manager: where it lives and what it
/// costs right now.
public struct SessionOverview: Hashable, Sendable {
    /// The session name, the workspace's label.
    public let name: String

    /// The pane's working directory, locating the worktree.
    public let workingDirectory: String

    /// The pane's process tree's summed CPU percentage.
    public let cpuPercent: Double

    /// The pane's process tree's summed resident memory.
    public let memoryMegabytes: Int
}

// MARK: - OverviewLayout

/// The listing's parsing constants; extensions cannot store them.
private enum OverviewLayout {
    /// Kilobytes per megabyte, for `ps` rss conversion.
    static let kilobytesPerMegabyte = 1_024

    /// `pid ppid %cpu rss comm`: the `ps` listing's fields. The
    /// command comes last because it is the one that can hold
    /// spaces, so the split stops before it.
    static let psFields = 5
    static let psCPUField = 2
    static let psRSSField = 3
    static let psCommandField = 4
}

// MARK: - Session overviews

/// The session manager's listing with resource usage.
public extension SessionService {
    /// Every agent session with its working directory and the
    /// resource usage of its pane's process tree.
    func sessionOverviews() async -> [SessionOverview] {
        let panes = await (try? herdr.panes()) ?? []
        let listing = try? await processes.run(
            ["ps", "-axo", "pid=,ppid=,%cpu=,rss=,comm="],
            workingDirectory: nil,
            environment: [:],
        )
        let samples = Self.processSamples(fromPS: listing?.standardOutput ?? "")
        var seen = Set<String>()
        var overviews = [SessionOverview]()
        for pane in panes where seen.insert(pane.sessionName).inserted {
            let pid = await herdr.shellPID(paneID: pane.paneID)
            let usage = pid.map { Self.treeUsage(root: $0, samples: samples) }
            overviews.append(SessionOverview(
                name: pane.sessionName,
                workingDirectory: pane.currentPath,
                cpuPercent: usage?.cpuPercent ?? 0,
                memoryMegabytes: usage?.megabytes ?? 0,
            ))
        }
        return overviews
    }

    /// What every pane's process tree is costing, keyed by the
    /// pane's working directory, for the rows that stand for those
    /// worktrees. One `ps` for the machine and, once per pane ever,
    /// one herdr call for the shell it runs: a pane's shell never
    /// changes, so a steady state pays for the `ps` alone.
    ///
    /// Only trees that have been busy a while come back, which is
    /// the point: a runaway in one worktree starves every other, and
    /// nothing on screen said which one or what it was running.
    func paneLoads() async -> [String: PaneLoad] {
        let panes = await panesOrLastAnswer()
        guard panes.isEmpty == false else {
            return [:]
        }

        let listing = try? await processes.run(
            ["ps", "-axo", "pid=,ppid=,%cpu=,rss=,comm="],
            workingDirectory: nil,
            environment: [:],
        )
        let samples = Self.processSamples(fromPS: listing?.standardOutput ?? "")
        var loads = [String: PaneLoad]()
        for pane in panes {
            guard let shell = await shellPID(of: pane) else {
                continue
            }

            let usage = Self.treeUsage(root: shell, samples: samples)
            let load = paneLoadCache.reading(
                percent: usage.cpuPercent,
                busiest: usage.busiest,
                of: pane.currentPath,
            )
            if let load, load.isHeavy() {
                loads[pane.currentPath] = load
            }
        }
        paneLoadCache.forgetAll(except: Set(panes.map(\.currentPath)))
        return loads
    }

    /// A pane's shell process, asked for once and remembered: it
    /// lives as long as the pane does.
    private func shellPID(of pane: HerdrPane) async -> Int? {
        if let known = paneLoadCache.shell(of: pane.paneID) {
            return known
        }

        guard let shell = await herdr.shellPID(paneID: pane.paneID) else {
            return nil
        }

        paneLoadCache.remember(shell: shell, of: pane.paneID)
        return shell
    }

    /// The usage of processes the app runs itself rather than herdr,
    /// a browser page's web content process above all, in one `ps`
    /// pass so a list of them costs no more than one session does.
    func usage(ofProcesses identifiers: [Int32]) async -> [Int32: (cpuPercent: Double, memoryMegabytes: Int)] {
        guard identifiers.isEmpty == false else {
            return [:]
        }

        let listing = try? await processes.run(
            ["ps", "-axo", "pid=,ppid=,%cpu=,rss="],
            workingDirectory: nil,
            environment: [:],
        )
        let samples = Self.processSamples(fromPS: listing?.standardOutput ?? "")
        var usage = [Int32: (cpuPercent: Double, memoryMegabytes: Int)]()
        for identifier in identifiers {
            let tree = Self.treeUsage(root: Int(identifier), samples: samples)
            usage[identifier] = (tree.cpuPercent, tree.megabytes)
        }
        return usage
    }

    // MARK: Internal

    /// One `ps` row of the fields the usage sums need.
    struct ProcessSample: Hashable, Sendable {
        let pid: Int
        let parent: Int
        let cpuPercent: Double
        let residentKilobytes: Int
        let command: String
    }

    /// Parses `ps -axo pid=,ppid=,%cpu=,rss=,comm=` output.
    static func processSamples(fromPS output: String) -> [ProcessSample] {
        output.split(separator: "\n").compactMap { line in
            let fields = line.split(
                separator: " ",
                maxSplits: OverviewLayout.psFields - 1,
                omittingEmptySubsequences: true,
            )
            guard fields.count == OverviewLayout.psFields,
                  let pid = Int(fields[0]),
                  let parent = Int(fields[1]),
                  let cpu = Double(fields[OverviewLayout.psCPUField]),
                  let rss = Int(fields[OverviewLayout.psRSSField])
            else {
                return nil
            }

            return ProcessSample(
                pid: pid,
                parent: parent,
                cpuPercent: cpu,
                residentKilobytes: rss,
                command: String(fields[OverviewLayout.psCommandField]),
            )
        }
    }

    /// What one pane's process tree costs: an agent's cost lives in
    /// the children its pane spawned, and so does the answer to what
    /// it is doing.
    struct TreeUsage: Hashable, Sendable {
        let cpuPercent: Double
        let megabytes: Int
        /// The heaviest process in the tree, named without its path.
        let busiest: String
    }

    /// Sums CPU and memory over a process and its descendants, and
    /// names the heaviest of them.
    static func treeUsage(root: Int, samples: [ProcessSample]) -> TreeUsage {
        var children = [Int: [ProcessSample]]()
        for sample in samples {
            children[sample.parent, default: []].append(sample)
        }
        let rootSample = samples.first { $0.pid == root }
        var cpu = rootSample?.cpuPercent ?? 0
        var kilobytes = rootSample?.residentKilobytes ?? 0
        var busiest = rootSample
        var frontier = [root]
        var visited = Set<Int>()
        while let pid = frontier.popLast() {
            guard visited.insert(pid).inserted else {
                continue
            }

            for child in children[pid] ?? [] where visited.contains(child.pid) == false {
                cpu += child.cpuPercent
                kilobytes += child.residentKilobytes
                if child.cpuPercent > (busiest?.cpuPercent ?? 0) {
                    busiest = child
                }
                frontier.append(child.pid)
            }
        }
        return TreeUsage(
            cpuPercent: cpu,
            megabytes: kilobytes / OverviewLayout.kilobytesPerMegabyte,
            busiest: busiest.map { URL(filePath: $0.command).lastPathComponent } ?? "",
        )
    }

    /// Whether a session still exists on the server.
    internal func sessionExists(name: String) async -> Bool {
        let panes = await (try? herdr.panes()) ?? []
        return panes.contains { $0.sessionName == name }
    }

    /// The bare branch name of a base ref: only the known remote and
    /// ref prefixes come off, so a default branch that itself
    /// contains slashes (`release/2026`) survives intact where
    /// splitting on `/` would have left `2026`.
    internal static func branchName(fromBaseRef baseRef: String) -> String {
        for prefix in ["refs/remotes/origin/", "refs/heads/", "origin/"] where baseRef.hasPrefix(prefix) {
            return String(baseRef.dropFirst(prefix.count))
        }
        return baseRef
    }
}
