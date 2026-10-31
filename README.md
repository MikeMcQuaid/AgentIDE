# 🪪 Sanductor

Sanductor (formerly AgentIDE) is a free, native macOS workspace for running coding agents in parallel, reviewing their work and shipping pull requests.
[sandvault](https://github.com/webcoyote/sandvault) runs all agents under a separate non-admin macOS user with a clean environment, keeping your home directory, GitHub credentials and inherited secrets out of reach even in YOLO mode.

## 💡 Motivation

I lead [Homebrew](https://brew.sh) and treat agent code as untrusted, keeping my credentials and signing keys outside its account.
My [coding workflow](https://mikemcquaid.com/sanductor/) fits in one app, from prompt to merged pull request.
No account, subscription or hosted relay is required.

![The worktree sidebar, an agent's terminal and its review beside it](docs/screenshot.png)

## ✨ Features

- Runs Claude Code or Codex CLI in parallel worktrees, directly on macOS without containers or virtual machines.
- Reviews diffs with comments and a second agent, Copilot or CodeRabbit.
- Fixes reviews, failing CI and upstream merge conflicts locally, resuming feedback watching after relaunch.
- Opens pull requests with commit signing, rebasing, stack pushes, automerge and merge cleanup.
- Keeps agents running when the app closes and conversations browsable and resumable after worktree deletion.
- Starts from prompts, issues, PRs or unpublished security advisories.
- Schedules repository prompts daily, weekly or monthly while open.
- Tracks agents, PRs and blockers by repository or status, with bulk worktree actions and notifications.
- Edits code with highlighting and search alongside worktree shell tabs.
- Starts tasks and checks blockers through Shortcuts and Siri, with an [iPhone companion](#-iphone-companion).

## 📋 Requirements

- An Apple silicon Mac running macOS Tahoe (26) or later.
- [Homebrew](https://brew.sh), with Git, [`gh`](https://cli.github.com), [`herdr`](https://herdr.dev) and [ripgrep](https://github.com/BurntSushi/ripgrep) installed.
- [sandvault](https://github.com/webcoyote/sandvault) 1.29 or later.
- A Claude Code or Codex CLI account.
- Xcode 27.2 or later, only to build from source.

## 📦 Installation

```bash
brew install --cask sanductor
```

Update with `brew upgrade`, or unzip a signed [release](https://github.com/MikeMcQuaid/Sanductor/releases) into /Applications.

### Getting started

Follow Sanductor’s checks; run setup commands in your normal Terminal.
Run `brew install sandvault`, then `sv build` and authorise setup.
This creates the non-admin account `sandvault-<you>` and shared workspace `/Users/Shared/sv-<you>`; `<you>` is your macOS username.
Run `gh auth login` as yourself, then `sv claude` or `sv codex` to sign in to your chosen agent inside the sandbox; quit the agent and click Recheck.
`sv` runs commands as the sandbox account; its agent login is separate from yours.
A short tour explains the three panes after setup succeeds.

Use the left sidebar to add a repository and start an agent in a worktree, a separate checkout for its branch.
Choose repository paths inside the workspace in Settings → Advanced.
Symlinks can point your usual path here, but cannot grant access outside the workspace.
The centre terminal runs as `sandvault-<you>`; the right-hand Shell pane runs as you, with your normal permissions.
Run the repository's bootstrap command (e.g. `script/bootstrap`) in its main checkout from Shell to install shared dependencies.
Agents can prepare worktrees but cannot `brew install`; repeat host bootstrapping when shared dependencies change.
Agents survive quitting through herdr, the background session manager; Shell tabs close with the app.
YOLO mode protects your home and credentials, but agents can change shared files and upload readable code; review their work before trusting it.
For keychain problems follow setup's sandbox-account guidance; never reset your main user's keychain.
For permission popups see [sandvault recovery](https://github.com/webcoyote/sandvault#fix-the-security-popup).

Upgrading from the former app preserves settings and conversations; keep old session files, update custom app paths and repeat iPhone setup.

## ⚙️ Configuration

Settings (Cmd-,):

- **General**: Choose session defaults, signing and the browser.
- **Work**: Hide selected organisations on Mac and iPhone outside working hours while schedules continue.
- **Schedules**: Manage recurring jobs with masked token previews or start them now.
- **Sessions**: Inspect and stop agents and browser pages.
- **Review**: Choose reviewers, models, effort and review or fix prompts.
- **Notifications**: Choose finished-turn and input notifications, sounds and a Dock badge for agents waiting for input.
- **Fonts**: Customise fonts and sizes.
- **Editor**: Choose the external editor opened with Cmd-click.
- **Advanced**: Set paths, refresh intervals, idle sleep and logging.

Use `sanductor .` to select a worktree or `sanductor /some/file` to open a file.
To use Sanductor as your editor inside its shell panes, add this to your shell configuration:

```bash
if [ -n "${SANDUCTOR}" ]; then
  export EDITOR="$(command -v sanductor) --wait"
  export VISUAL="${EDITOR}"
fi
```

## 🛠️ Development

Use `script/build`, `script/test`, `script/style --fix` and `script/analyze` for [development](ARCHITECTURE.md#dependencies-and-toolchain).
Quit the app and run `script/tutorial` to replay the opening tour without resetting settings.
See the [release process](ARCHITECTURE.md#releases) for publishing.

## 📱 iPhone companion

Requires iOS 26 or later; run `script/bootstrap` and `script/install` on your Mac, then choose a signing team in Xcode and build `Sanductor-iOS`.

1. Copy the public key from iPhone Settings to your Mac's clipboard, then install it for the sandbox user:

   ```bash
   mkdir -p ~/.config/codeofhonor/sandvault/authorized_keys.d
   pbpaste >~/.config/codeofhonor/sandvault/authorized_keys.d/sanductor-phone
   sv build
   ```

   Delete that file and run `sv build` to revoke the key.

2. Add this to `/etc/ssh/sshd_config.d/000-sanductor.conf`, replacing `<you>` with your username and adjusting the workspace path, then enable Remote Login for `sandvault-<you>`:

   ```text
   Match User sandvault-<you>
       SetEnv SHARED_WORKSPACE=/Users/Shared/sv-<you>
   ```

3. In the iPhone app, enter your Mac's address and username; it adds `sandvault-` automatically.
   Use port `22` unless changed and select `sanductor` for the installed app or `sanductor-dev` for development.
   Choose **Connect** and verify the host key against `ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub` on your Mac.
   A changed key must be explicitly replaced in Settings.

## 📄 Licence and contact

[AGPL-3.0](LICENSE); personal software without support or compatibility guarantees.
[Contact Mike McQuaid](mailto:mike@mikemcquaid.com).
[Octicons](https://github.com/primer/octicons) are vendored in `App/Assets.xcassets` and licensed under the [MIT License](https://github.com/primer/octicons/blob/main/LICENSE).
