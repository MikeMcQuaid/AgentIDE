# 🪪 AgentIDE

![The worktree sidebar, an agent's terminal and its review beside it](docs/screenshot.png)

AgentIDE is a native macOS app for running, steering and reviewing
sandboxed AI coding agents in parallel git worktrees, from problem
statement to merged pull request. Everything a task passes through,
worktree, conversation, diff, pull request and CI, is one window rather
than four apps kept in sync by hand. Built with SwiftUI on top of
[sandvault](https://github.com/webcoyote/sandvault),
[`herdr`](https://herdr.dev) and the [`gh`](https://cli.github.com) CLI.

## 💡 Motivation

My agentic coding setup, described in
[Sandboxes and Worktrees: My secure Agentic AI Setup](https://mikemcquaid.com/sandboxed-agent-worktrees-my-coding-and-ai-setup-in-2026/),
spanned four apps: an agent manager, a git client, a code editor and a
terminal. AgentIDE replaces all four with one app designed around that
loop. Agents run inside a sandvault sandbox with no GitHub credentials,
so they can work unattended without endangering the rest of the machine,
and their sessions live in a `herdr` server owned by the sandbox user, so
nothing is lost when the app quits, crashes or updates.

## ✨ Features

- Starts a worktree, a branch and an agent from a typed problem
  statement, a GitHub issue or a pull request, narrating each step until
  the agent is up.
- Runs Claude Code or Codex CLI in the sandbox, with no permission
  prompts and no access to your credentials.
- Groups worktrees by repository with unread activity, agent state, open
  pull requests, merge conflicts, uncommitted work and drift from what
  was pushed, adopting worktrees made outside the app.
- Says what a pull request is doing in GitHub's own icons, one glyph per
  fact, watching checks and queued merges until they settle.
- Reviews uncommitted work, the last commit, unpushed commits, the whole
  branch or any single commit, as a syntax-highlighted diff with the pull
  request's conversations inline under their files.
- Edits uncommitted lines in place in the diff, and files in a built-in
  editor that reads `.editorconfig`, comments with Cmd-/, moves and
  duplicates lines, guides columns 80 and 118 and bars every uncommitted
  line.
- Commits the files you tick rather than the worktree, or adds them to
  the previous commit, with the message drafted by the on-device model.
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

[ARCHITECTURE.md](ARCHITECTURE.md) owns how all of this works.

## 🚫 Out of Scope

- A general-purpose IDE (the built-in editor is for review-time fixes).
- Windows or Linux support; being a native macOS app is the point.
- Replacing sandvault, which AgentIDE drives; sandboxing policy stays
  there, and agents never run outside it.
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
are in. [ARCHITECTURE.md](ARCHITECTURE.md) lists the environment
variables and the files AgentIDE keeps in the shared workspace, and
explains reaching sessions over SSH from a phone.

## 🛠️ Development

- `script/bootstrap`: install `Brewfile` dependencies and generate the
  Xcode project with XcodeGen
- `script/build`: build the app; `AgentIDE.app` in the repository root
  symlinks its output
- `script/install`: build, then copy the app to /Applications
- `script/test`: unit, integration and App Intents tests
- `script/style [--fix]`: SwiftLint and SwiftFormat, every rule on
- `script/analyze`: static analysis and dead code
- `script/zip` and `script/package`: zip, sign and notarise a release
- `script/attach`: attach this terminal to the sandboxed `herdr` session

Releases run the **Release** workflow from the Actions tab on `main` with
a bare `MAJOR.MINOR.PATCH` version; see
[ARCHITECTURE.md](ARCHITECTURE.md) for what it does. See
[AGENTS.md](AGENTS.md) for the conventions this repository keeps.

## 🚧 Status

Unstable and changing daily. AgentIDE is being designed exclusively for
[@MikeMcQuaid](https://github.com/MikeMcQuaid)'s personal workflow;
nothing here promises to suit anyone else's, interfaces and behaviour
break without notice and there is no support.

## 📮 Contact

[Mike McQuaid](mailto:mike@mikemcquaid.com)

## 📄 Licence

[AGPL-3.0](LICENSE). If you reuse or adapt the source the AGPL terms
apply, including the network-use clause.

[Octicons](https://github.com/primer/octicons) are vendored in
`App/Assets.xcassets` and licensed under the
[MIT License](https://github.com/primer/octicons/blob/main/LICENSE).
