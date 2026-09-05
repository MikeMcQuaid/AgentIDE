@testable import AgentIDEDomain
import Testing

/// What a remote's URL says about the repository behind it.
struct GitHubRemoteTests {
    @Test
    func `both of GitHub's own URL forms name the same repository`() {
        #expect(GitHubRemote.fullName(ofURL: "https://github.com/Homebrew/brew") == "Homebrew/brew")
        #expect(GitHubRemote.fullName(ofURL: "https://github.com/aholland/brew.git") == "aholland/brew")
        #expect(GitHubRemote.fullName(ofURL: "git@github.com:Homebrew/brew.git") == "Homebrew/brew")
        #expect(GitHubRemote.owner(ofURL: "git@github.com:aholland/brew.git") == "aholland")
    }

    @Test
    func `anywhere but GitHub names nothing`() {
        #expect(GitHubRemote.fullName(ofURL: "https://gitlab.com/owner/name") == nil)
        #expect(GitHubRemote.fullName(ofURL: "https://github.com/Homebrew") == nil)
        #expect(GitHubRemote.owner(ofURL: "") == nil)

        // A host that merely reads like GitHub's is somebody
        // else's, and a push aimed there would be a push aimed at
        // a stranger.
        #expect(GitHubRemote.fullName(ofURL: "https://evilgithub.com/Homebrew/brew") == nil)
        #expect(GitHubRemote.fullName(ofURL: "https://github.com.example.org/Homebrew/brew") == nil)
        #expect(GitHubRemote.fullName(ofURL: "git@notgithub.com:Homebrew/brew.git") == nil)
        // Its own forms, however they are written, still count.
        #expect(GitHubRemote.fullName(ofURL: "ssh://git@github.com/Homebrew/brew.git") == "Homebrew/brew")
    }

    @Test
    func `a configured remote is told from a URL`() {
        // What `gh pr checkout` writes for a pull request from a
        // fork, against what it writes for one of your own.
        #expect(GitHubRemote.isURL("https://github.com/aholland/brew.git"))
        #expect(GitHubRemote.isURL("git@github.com:aholland/brew.git"))
        #expect(GitHubRemote.isURL("origin") == false)
        #expect(GitHubRemote.isURL("aholland") == false)
    }
}
