import Foundation
import SanductorDomain

extension RemoteHerdr {
    static func worktreeVersions(in snapshot: HerdrSnapshot) -> [String: [String]] {
        let workspaces = Set(snapshot.workspaces.filter { SessionName.isSanductor($0.label) }.map(\.workspaceID))
        var versions = [String: [String]]()
        for pane in snapshot.panes.sorted(by: { $0.paneID < $1.paneID }) {
            guard workspaces.contains(pane.workspaceID), let path = pane.directory else {
                continue
            }

            versions[path, default: []].append(pane.paneID + ":" + (pane.agent ?? "") + ":" + (pane.agentStatus ?? ""))
        }
        return versions
    }

    static func worktreeStatusCommand(paths: [String]) -> [String] {
        let command = (["git", "--no-optional-locks", "-c", "core.fsmonitor=false"]
            + GitWorktreeStatus.arguments.filter { $0 != "-z" } + ["--branch"])
            .map(SSHConfiguration.quote)
            .joined(separator: " ")
        let script = """
        set -o pipefail
        for directory do
          if summary=$(cd -- "$directory" && \(command) | LC_ALL=C /usr/bin/awk '
            $1 == "#" && $2 == "branch.head" { branch = $3 == "(detached)" ? "" : $3 }
            $1 == "#" && $2 == "branch.ab" { ahead = substr($3, 2); behind = substr($4, 2) }
            /^[12u?] / { dirty = 1 }
            END { printf "%s\\t%s\\t%s\\t%d", branch, ahead, behind, dirty }
          ') 2>/dev/null; then
            printf '%s\\n' "$summary"
          else
            printf '\\n'
          fi
        done
        """
        return ["/bin/bash", "-c", script, "sanductor-status"] + paths
    }

    static func parseWorktreeStatuses(_ output: String, paths: [String]) -> [String: GitWorktreeStatus] {
        var statuses = [String: GitWorktreeStatus]()
        for (path, record) in zip(paths, output.components(separatedBy: "\n")) {
            var fields = record.split(separator: "\t", omittingEmptySubsequences: false).makeIterator()
            guard let branch = fields.next(), let ahead = fields.next(), let behind = fields.next(),
                  let dirty = fields.next(), fields.next() == nil, dirty == "0" || dirty == "1"
            else {
                continue
            }

            statuses[path] = GitWorktreeStatus(
                branch: branch.isEmpty ? nil : String(branch),
                isDirty: dirty == "1",
                aheadOfUpstream: Int(ahead),
                behindUpstream: Int(behind),
            )
        }
        return statuses
    }
}

// MARK: - RemoteWorktree

struct RemoteWorktree {
    let version: [String]
    let status: GitWorktreeStatus?
}
