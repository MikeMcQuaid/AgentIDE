// MARK: - SessionOverview

/// One tmux session for the manager: where it lives and what it
/// costs right now.
public struct SessionOverview: Hashable, Sendable {
    /// The tmux session name.
    public let name: String

    /// Whether the session is a host shell rather than an agent.
    public let isHostShell: Bool

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
    /// `session|pid|path`: the host pane listing's fields.
    static let hostPaneFields = 3
    static let hostPanePathField = 2
    static let hostPanePidField = 1

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
    /// Every AgentIDE tmux session with its working directory and
    /// the resource usage of its pane's process tree.
    func sessionOverviews() async -> [SessionOverview] {
        var panes = [(name: String, isHostShell: Bool, path: String, pid: Int?)]()
        for pane in await (try? tmux.panes()) ?? [] {
            panes.append((pane.sessionName, false, pane.currentPath, pane.pid))
        }
        let host = try? await processes.run(
            [Self.hostTmuxPath, "list-panes", "-a", "-F", "#{session_name}|#{pane_pid}|#{pane_current_path}"],
            workingDirectory: nil,
            environment: [:],
        )
        for line in (host?.standardOutput ?? "").split(separator: "\n") {
            let fields = line.split(
                separator: "|",
                maxSplits: OverviewLayout.hostPaneFields - 1,
                omittingEmptySubsequences: false,
            )
            guard fields.count == OverviewLayout.hostPaneFields,
                  fields[0].hasPrefix(Self.hostShellPrefix)
            else {
                continue
            }

            panes.append((
                String(fields[0]),
                true,
                String(fields[OverviewLayout.hostPanePathField]),
                Int(fields[OverviewLayout.hostPanePidField]),
            ))
        }

        let listing = try? await processes.run(
            ["ps", "-axo", "pid=,ppid=,%cpu=,rss="],
            workingDirectory: nil,
            environment: [:],
        )
        let samples = Self.processSamples(fromPS: listing?.standardOutput ?? "")
        var seen = Set<String>()
        return panes.compactMap { pane in
            guard seen.insert(pane.name).inserted else {
                return nil
            }

            let usage = pane.pid.map { Self.treeUsage(root: $0, samples: samples) } ?? (0, 0)
            return SessionOverview(
                name: pane.name,
                isHostShell: pane.isHostShell,
                workingDirectory: pane.path,
                cpuPercent: usage.0,
                memoryMegabytes: usage.1,
            )
        }
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

    /// The pane process ids of one session, for kill escalation.
    internal func panePIDs(sessionName: String, isHostShell: Bool) async -> [Int] {
        if isHostShell {
            let host = try? await processes.run(
                [Self.hostTmuxPath, "list-panes", "-t", sessionName, "-F", "#{pane_pid}"],
                workingDirectory: nil,
                environment: [:],
            )
            return (host?.standardOutput ?? "").split(separator: "\n").compactMap { Int($0) }
        }
        let panes = await (try? tmux.panes()) ?? []
        return panes.filter { $0.sessionName == sessionName }.compactMap(\.pid)
    }

    /// Issues the polite tmux kill on whichever server owns the
    /// session.
    internal func issueKill(name: String, isHostShell: Bool) async {
        if isHostShell {
            _ = try? await processes.run(
                [Self.hostTmuxPath, "kill-session", "-t", name],
                workingDirectory: nil,
                environment: [:],
            )
        } else {
            try? await tmux.killSession(name: name)
        }
    }

    /// Whether a session still exists on its server.
    internal func sessionExists(name: String, isHostShell: Bool) async -> Bool {
        if isHostShell {
            let list = try? await processes.run(
                [Self.hostTmuxPath, "ls", "-F", "#{session_name}"],
                workingDirectory: nil,
                environment: [:],
            )
            return (list?.standardOutput ?? "").split(separator: "\n").contains { $0 == name }
        }
        let panes = await (try? tmux.panes()) ?? []
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
