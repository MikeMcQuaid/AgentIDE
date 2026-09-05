# 🪪 AgentIDE

![The worktree sidebar, an agent's terminal and its review beside it](docs/screenshot.png)

AgentIDE is a native macOS app for running, prompting and reviewing
sandboxed AI coding agents in parallel `git` worktrees, from prompt
to reviewed, merged pull request. Everything a task passes through,
worktree, conversation, review, pull request and CI, is one window in
one app rather than several. Built with SwiftUI on top of
[sandvault](https://github.com/webcoyote/sandvault),
[`herdr`](https://herdr.dev) and the [`gh`](https://cli.github.com) CLI.

## 💡 Motivation

My agentic coding setup, described in
[Sandboxes and Worktrees: My secure Agentic AI Setup](https://mikemcquaid.com/sandboxed-agent-worktrees-my-coding-and-ai-setup-in-2026/),
spanned four apps: an agent and worktree manager, a `git` GUI, a code
editor and a terminal. AgentIDE replaces all four with one app designed
around the same workflow. Agents run inside a separate, non-admin
sandvault sandboxed user with no access to sensitive files or
credentials, so they can work unattended without endangering the rest of
the machine, and their sessions live in a `herdr` server owned by the
same sandbox user, so nothing is lost when the app quits, crashes or
updates.

## ✨ Features

- Starts a worktree, a branch and an agent from a prompt, a GitHub issue
  or a pull request, narrating each step until the agent is up.
- Runs Claude Code or Codex CLI as a sandboxed, non-admin user, with
  no permission prompts necessary and no access to your admin user's
  files or credentials.
- Groups worktrees by repository with unread activity, agent state, open
  pull requests, merge conflicts, uncommitted work and drift from what
  was pushed, adopting worktrees made outside the app in the same
  locations.
- Says what a pull request is doing in GitHub's own icons, one glyph per
  fact, watching checks and queued merges until they settle.
- Code reviews uncommitted work, the last commit, unpushed commits, the
  whole branch or any single commit, as a syntax-highlighted diff with
  the pull request's conversations inline under their files.
- Edits uncommitted lines in place in the diff, and files in a built-in
  editor that reads `.editorconfig`, comments with Cmd-/, moves and
  duplicates lines, guides columns 80 and 118 and bars every uncommitted
  line.
- Commits the files you tick rather than the worktree, or adds them to
  the previous commit, with the message drafted by the on-device Apple
  model.
- Pushes, rebases and opens pull requests as drafts or ready for review,
  templates filled in, labels attached, forks used where the repository
  is not yours, and branches stacked in one worktree.
- Copies unresolved review comments and failing CI logs into a prompt,
  resolves conversations and merges or queues, each with a click.
- Notifies when an agent finishes or needs input, badges the Dock, and
  marks a pane that has held several cores for ten minutes with what is
  running in it.
- Deletes a worktree and its branch once its pull request merges, and
  keeps every conversation browsable and resumable after the worktree is
  gone.
- Starts and steers work from a phone: `agentide new` over SSH, Shortcuts
  and Siri, and `herdr` for the sessions themselves.

## 🚫 Out of Scope

- Windows or Linux support; being a native macOS app is the point.
- Running agents without a sandboxed non-admin user.
- Team, multi-user or hosted features: one developer, one Mac.
- An agent marketplace or bundled models; bring your own agent CLI.
- A native iOS app: SSH into `herdr` from any iOS client instead.
- An updater or a Mac App Store build; Homebrew's cask upgrades it, and
  the App Store sandbox forbids running agents as another user.

## 📋 Requirements

- macOS Golden Gate (27) or later.
- [Homebrew](https://brew.sh), which installs the rest.
- [sandvault](https://github.com/webcoyote/sandvault), which creates the
  sandbox user and the shared workspace.
- [`gh`](https://cli.github.com) authenticated as you; it stays with your
  user and agents never see it.
- [`herdr`](https://herdr.dev) and [`mosh`](https://mosh.org), installed
  by `script/bootstrap`; `mosh` only matters from a phone.
- Xcode 27 or later, only to build from source.

## 📦 Installation

Download `AgentIDE-<version>.zip` from the
[releases page](https://github.com/MikeMcQuaid/AgentIDE/releases), unzip
it and move `AgentIDE.app` to /Applications. Releases are signed with a
Developer ID certificate and notarised by Apple.

Releases will also ship as a Homebrew cask
(`brew install --cask agentide`) once the cask exists; `brew upgrade`
then updates the app.

To run the current source instead:

```bash
script/bootstrap
script/install
```

## ⚙️ Configuration

Settings (Cmd-,) controls:

- **General**: the agent, model and effort new sessions start on, whether
  commits must be signed, and the browser Cmd-click opens.
- **Notifications**: which events notify, badge the Dock and make a
  sound.
- **Editor**: the external editor Cmd-click runs, and the monospace font
  every code surface shares.
- **Advanced**: where repositories and worktrees live, how often the
  system is re-read, idle sleep and the performance log.

A shell pane sets `AGENTIDE=1` and puts the bundled `agentide` command on
`PATH`, so shell files can hand editing back to the app:

```bash
if [ -n "${AGENTIDE}" ]; then
  export EDITOR="$(command -v agentide) --wait"
  export VISUAL="${EDITOR}"
fi
```

`agentide .` from any terminal switches the window to the worktree you
are in.

## 📱 From a phone

Agents run as the sandbox user, so anything that can SSH to that user can
start and steer them. [Moshi](https://getmoshi.app) is the iOS client
this is built around: it speaks [`mosh`](https://mosh.org), so a phone
that changes network keeps its session rather than dropping it.

1. Put the phone's public key in sandvault's guest template, which is
   what the sandbox home is built from, then rebuild it. A sandvault
   upgrade replaces the template, so keep this in your dotfiles:

   ```bash
   guest_keys="$(brew --prefix sandvault)/libexec/guest/home/.ssh/authorized_keys"
   cat "${HOME}/Downloads/moshi.pub" >>"${guest_keys}"
   sv --rebuild build
   ```

2. Name the shared workspace for logins from outside the sandbox, which
   do not inherit it, in `/etc/ssh/sshd_config.d/000-agentide.conf` with
   your own user and path, then turn on Remote Login for that account:

   ```text
   Match User sandvault-mike
       SetEnv SHARED_WORKSPACE=/Users/Shared/sv-mike
   ```

3. In the sandbox user's shell configuration, name the session and give
   the new-session command a short alias:

   ```bash
   export HERDR_SESSION=agentide
   alias an='/Applications/AgentIDE.app/Contents/Resources/bin/agentide new'
   ```

Connect as `sandvault-<you>` and run `herdr`: one attach presents every
agent's workspace, and `an` starts a new session, asking for repository,
agent, model, effort and prompt. A session steered from the phone is the
same session the Mac shows.

## 🛠️ Development

- `script/bootstrap`: install `Brewfile` dependencies and generate the
  Xcode project with XcodeGen
- `script/build`: build the app; `AgentIDE.app` in the repository root
  symlinks its output
- `script/version`: print the version and build number git says, which
  scripted and Xcode builds both use
- `script/install`: build, then copy the app to /Applications
- `script/test`: unit, integration and App Intents tests
- `script/style [--fix]`: SwiftLint and SwiftFormat, every rule on
- `script/analyze`: static analysis and dead code
- `script/zip` and `script/package`: zip, sign and notarise a release
- `script/attach`: attach this terminal to the sandboxed `herdr` session

Releases run the **Release** workflow from the Actions tab on `main` with
a bare `MAJOR.MINOR.PATCH` version.

See [ARCHITECTURE.md](ARCHITECTURE.md) for how AgentIDE is designed and
[AGENTS.md](AGENTS.md) if you are working on this repository, human or
agent.

## 🚧 Status

Stable but changing daily. AgentIDE is being designed exclusively for
[@MikeMcQuaid](https://github.com/MikeMcQuaid)'s personal workflow;
nothing here promises to suit anyone else's, interfaces and behaviour may
break without notice and there is no support.

## 📮 Contact

[Mike McQuaid](mailto:mike@mikemcquaid.com)

## 📄 Licence

[AGPL-3.0](LICENSE). If you reuse or adapt the source the AGPL terms
apply, including the network-use clause.

[Octicons](https://github.com/primer/octicons) are vendored in
`App/Assets.xcassets` and licensed under the
[MIT License](https://github.com/primer/octicons/blob/main/LICENSE).
