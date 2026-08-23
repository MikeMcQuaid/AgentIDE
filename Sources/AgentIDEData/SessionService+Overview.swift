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

    /// `pid ppid %cpu rss`: the `ps` listing's fields.
    static let psFields = 4
    static let psCPUField = 2
    static let psRSSField = 3
}

// MARK: - Session overviews

/// The session manager's listing with resource usage.
public extension SessionService {
    /// Every agent session with its working directory and the
    /// resource usage of its pane's process tree.
    func sessionOverviews() async -> [SessionOverview] {
        let panes = await (try? herdr.panes()) ?? []
        let listing = try? await processes.run(
            ["ps", "-axo", "pid=,ppid=,%cpu=,rss="],
            workingDirectory: nil,
            environment: [:],
        )
        let samples = Self.processSamples(fromPS: listing?.standardOutput ?? "")
        var seen = Set<String>()
        var overviews = [SessionOverview]()
        for pane in panes where seen.insert(pane.sessionName).inserted {
            let pid = await herdr.shellPID(paneID: pane.paneID)
            let usage = pid.map { Self.treeUsage(root: $0, samples: samples) } ?? (0, 0)
            overviews.append(SessionOverview(
                name: pane.sessionName,
                workingDirectory: pane.currentPath,
                cpuPercent: usage.0,
                memoryMegabytes: usage.1,
            ))
        }
        return overviews
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
    }

    /// Parses `ps -axo pid=,ppid=,%cpu=,rss=` output.
    static func processSamples(fromPS output: String) -> [ProcessSample] {
        output.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count == OverviewLayout.psFields,
                  let pid = Int(fields[0]),
                  let parent = Int(fields[1]),
                  let cpu = Double(fields[OverviewLayout.psCPUField]),
                  let rss = Int(fields[OverviewLayout.psRSSField])
            else {
                return nil
            }

            return ProcessSample(pid: pid, parent: parent, cpuPercent: cpu, residentKilobytes: rss)
        }
    }

    /// Sums CPU and memory over a process and its descendants; an
    /// agent's cost lives in the children its pane spawned.
    static func treeUsage(root: Int, samples: [ProcessSample]) -> (cpuPercent: Double, megabytes: Int) {
        var children = [Int: [ProcessSample]]()
        for sample in samples {
            children[sample.parent, default: []].append(sample)
        }
        let rootSample = samples.first { $0.pid == root }
        var cpu = rootSample?.cpuPercent ?? 0
        var kilobytes = rootSample?.residentKilobytes ?? 0
        var frontier = [root]
        var visited = Set<Int>()
        while let pid = frontier.popLast() {
            guard visited.insert(pid).inserted else {
                continue
            }

            for child in children[pid] ?? [] where visited.contains(child.pid) == false {
                cpu += child.cpuPercent
                kilobytes += child.residentKilobytes
                frontier.append(child.pid)
            }
        }
        return (cpu, kilobytes / OverviewLayout.kilobytesPerMegabyte)
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
