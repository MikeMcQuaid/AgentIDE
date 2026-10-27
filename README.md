# 🪪 AgentIDE

![The worktree sidebar, an agent's terminal and its review beside it](docs/screenshot.png)

AgentIDE runs sandboxed AI coding agents in parallel `git` worktrees, from prompt to merged pull request, in one native macOS app.
Built with SwiftUI on top of [sandvault](https://github.com/webcoyote/sandvault), [`herdr`](https://herdr.dev) and the [`gh`](https://cli.github.com) CLI.

## 💡 Motivation

My agentic coding setup, described in [Sandboxes and Worktrees: My secure Agentic AI Setup](https://mikemcquaid.com/sandboxed-agent-worktrees-my-coding-and-ai-setup-in-2026/), spanned four apps: an agent and worktree manager, a `git` GUI, a code editor and a terminal.
AgentIDE replaces all four with one app designed around the same workflow.

## ✨ Features

- Runs Claude Code or Codex CLI in parallel worktrees, sandboxed away from your personal files and credentials.
- Starts tasks from prompts, GitHub issues, pull requests or security advisories.
- Schedules repository prompts daily, weekly or monthly while AgentIDE is open.
- Tracks agents, pull requests and blockers by repository or status, with bulk worktree actions and completion notifications.
- Keeps agents running when the app closes and conversations browsable and resumable after their worktrees are deleted.
- Reviews syntax-highlighted diffs with inline comments and AI feedback from another agent, Copilot or CodeRabbit.
- Runs review and autofix loops for local findings, GitHub feedback and failing CI, with automatic pushing off by default.
- Edits code with syntax highlighting, search and change tracking alongside multiple shell tabs per worktree.
- Commits changes and opens pull requests with rebasing, signing and pushing as needed, plus stacks, automerge and merge cleanup.
- Starts and steers work through Shortcuts, Siri and an [iPhone companion](#-iphone-companion).

## 🚫 Out of Scope

One developer, one Mac: no Windows, Linux, multi-user or hosted support.
Bring your own agent CLI and sandboxed non-admin user; no marketplace, bundled models, built-in updater or Mac App Store build.

## 📋 Requirements

- An Apple silicon Mac running macOS Tahoe (26) or later.
- [Homebrew](https://brew.sh), with Git, [`gh`](https://cli.github.com), [`herdr`](https://herdr.dev) and [ripgrep](https://github.com/BurntSushi/ripgrep) installed.
- [sandvault](https://github.com/webcoyote/sandvault) 1.29 or later, which creates the sandbox user and the shared workspace.
- [`gh`](https://cli.github.com) authenticated as you; it stays with your user and agents never see it.
- Claude Code or Codex CLI installed and signed in inside sandvault.
- Xcode 27 or later, only to build from source.

## 📦 Installation

```bash
brew install --cask agentide
```

Update with `brew upgrade`, or unzip a signed [release](https://github.com/MikeMcQuaid/AgentIDE/releases) into /Applications.

To run the current source, use `script/bootstrap` then `script/install`.

## ⚙️ Configuration

Settings (Cmd-,) controls:

- **General**: Choose session defaults, signing and the browser.
- **Schedules**: Manage recurring repository jobs or start them now.
- **Sessions**: Inspect and stop agents and browser pages.
- **Review**: Choose reviewers, models, effort and review or fix prompts.
- **Notifications**: Choose notifications, Dock badges and sounds.
- **Fonts**: Customise fonts and sizes.
- **Editor**: Choose the external editor opened with Cmd-click.
- **Advanced**: Set paths, refresh intervals, idle sleep and logging.

Use `agentide .` to select a worktree or `agentide /some/file` to open a file.
To use AgentIDE as your editor inside its shell panes, add this to your shell configuration:

```bash
if [ -n "${AGENTIDE}" ]; then
  export EDITOR="$(command -v agentide) --wait"
  export VISUAL="${EDITOR}"
fi
```

## 🛠️ Development

Use `script/build`, `script/test`, `script/style --fix` and `script/analyze` for [development](ARCHITECTURE.md#dependencies-and-toolchain).
See the [release process](ARCHITECTURE.md#releases) for publishing.

## 📱 iPhone companion

- Views and steers running agents on your Mac over SSH.
- Starts tasks and manages blockers from your iPhone.

Requires iOS 26 or later; run `script/bootstrap` and `script/install` on your Mac, then choose a signing team in Xcode and build `AgentIDE-iOS`.

1. Copy the public key from iPhone Settings to your Mac's clipboard, then install it for the sandbox user:

   ```bash
   mkdir -p ~/.config/codeofhonor/sandvault/authorized_keys.d
   pbpaste >~/.config/codeofhonor/sandvault/authorized_keys.d/agentide-phone
   sv build
   ```

   This needs sandvault 1.29 or later; deleting that file and running `sv build` again revokes the key.

2. Add this to `/etc/ssh/sshd_config.d/000-agentide.conf`, replacing `<you>` with your username and adjusting the workspace path, then enable Remote Login for `sandvault-<you>`:

   ```text
   Match User sandvault-<you>
       SetEnv SHARED_WORKSPACE=/Users/Shared/sv-<you>
   ```

3. In the iPhone app, enter your Mac's address and username; it adds `sandvault-` automatically.
   Use port `22` unless changed and select `agentide` for the installed app or `agentide-dev` for development.
   Choose **Connect** and verify the host key against `ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub` on your Mac.
   A changed key must be explicitly replaced in Settings.

### TestFlight releases

Create an iOS record and App Store Connect profile for `com.mikemcquaid.AgentIDE` with your Apple Distribution certificate.
Base64-encode it as secret `AGENTIDE_APP_STORE_IOS_PROFILE`; reuse `APP_STORE_CERTIFICATES`, `APP_STORE_CERTIFICATES_PASSWORD` and `NOTARIZATION_*`.
Push a change to `script/testflight` or another Release `push.paths` input for a dry run.
Once it passes, merge and run **Release** on `main` with a new version.
After Apple's checks, join an internal TestFlight group.

## 🚧 Status

Stable but changing regularly.
AgentIDE is being designed exclusively for [@MikeMcQuaid](https://github.com/MikeMcQuaid)'s personal workflow; nothing here promises to suit anyone else's, interfaces and behaviour may break without notice and there is no support.

## 📮 Contact

[Mike McQuaid](mailto:mike@mikemcquaid.com)

## 📄 Licence

[AGPL-3.0](LICENSE).
If you reuse or adapt the source the AGPL terms apply, including the network-use clause.

[Octicons](https://github.com/primer/octicons) are vendored in `App/Assets.xcassets` and licensed under the [MIT License](https://github.com/primer/octicons/blob/main/LICENSE).
