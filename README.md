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

- Starts a worktree, a branch and an agent from a prompt, a GitHub
  issue, a pull request or a repository security advisory still in
  triage or draft, narrating each step until the agent is up; the
  issue and pull request pickers search by title or number, the
  advisory picker by title or GHSA id. An advisory session gets a
  bland branch name and is told to keep its commit messages and pull
  request as bland, naming neither the advisory nor the vulnerability,
  so nothing public discloses the fix before the advisory is published.
  New branches start from origin's default branch, fetching first when
  the last fetch was over an hour ago, including with `agentide new`.
- Runs Claude Code or Codex CLI as a sandboxed, non-admin user, with
  no permission prompts necessary and no access to your admin user's
  files or credentials.
- Groups worktrees by repository with unread activity, agent state, open
  pull requests, merge conflicts, uncommitted work and drift from what
  was pushed, adopting worktrees made outside the app in the same
  locations.
- Says what a pull request is doing in GitHub's own icons, one glyph per
  fact, watching checks and queued merges until they settle. The checks
  dot follows the checks the base branch requires: an optional job
  failing leaves it green, its hover help saying so, and a required one
  still to report keeps it orange. The sidebar's row and the pull
  request pane change together, whichever of them heard first.
- Fetch and Fetch and Reset on a repository follow its default branch
  when it has moved on GitHub, switching the checkout to the new one;
  a new worktree whose base branch has gone follows it too. Fetches
  update origin and forks used by open worktrees, so unused fork
  remotes cannot block them; `agentide new` needs only origin.
- Reattaches a pane that shows nothing by itself, once, and offers
  Reattach in the pane when that does not draw either; a right-click
  on the pane or on the session strip above it offers it any time.
- Keeps terminal text selected for copying while the agent's cursor
  blinks or its screen repaints. Option-drag copies a rectangle;
  Cmd-C and the Copy menu keep that same block while it is selected.
  A new ordinary selection or Select All replaces the block completely.
- Runs as many host shells in a worktree as the work needs, each a tab
  of its own: a dev server holding one while git commands and API calls
  use the next. The plus in the Shell bubble or Shift-Cmd-T opens
  another; the following close button ends all shells in that worktree.
  A single shell uses no extra tab row. Multiple shells share a
  full-width tab bar underneath, each tab closing its own shell process
  immediately.
- Keeps running shells alive when switching shells, worktrees or tabs,
  hiding the utility pane or narrowing the window. Shells end when
  closed, when their worktree is deleted or when the app quits.
  Option-arrow keys reach agents as shortcuts and retain shell word
  navigation, and the numeric keypad types its numbers while preserving
  modified-key behaviour.
- Asks Copilot to review a pull request, or to review it again after
  a push, from the Copilot icon in the conversation's header; it dims
  while a request is still waiting on it.
- Code reviews uncommitted work, the last commit, unpushed commits, the
  whole branch or any single commit, as a syntax-highlighted diff with
  the pull request's conversations inline under their files.
- Asks the other agent to review the selected diff through its Claude
  or Codex icon at the top of Review, which shows a spinner while a
  review runs. The popover starts with an
  editable review prompt, prefilled with the existing instructions,
  and attaches the selected diff automatically. Reviews cover
  actionable bugs and major readability, documentation and security
  improvements. Findings appear both beneath their files and in the
  popover, marked as local reviews with the reviewer's icon. Make fixes
  prepares one editable prompt for all unresolved findings to copy
  into the main agent pane, grouping comments by file like copied GitHub
  reviews and omitting empty notes. Each finding also offers Make fix
  for just that comment. Resolve comment dismisses it locally and can be
  undone with Reopen comment; preparing a fix does not claim the code
  has been fixed. Raw output stays out of the popover. Reviews continue
  in the background when switching worktrees or panes; returning shows
  their progress or results. Completed reviews, their edited instructions
  and resolved comments survive relaunches;
  changed code needs a fresh review. Settings chooses the default
  reviewer and each agent's review model and effort. With no recorded
  session, Other agent uses the opposite of the general session default.
  Diff controls stay locked during review and fix-prompt preparation;
  a reviewer exceeding 256 KiB on either output stream is stopped.
- Edits files in a built-in editor that reads `.editorconfig`, comments
  with Cmd-/, moves and duplicates lines, guides columns 80 and 118 and
  bars every uncommitted line; an uncommitted file can also be put back
  to what HEAD has, or deleted if it was never committed, after a
  prompt. Cmd-F jumps to the first match after a brief pause in typing,
  keeping focus in the find field.
- Commits the files you tick rather than the worktree, or adds them to
  the previous commit, with the message drafted by the on-device Apple
  model. Last Commit also starts with every file ticked; untick files
  and Amend to leave them uncommitted, keeping at least one file in
  the commit. The sidebar's counts and Push follow a commit or amend
  at once.
- Pushes, rebases and opens pull requests as drafts or ready for review,
  templates filled in, labels attached, forks used where the repository
  is not yours, pushes following a contributor's fork back to it, and
  branches stacked in one worktree; an open pull request's title and
  body are edited in the same form, the template as a field of its
  own when the body was opened with one, to say what was actually
  pushed.
- Connects fork worktrees to their upstream pull requests for comments
  and checks, signing and pushing back to the contributor's branch;
  a push refused by the fork reports the error in the pane. Fork
  branches cannot create or publish PR stacks, which GitHub does not
  support across forks.
- Copies unresolved review comments and the failing logs of the checks
  the branch requires into a prompt, resolves conversations and merges
  or queues, each with a click.
- Stays quiet while idle, and quieter still on battery, with agent
  and file changes still landing at once.
- Says when the sandbox user's login keychain has stopped opening after
  a macOS update, with the commands that put it right, rather than
  letting every agent start behind a password dialog; no keychain is
  ever deleted for you.
- Notifies when an agent finishes or needs input, badges the Dock, and
  marks a pane that has held several cores for ten minutes with what is
  running in it.
- Counts unread errors in the Messages tab's red badge. Viewing Messages
  marks them as read, keeping the log available without needing Clear.
  A network connection dropping and coming back is not a message; only
  something you asked for that needed the network reports its absence.
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

```bash
brew install --cask agentide
```

The [`agentide` cask](https://github.com/Homebrew/homebrew-cask/blob/main/Casks/a/agentide.rb)
installs the latest release, and `brew upgrade` updates it. Releases are
signed with a Developer ID certificate and notarised by Apple.

Without Homebrew, download `AgentIDE-<version>.zip` from the
[releases page](https://github.com/MikeMcQuaid/AgentIDE/releases), unzip
it and move `AgentIDE.app` to /Applications.

To run the current source instead:

```bash
script/bootstrap
script/install
```

## ⚙️ Configuration

Settings (Cmd-,) controls:

- **General**: the agent, model and effort new sessions start on, whether
  commits must be signed, and the browser Cmd-click opens.
- **Review**: which reviewer a pane starts with, either the other agent
  or a named agent, and separate model and effort preferences for each.
  Model and effort changes apply to the next review without changing
  new-session defaults.
- **Notifications**: which events notify, badge the Dock and make a
  sound.
- **Fonts**: fonts and sizes for every piece of text in the app, so it
  can be made as large or as legible as you need: interface text
  (labels, headings, captions, messages and conversations), code and
  terminals, repository names, worktree and branch names, and the
  utility and shell tabs. The first font entry names the default
  family. Changes preview immediately in the main window and in
  Settings itself, including open terminals and editors. Headings
  keep their emphasis as fonts change; each group can return to its
  original defaults.
- **Editor**: the external editor Cmd-click runs.
- **Advanced**: where repositories and worktrees live, how often the
  system is re-read, idle sleep and the performance log.

Double-click either pane divider to restore that pane's default width.
The right divider and **Resize Panes** give the review pane one-third of
the space beside the sidebar and the middle pane two-thirds, subject to
their minimum and maximum widths.

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

## 📱 iPhone SSH access

Agents run as the sandbox user, so anything that can SSH to that user
can start and steer them. [Moshi](https://getmoshi.app) is the iOS
client this is currently built around, because it speaks both
[`mosh`](https://mosh.org), so a phone changing network keeps its
session rather than dropping it, and `herdr`, so it attaches to the same
sessions the app does.

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
   your own user name and path in place of `<you>`, then turn on macOS's
   Remote Login for that account:

   ```text
   Match User sandvault-<you>
       SetEnv SHARED_WORKSPACE=/Users/Shared/sv-<you>
   ```

3. In the sandbox user's shell configuration, name the session and give
   the new-session command a short alias:

   ```bash
   export HERDR_SESSION=agentide
   alias ain='/Applications/AgentIDE.app/Contents/Resources/bin/agentide new'
   ```

Connect as `sandvault-<you>` and run `herdr`: one attach presents every
agent's workspace, and `ain` starts a new session, asking for repository,
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
- `script/test [--sanitize address|thread]`: unit, integration and App
  Intents tests, optionally checking memory accesses or data races
- `script/style [--fix]`: SwiftLint and SwiftFormat, every rule on
- `script/analyze`: static analysis and dead code
- `script/zip` and `script/package`: zip, sign and notarise a release
- `script/attach`: attach this terminal to the sandboxed `herdr` session

Project code treats compiler and linker warnings as errors, with Swift's
strict concurrency and memory safety checks enabled. Xcode also runs
Apple's static analyser during builds. `script/analyze` adds SwiftLint's
analysis and dead-code detection on the host and CI. CI also runs the
tests under Address Sanitizer. Thread Sanitizer is available locally;
its CI gate awaits a compatible SwiftTerm release fixing a shell-exit
race.

Releases run the **Release** workflow from the Actions tab on `main` with
a bare `MAJOR.MINOR.PATCH` version.

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
