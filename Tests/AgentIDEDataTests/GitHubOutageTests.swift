import AgentIDEData
import Testing

/// Pins which failures count as an outage. The classification has
/// to stay narrow: an outage is announced once and then waited out
/// quietly, so anything misfiled as one goes unheard.
struct GitHubOutageTests {
    @Test
    func `github's own failures read as an outage`() {
        let outages = [
            "gh pr list failed (1): HTTP 503: No server is currently available to service your request.",
            "HTTP 502: Bad gateway (https://api.github.com/graphql)",
            "gh api failed (1): HTTP 500: Internal server error",
            "error connecting to api.github.com: operation timed out",
            // gh's own wording when the machine has no route out,
            // which arrives with no other marker in it at all.
            """
            gh api repos/Homebrew/brew/pulls?state=all failed (1): error connecting to api.github.com
            check your internet connection or https://githubstatus.com
            """,
            "could not resolve host: api.github.com",
            "The Internet connection appears to be offline.",
        ]
        for message in outages {
            #expect(GitHubOutage.isLikely(message), "\(message.prefix(40))")
        }
    }

    @Test
    func `real failures stay real`() {
        let failures = [
            "gh pr create failed (1): pull request already exists for branch",
            "HTTP 404: Not Found (https://api.github.com/repos/x/y)",
            "HTTP 401: Bad credentials",
            "gh auth status failed (1): You are not logged into any GitHub hosts",
            "! [rejected] main -> main (non-fast-forward)",
            "The tip commit is not GPG signed",
        ]
        for message in failures {
            #expect(GitHubOutage.isLikely(message) == false, "\(message.prefix(40))")
        }
    }
}
