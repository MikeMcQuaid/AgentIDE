# AgentIDE

🪪 IDE for Agents

A native macOS app for running, steering and reviewing sandboxed AI coding
agents in parallel git worktrees, from problem statement to merged pull
request. Built with SwiftUI on top of
[sandvault](https://github.com/webcoyote/sandvault),
[`herdr`](https://herdr.dev) and the
[`gh`](https://cli.github.com) CLI.

## 💡 Motivation

My agentic coding setup, described in
[Sandboxes and Worktrees: My secure Agentic AI Setup](https://mikemcquaid.com/sandboxed-agent-worktrees-my-coding-and-ai-setup-in-2026/),
previously spanned four apps: an agent manager to run agents in worktrees, a
git client to review their work, a code editor to fix it and a terminal for
everything else. AgentIDE replaces all four with a single native app designed
around that workflow rather than four apps adapted to it, with no web-tech
wrappers. Agents run inside a sandvault sandbox with no GitHub credentials so
they can run wild without babysitting permission prompts or endangering the
rest of my machine. Sessions live in a `herdr` server owned by the sandbox user
so nothing is lost when the app quits, crashes or updates.

## ✨ Features

In workflow order; the loop from prompt to review repeats as often as needed
before shipping.

### 🚀 Start work

- **Creates** or clones repositories into the sandvault shared workspace, symlinks
  them into your home directory and bootstraps them (so your user and the
  sandbox share one checkout with nothing to keep in sync)
- **Creates** a worktree and branch from a typed problem statement or an existing
  issue or pull request, narrating each step and the command it is waiting
  on with a clock that ticks every second, the same when a conversation
  resumes (so starting work is one prompt, not a git ritual, and a slow
  step is never a blank pane)
- **Starts** the agent of your choice in `herdr` inside the sandvault sandbox, with
  Claude Code and Codex CLI supported first and more pluggable later (so
  agents run unattended with no permission prompts and no access to your
  credentials)

### 👀 Watch and steer

- **Shows** every agent's state on one dashboard, working, waiting for
  input or finished straight from `herdr`'s own agent detection, including
  sessions started outside AgentIDE (so one window tells you who needs
  attention)
- **Groups** worktrees by repository, showing unread terminal and agent activity
  since each was last viewed, open pull requests, mergeability and
  uncommitted or unpushed work, and a worktree can be marked unread to
  revisit, with a right-click Refresh that asks GitHub about that
  repository's branches at once (so you always know where you are
  needed)
- **Says** what a branch is doing in GitHub's own icons: green for an open
  pull request or a repository's own branch, purple once merged, orange
  while it actually sits in the merge queue, grey for a draft; then its
  number, a CI dot, a review that has approved, asked for changes or not
  happened yet, any unresolved conversations, and its commit counts last
  (so one glance across the sidebar says where everything stands)
- **Notifies** you when an agent finishes its work, needs your input or
  stalls, the finish with a completion chime picked from the menu bar:
  macOS's own sounds, any audio file of your own or silence (so you never
  sit polling a terminal and ship no audio files either)
- **Renders** terminals locally from `herdr`'s terminal control stream, so
  selecting, copying and pasting behave like any other text on your Mac
  while the sessions keep running in `herdr` (so native terminal feel
  costs no session survival)
- **Reflows** multi-line copies from agent terminals: indentation, gutter
  marks and hard line breaks go while paragraphs and lists survive, but a
  block that reads as commands or code keeps every line exactly, and
  Option-drag copies a rectangle (so answers paste cleanly into chat,
  notes and pull request bodies, and a copied script still runs)
- **Commits** work the agent forgot to commit, clearly authored as such (so
  nothing is stranded in a worktree and review still sees everything)
- **Lets** you SSH into every session from an iOS SSH client, with
  [Moshi](https://getmoshi.app) the one to reach for: one `herdr` attach
  presents every agent workspace with its own navigation, and `mosh`
  survives a phone changing network, so nothing is needed on this side
  beyond Remote Login for the sandbox account (so you can steer or add
  context away from your Mac)

### 🔍 Review

- **Presents** the agent's conversation beside a pull-request-style review of its
  diff, syntax highlighted with per-file and total diffstats, generated files
  hidden, a whitespace-only-change toggle and the open pull request's
  conversations inline under their files, resolvable in place (so you review
  what matters the way you would on GitHub)
- **Rejects** individual lines to amend the commit, edits commit messages and
  edits files directly in a built-in syntax-highlighted editor, with a
  Markdown file rendering inline at the press of its own button (so small
  fixes and reading what the agent wrote need no other app)
- **Previews** web pages and rendered Markdown in an embedded browser and opens an
  embedded terminal running as your own user (so you can verify behaviour and
  use `git`, `gh` and other CLI tools without leaving the window)
- **Keeps** each worktree's page loaded as you work in other worktrees,
  remembers its address for the next time and lists every loaded page in
  the session manager with what it costs and a Close (so a dev server stays
  logged in and mid-flow, and a page eating memory is easy to find and end)
- **Finds** with Cmd-F wherever you are: the editor and both terminals get
  the system find bar, and the diff gets its own with match highlighting and
  Cmd-G walking the matches; nothing anywhere turns your quotes curly or your
  dashes long (so code and commit messages survive being typed)
- **Edits** whatever that terminal's commands open, a `git rebase -i` todo list
  or a commit message, in the same editor with their own highlighting, because
  an `agentide` command on its `PATH` blocks until you save and close and
  `EDITOR`, `VISUAL` and `GIT_EDITOR` there name it (so interactive rebasing
  needs no terminal editor, and cancelling aborts the rebase as `:cq` would)

### 🚢 Ship

- **Pushes** branches, showing how many commits each push sends and naming
  whether a rebase would move the base, sign commits or both, then opens
  pull requests from an in-app form that fills in the project's own
  template below your title and body, defaulting both from a single
  commit, unwrapped from the narrow column commit messages are written
  to, or drafting them from many with the on-device model (so shipping
  needs no retyping)
- **Pushes** to your own fork when the repository is not yours to write to,
  creating it and its remote the first time and opening the pull request from
  it (so working in someone else's repository needs no setup and no thinking
  about where the branch goes)
- **Copies** unresolved review comments, or failing CI steps with their
  actual log output, straight into a prompt, resolves conversations one
  by one, resolves merge conflicts and enables automerge or merges,
  each with one click (so the last mile is not the slowest)

### 🧹 Tidy up

- **Deletes** a worktree and its branch once the pull request merges,
  whether you merged in the app, picked Clean up after merge from the
  worktree's menu or the next refresh simply notices the merge happened
  on GitHub (so finished work disappears without ceremony)
- **Keeps** every conversation a repository has ever run browsable and
  resumable from the repository's own page, whichever worktree it used and
  even after that worktree is deleted, and starts a fresh session in a
  worktree from the same list (so tidying up never loses a conversation)

### 🛟 Resilience

- **Keeps** agent sessions in a `herdr` server owned by the sandbox user rather
  than the app (so agents survive AgentIDE quitting, crashing or
  updating, expectedly or not; the host shell tab deliberately does not,
  living and dying with the app)
- **Keeps** a copy of each worktree's newest conversation in iCloud Drive,
  hourly while it runs and whenever it is closed or resumed, the conversation
  only, and drops it when the worktree is deleted (so the sandbox user is
  disposable: its transcripts are the one thing git and GitHub do not hold)
- **Fits** itself to whatever display it is on: unplugging the monitor a
  fullscreen window is on drops it back onto the screen that is left, at a
  size that screen can show, with the panes narrowed to match (so a window
  is never stranded larger than the display under it)
- **Keeps** every running shell alive while you move around the app and
  keeps a worktree listed until it is really gone, rebases and failed
  listings included (so only closing a shell or destroying its worktree
  ends it)
- **Defers** idle sleep while agents or shells run and resumes sessions the
  sleep killed when the Mac wakes (so a long response survives you
  walking away; closing the lid still sleeps)
- **Collects** every failure and status message into a Messages utility tab
  that is always there, and shows failures inline on screens without the
  utility pane (so nothing is lost to a status line that scrolled past or
  a log you were not watching)

## 🚫 Out of Scope Features

- Being a general-purpose IDE (the built-in editor is for review-time fixes;
  use your preferred editor for long editing sessions)
- Windows or Linux support (being a native macOS app is the point)
- Replacing sandvault (AgentIDE drives sandvault; sandboxing policy stays
  there)
- Running agents outside the sandbox (the agents' own dangerous flags exist if
  you must)
- Team, multi-user or hosted features (one developer, one Mac)
- An agent marketplace or bundled models (bring your own Claude Code, Codex
  CLI or other supported agent)
- A native iOS app (remote access is SSH into `herdr` from any iOS SSH
  client)

## 📋 Requirements

- **macOS** Golden Gate (27) or later
- [Homebrew](https://brew.sh) (installs the dependencies below)
- [sandvault](https://github.com/webcoyote/sandvault) (creates the sandbox
  user and shared workspace)
- [`gh`](https://cli.github.com) authenticated as you (it stays with your user;
  agents never see it)
- [`herdr`](https://herdr.dev) and
  [`mosh`](https://mosh.org) (installed by `script/bootstrap` via the
  `Brewfile`; `mosh` is only needed to reach sessions from a phone over a
  connection that comes and goes)
- **Xcode** 27 or later (only needed to build from source)

## 🖥️ Usage

After cloning:

```bash
git clone https://github.com/MikeMcQuaid/AgentIDE
cd AgentIDE
script/bootstrap
script/install
open /Applications/AgentIDE.app
```

- **`script/bootstrap`** installs the `Brewfile` dependencies and generates
  the gitignored Xcode project with XcodeGen (`open AgentIDE.xcodeproj` to
  work in Xcode).
- **`script/install`** builds and copies the app into `/Applications`, so the
  copy you run is never the build output a rebuild overwrites in place.
- **`AgentIDE.app`** in the repository root symlinks `script/build`'s output,
  for quick development runs.
- **Features** land slice by slice (see [Status](#-status)); the app launches
  to an empty dashboard until the first slices fill it.
- **Updates** come from Homebrew: releases ship as a cask, so `brew upgrade`
  moves the app on with the rest of your tools. There is no built-in
  updater, and no Mac App Store build: its sandbox forbids running agents
  as another user, which is the whole design.

A shell pane runs your login shell, so anything your shell configuration
exports wins over what the pane was started with. It sets `AGENTIDE=1` and
puts the bundled `agentide` command on `PATH`, so shell files that set an
editor of their own can hand those panes back to the app:

```bash
if [ -n "${AGENTIDE}" ]; then
  export EDITOR="$(command -v agentide) --wait"
  export VISUAL="${EDITOR}"
fi
```

## 🚧 Status

Unstable and changing daily. AgentIDE is being designed exclusively
for [@MikeMcQuaid](https://github.com/MikeMcQuaid)'s personal
workflow; nothing here promises to suit anyone else's, interfaces
and behaviour break without notice and there is no support.

See [ARCHITECTURE.md](ARCHITECTURE.md) for how AgentIDE is designed and
[AGENTS.md](AGENTS.md) if you are working on this repository, human or agent.

## 📄 Licence

[GNU Affero General Public License v3.0](LICENSE). If you reuse or adapt the
source the AGPL terms apply, including the network-use clause.

[Octicons](https://github.com/primer/octicons) are vendored in
`App/Assets.xcassets` and licensed under the
[MIT License](https://github.com/primer/octicons/blob/main/LICENSE).
