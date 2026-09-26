# 🪪 AgentIDE

![The worktree sidebar, an agent's terminal and its review beside it](docs/screenshot.png)

AgentIDE is a native macOS app for running, prompting and reviewing sandboxed AI coding agents in parallel `git` worktrees, from prompt to reviewed, merged pull request.
Worktrees, conversations, code reviews, pull requests and CI live in one window.
Built with SwiftUI on top of [sandvault](https://github.com/webcoyote/sandvault), [`herdr`](https://herdr.dev) and the [`gh`](https://cli.github.com) CLI.

## 💡 Motivation

My agentic coding setup, described in [Sandboxes and Worktrees: My secure Agentic AI Setup](https://mikemcquaid.com/sandboxed-agent-worktrees-my-coding-and-ai-setup-in-2026/), spanned four apps: an agent and worktree manager, a `git` GUI, a code editor and a terminal.
AgentIDE replaces all four with one app designed around the same workflow.
Agents run inside a separate, non-admin sandvault sandboxed user with no access to sensitive files or credentials, so they can work unattended without endangering the rest of the machine.
Their sessions live in a `herdr` server owned by the same sandbox user, so nothing is lost when the app quits, crashes or updates.

## ✨ Features

- Runs Claude Code or Codex CLI in parallel worktrees, sandboxed away from your personal files and credentials.
- Starts a new task from a prompt, GitHub issue, pull request or security advisory in triage or draft.
- Shows agent activity, pull requests, CI checks and uncommitted changes across repositories in one sidebar.
- Keeps agents running when the app closes and conversations browsable and resumable after their worktrees are deleted.
- Scrolls the agent conversation under the pointer.
- Reviews uncommitted changes, individual commits or whole branches as syntax-highlighted diffs with inline pull request comments.
- Requests reviews from another agent or Copilot and turns review comments and failing CI logs into prompts for fixes.
- Edits code with syntax highlighting, search and change tracking, keeping each worktree's open file and scroll position.
- Runs multiple shell tabs in each worktree for development servers, tests and other commands.
- Commits or amends selected files with messages drafted by Apple's on-device model.
- Pushes, rebases and manages pull requests, including forks and stacked branches.
- Merges or queues pull requests and can automatically remove clean, fully merged worktrees and branches when it observes a merge, leaving the selected worktree and main checkout in place.
- Notifies you when an agent finishes or needs input.
- Starts and steers work from a phone through SSH, Shortcuts and Siri.

## 🚫 Out of Scope

- Windows or Linux support; being a native macOS app is the point.
- Running agents without a sandboxed non-admin user.
- Team, multi-user or hosted features: one developer, one Mac.
- An agent marketplace or bundled models; bring your own agent CLI.
- A native iOS app: SSH into `herdr` from any iOS client instead.
- An updater or a Mac App Store build; Homebrew's cask upgrades it, and the App Store sandbox forbids running agents as another user.

## 📋 Requirements

- macOS Golden Gate (27) or later.
- [Homebrew](https://brew.sh), which installs the rest.
- [sandvault](https://github.com/webcoyote/sandvault), which creates the sandbox user and the shared workspace.
- [`gh`](https://cli.github.com) authenticated as you; it stays with your user and agents never see it.
- [`herdr`](https://herdr.dev) and [`mosh`](https://mosh.org), installed by `script/bootstrap`; `mosh` only matters from a phone.
- Xcode 27 or later, only to build from source.

## 📦 Installation

```bash
brew install --cask agentide
```

The [`agentide` cask](https://github.com/Homebrew/homebrew-cask/blob/main/Casks/a/agentide.rb) installs the latest release, and `brew upgrade` updates it.
Releases are signed with a Developer ID certificate and notarised by Apple.

Without Homebrew, download `AgentIDE-<version>.zip` from the [releases page](https://github.com/MikeMcQuaid/AgentIDE/releases), unzip it and move `AgentIDE.app` to /Applications.

To run the current source instead:

```bash
script/bootstrap
script/install
```

## ⚙️ Configuration

Settings (Cmd-,) controls:

- **General**: Choose session defaults, commit signing requirements and the external browser.
- **Review**: Choose the reviewer and each agent's review model and effort.
- **Notifications**: Choose which events notify, badge the Dock or play a sound.
- **Fonts**: Customise fonts and sizes throughout the app.
- **Editor**: Choose the external editor opened with Cmd-click.
- **Advanced**: Set repository and worktree locations, refresh intervals, idle sleep and performance logging.

Double-click either pane divider to restore that pane's default width.
The right divider and **Resize Panes** give the review pane one-third of the space beside the sidebar and the middle pane two-thirds, subject to their minimum and maximum widths.

A shell pane sets `AGENTIDE=1` and puts the bundled `agentide` command on `PATH`, so shell files can hand editing back to the app:

```bash
if [ -n "${AGENTIDE}" ]; then
  export EDITOR="$(command -v agentide) --wait"
  export VISUAL="${EDITOR}"
fi
```

`agentide .` from any terminal switches the window to the worktree you are in.
`agentide /some/file` opens the file in its worktree's editor.
Both expand the repository and bring AgentIDE to the foreground; a file outside every worktree opens beside the current selection.

## 📱 iPhone SSH access

Agents run as the sandbox user, so anything that can SSH to that user can start and steer them.
[Moshi](https://getmoshi.app) is the iOS client this is currently built around, because it speaks both [`mosh`](https://mosh.org), so a phone changing network keeps its session rather than dropping it, and `herdr`, so it attaches to the same sessions the app does.

1. Put the phone's public key in sandvault's guest template, which is what the sandbox home is built from, then rebuild it.
   A sandvault upgrade replaces the template, so keep this in your dotfiles:

   ```bash
   guest_keys="$(brew --prefix sandvault)/libexec/guest/home/.ssh/authorized_keys"
   cat "${HOME}/Downloads/moshi.pub" >>"${guest_keys}"
   sv --rebuild build
   ```

2. Name the shared workspace for logins from outside the sandbox, which do not inherit it, in `/etc/ssh/sshd_config.d/000-agentide.conf` with your own user name and path in place of `<you>`, then turn on macOS's Remote Login for that account:

   ```text
   Match User sandvault-<you>
       SetEnv SHARED_WORKSPACE=/Users/Shared/sv-<you>
   ```

3. In the sandbox user's shell configuration, name the session and give the new-session command a short alias:

   ```bash
   export HERDR_SESSION=agentide
   alias ain='/Applications/AgentIDE.app/Contents/Resources/bin/agentide new'
   ```

Connect as `sandvault-<you>` and run `herdr`: one attach presents every agent's workspace, and `ain` starts a new session, asking for repository, agent, model, effort and prompt.
A session steered from the phone is the same session the Mac shows.

## 🛠️ Development

- `script/bootstrap`: install `Brewfile` dependencies and generate the Xcode project with XcodeGen
- `script/build`: build the app; `AgentIDE.app` in the repository root symlinks its output
- `script/version`: print the version and build number git says, which scripted and Xcode builds both use
- `script/install`: build, then copy the app to /Applications
- `script/test [--sanitize address|thread]`: unit, integration and App Intents tests, optionally checking memory accesses or data races
- `script/style [--fix]`: SwiftLint and SwiftFormat, every rule on
- `script/analyze`: static analysis and dead code
- `script/zip` and `script/package`: zip, sign and notarise a release
- `script/attach`: attach this terminal to the sandboxed `herdr` session

Project code treats compiler and linker warnings as errors, with Swift's strict concurrency and memory safety checks enabled.
Xcode also runs Apple's static analyser during builds.
`script/analyze` adds SwiftLint's analysis and dead-code detection on the host and CI.
CI also runs the tests under Address Sanitizer.
Thread Sanitizer is available locally; its CI gate awaits a compatible SwiftTerm release fixing a shell-exit race.

Releases run the **Release** workflow from the Actions tab on `main` with a bare `MAJOR.MINOR.PATCH` version.

## 🚧 Status

Stable but changing regularly.
AgentIDE is being designed exclusively for [@MikeMcQuaid](https://github.com/MikeMcQuaid)'s personal workflow; nothing here promises to suit anyone else's, interfaces and behaviour may break without notice and there is no support.

## 📮 Contact

[Mike McQuaid](mailto:mike@mikemcquaid.com)

## 📄 Licence

[AGPL-3.0](LICENSE).
If you reuse or adapt the source the AGPL terms apply, including the network-use clause.

[Octicons](https://github.com/primer/octicons) are vendored in `App/Assets.xcassets` and licensed under the [MIT License](https://github.com/primer/octicons/blob/main/LICENSE).
