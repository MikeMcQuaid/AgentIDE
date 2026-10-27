import AgentIDEDomain
import Foundation

public extension RemoteHerdr {
    /// Sends one idempotent metadata edit or picker request, awaiting host acknowledgement.
    func sidebarRequest(_ request: SidebarRequest) async throws -> SidebarResponse {
        let data = try JSONEncoder().encode(request)
        guard data.count <= SidebarRequest.maximumBytes, let input = String(data: data, encoding: .utf8) else {
            throw RemoteError("The blocker is too long.")
        }

        let output = try await connection.execute(
            configuration.command([
                "/bin/sh", "-c", Self.sidebarRequestScript, "agentide-sidebar", UUID().uuidString,
            ]),
            input: input,
        )
        return try JSONDecoder().decode(SidebarResponse.self, from: Data(output.utf8))
    }

    // MARK: Internal

    internal static let sidebarRequestScript = #"""
    set -eu
    directory="${SHARED_WORKSPACE:-/Users/Shared/sv-${USER#sandvault-}}/agentide/sidebar-requests-${HERDR_SESSION}"
    mkdir -p "$directory"
    request_file="$directory/$1"
    trap 'rm -f "$request_file.partial" "$request_file.request" "$request_file.response"' EXIT
    cat >"$request_file.partial"
    mv "$request_file.partial" "$request_file.request"
    # SSH has no file notification channel; this short-lived request waits only for its reply.
    attempt=0
    while [ "$attempt" -lt 60 ]; do
      if [ -f "$request_file.response" ]; then
        cat "$request_file.response"
        exit
      fi
      sleep 0.5
      attempt=$((attempt + 1))
    done
    echo 'The Mac did not confirm this request. Open AgentIDE on the Mac, refresh and try again.' >&2
    exit 1
    """#
}
