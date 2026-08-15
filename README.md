# AgentIDE

🪪 IDE for Agents

A native macOS app for running, steering and reviewing sandboxed AI coding
agents in parallel git worktrees, from problem statement to merged pull
request. Built with SwiftUI on top of
[sandvault](https://github.com/webcoyote/sandvault),
[tmux](https://github.com/tmux/tmux/wiki) and the [gh](https://cli.github.com)
CLI.

## Motivation

My agentic coding setup, described in
[Sandboxes and Worktrees: My secure Agentic AI Setup](https://mikemcquaid.com/sandboxed-agent-worktrees-my-coding-and-ai-setup-in-2026/),
previously spanned four apps: an agent manager to run agents in worktrees, a
git client to review their work, a code editor to fix it and a terminal for
everything else. AgentIDE replaces all four with a single native app designed
around that workflow rather than four apps adapted to it, with no web-tech
wrappers. Agents run inside a sandvault sandbox with no GitHub credentials so
they can run wild without babysitting permission prompts or endangering the
rest of my machine. Sessions live in tmux owned by the sandbox user so nothing
is lost when the app quits, crashes or updates.

## Features

In workflow order; the loop from prompt to review repeats as often as needed
before shipping.

### Start work

- Creates or clones repositories into the sandvault shared workspace, symlinks
  them into your home directory and bootstraps them (so your user and the
  sandbox share one checkout with nothing to keep in sync)
- Creates a worktree and branch from a typed problem statement or an existing
  issue or pull request (so starting work is one prompt, not a git ritual)
- Starts the agent of your choice in tmux inside the sandvault sandbox, with
  Claude Code and Codex CLI supported first and more pluggable later (so
  agents run unattended with no permission prompts and no access to your
  credentials)

### Watch and steer

- Shows every agent's state on one dashboard, including sessions started
  outside AgentIDE (so one window tells you who needs attention)
- Groups worktrees by repository, showing unread terminal and agent activity
  since each was last viewed, open pull requests, mergeability and
  uncommitted or unpushed work, and a worktree can be marked unread to
  revisit (so you always know where you are needed)
- Notifies you when an agent finishes or its output stalls (so you never sit
  polling a terminal)
- Renders terminals locally from a tmux control mode client, so selecting,
  copying, wheel scrolling and scrollback behave like any other text on
  your Mac while the sessions keep running in tmux (so native terminal
  feel costs no session survival)
- Reflows multi-line copies from agent terminals: indentation, gutter
  marks and hard line breaks go while paragraphs and lists survive, and
  Option-drag copies a rectangle (so answers paste cleanly into chat,
  notes and pull request bodies)
- Commits work the agent forgot to commit, clearly authored as such (so
  nothing is stranded in a worktree and review still sees everything)
- Lets you SSH into any session from an iOS SSH client (so you can steer or
  add context away from your Mac)

### Review

- Presents the agent's conversation beside a pull-request-style review of its
  diff, syntax highlighted with per-file and total diffstats, generated files
  hidden, a whitespace-only-change toggle and the open pull request's
  conversations inline under their files, resolvable in place (so you review
  what matters the way you would on GitHub)
- Rejects individual lines to amend the commit, edits commit messages and
  edits files directly in a built-in syntax-highlighted editor (so small fixes
  need no other app)
- Previews web pages and rendered Markdown in an embedded browser and opens an
  embedded terminal running as your own user (so you can verify behaviour and
  use git, gh and other CLI tools without leaving the window)

### Ship

- Pushes branches, showing how many commits each push sends and naming
  whether a rebase would move the base, sign commits or both, then opens
  pull requests from an in-app form that fills in the project's own
  template below your title and body, defaulting both from a single
  commit or drafting them from many with the on-device model (so
  shipping needs no retyping)
- Copies unresolved review comments, or failing CI steps with their
  actual log output, straight into a prompt, resolves conversations one
  by one, resolves merge conflicts and enables automerge or merges,
  each with one click (so the last mile is not the slowest)

### Tidy up

- Deletes a worktree and its branch once the pull request merges (so
  finished work disappears without ceremony)
- Keeps every conversation a repository has ever run browsable and
  resumable from the repository's own page, whichever worktree it used and
  even after that worktree is deleted (so tidying up never loses a
  conversation)

### Resilience

- Keeps agent sessions in a tmux server owned by the sandbox user rather
  than the app (so agents survive AgentIDE quitting, crashing or
  updating, expectedly or not; the host shell tab deliberately does not,
  living and dying with the app)
- Defers idle sleep while agents or shells run and resumes sessions the
  sleep killed when the Mac wakes (so a long response survives you
  walking away; closing the lid still sleeps)
- Collects every failure and status message into a Messages utility tab,
  shown from the first error and inline on screens without the utility
  pane (so background failures are never lost to a log you were not
  watching)

## Out of Scope Features

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
- A native iOS app (remote access is SSH into tmux from any iOS SSH client)

## Requirements

- macOS 27 or later
- [Homebrew](https://brew.sh) (installs the dependencies below)
- [sandvault](https://github.com/webcoyote/sandvault) (creates the sandbox
  user and shared workspace)
- [gh](https://cli.github.com) authenticated as you (it stays with your user;
  agents never see it)
- tmux (installed by `script/bootstrap` via the `Brewfile`)
- Xcode 27 or later (only needed to build from source)

## Usage

After cloning:

```bash
git clone https://github.com/MikeMcQuaid/AgentIDE
cd AgentIDE
script/bootstrap
script/install
open /Applications/AgentIDE.app
```

`script/bootstrap` installs the `Brewfile` dependencies and generates the
gitignored Xcode project with XcodeGen (`open AgentIDE.xcodeproj` to work in
Xcode). `script/install` builds and copies the app into `/Applications`, so
the copy you run is never the build output a rebuild overwrites in place;
the repo-root `AgentIDE.app` symlink to `script/build`'s output remains for
quick development runs. The app
currently launches to an empty dashboard; features land slice by slice (see
[Status](#status)). A prebuilt app with automatic updates will come later.

## Status

Unstable and changing daily. AgentIDE is being designed exclusively
for [@MikeMcQuaid](https://github.com/MikeMcQuaid)'s personal
workflow; nothing here promises to suit anyone else's, interfaces
and behaviour break without notice and there is no support. If it
fits your workflow anyway, expect sharp edges.

Readme-driven development: this README describes the complete intended
workflow before any of it exists. Slices land in order, each one usable when
done:

1. Documentation and guardrails: these documents, linting and CI (done)
2. Skeleton: XcodeGen project, Swift packages and an empty dashboard app
   (done)
3. Core loop: create worktrees, launch and attach to sandboxed agents
   (basic, this pull request)
4. Monitoring: notifications, unread tracking and resumable sessions
   (basic, this pull request)
5. Review: diffs, per-line rejection and editing (basic and plain text
   until the editor stack lands, this pull request)
6. Embedded terminal and browser (basic, this pull request)
7. GitHub pull request creation, dashboards and one-click fixes
   (basic, this pull request)
8. Lifecycle: cleanup on merge, past conversation browsing and foreign
   session discovery (basic, this pull request)
9. Automatic updates and polish, including checking the Brewfile's
   tools are installed at startup and offering to install any that
   are missing from a copy vendored in the app bundle

See [ARCHITECTURE.md](ARCHITECTURE.md) for how AgentIDE is designed and
[AGENTS.md](AGENTS.md) if you are working on this repository, human or agent.

## Licence

[GNU Affero General Public License v3.0](LICENSE). If you reuse or adapt the
source the AGPL terms apply, including the network-use clause.
[Octicons](https://github.com/primer/octicons) are vendored in
`App/Assets.xcassets` and licensed under the
[MIT License](https://github.com/primer/octicons/blob/main/LICENSE).
