# AgentIDE

🪪 IDE for Agents: prompt a worktree, review another, ship a third, repeat

![The worktree sidebar, an agent's terminal and its pull request side by side](docs/screenshot.png)

A native macOS app for running, steering and reviewing sandboxed AI coding
agents in parallel git worktrees, from problem statement to merged pull
request. Everything a task passes through, worktree, conversation, diff,
pull request and CI, is one window rather than four apps kept in sync by
hand. Built with SwiftUI on top of
[sandvault](https://github.com/webcoyote/sandvault),
[`herdr`](https://herdr.dev) and the [`gh`](https://cli.github.com) CLI.

## 💡 Motivation

My agentic coding setup, described in
[Sandboxes and Worktrees: My secure Agentic AI Setup](https://mikemcquaid.com/sandboxed-agent-worktrees-my-coding-and-ai-setup-in-2026/),
spanned four apps: an agent manager, a git client, a code editor and a
terminal. AgentIDE replaces all four with one native app designed around
that loop. Agents run inside a sandvault sandbox with no GitHub
credentials, so they can run unattended without endangering the rest of
the machine, and their sessions live in a `herdr` server owned by the
sandbox user, so nothing is lost when the app quits, crashes or updates.

## ✨ Features

In workflow order; the loop from prompt to review repeats before shipping.

### 🚀 Start work

- Creates or clones repositories into the shared workspace, symlinked into
  your home directory (so you and the sandbox share one checkout)
- Creates a worktree and branch from a typed problem statement, an issue or
  a pull request, narrating each step until the agent is up (so starting
  work is one prompt, not a git ritual)
- Starts Claude Code or Codex CLI in `herdr` inside the sandbox (so agents
  run unattended, with no permission prompts and no access to your
  credentials)
- Starts work from a terminal or a phone with `agentide new`, which asks
  for repository, agent, effort, model and prompt, each defaulting to the
  last choice (so a thought away from the Mac becomes a branch)
- Answers Shortcuts and Siri with Start Agent Session, Show Worktree, Open
  Pull Requests and What Needs Me (so a Shortcut on your phone starts work
  with no SSH)

### 👀 Watch and steer

- Shows every agent's state, working, idle, done, waiting on input or
  exited, from `herdr`'s own detection (so one glance says who needs you)
- Groups worktrees by repository with unread activity, open pull requests,
  merge conflicts, uncommitted work and how far each branch has drifted from
  what was pushed, and adopts worktrees made outside the app (so nothing
  running is invisible)
- Lists directories of your own beside a repository's worktrees (so work by
  hand sits beside the agents' work, and no agent ever runs in it)
- Says what a pull request is doing in GitHub's own icons, one glyph per
  fact (checks a dot, approval a tick, changes requested a diff, a conflict
  a warning), its checks and queued merges watched until they settle (so
  the sidebar is the dashboard and no two badges look alike)
- Opens a pull request as a draft or ready for review, chosen by the
  icon the row will carry (so an agent's first attempt can go up as
  something to read rather than something to merge)
- Commits some of the uncommitted files rather than all of them, ticking
  the ones to take and drafting the message beside them (so one agent's
  worktree can land as more than one commit)
- Edits with syntax highlighting, `.editorconfig` indentation, page guides
  at columns 80 and 118 and a change bar beside every uncommitted line
  (so the editor says what is yours before the diff does)
- Marks a worktree whose pane has been holding several cores for ten
  minutes, naming what is running (so one runaway command cannot quietly
  starve every other agent on the machine)
- Notifies when an agent finishes or needs input, badges the Dock and plays
  a chime per event (so you never sit polling a terminal)
- Renders terminals locally from `herdr`'s control stream, reflows copied
  prose while keeping code exact, and copies a pane's whole output from its
  menu (so terminals feel native and answers paste whole)
- Takes a pasted or dropped file or screenshot straight into the agent (so
  Cmd-V after Cmd-Shift-4 is enough)
- Commits work an agent forgot to commit, clearly authored as such (so
  nothing is stranded in a worktree)

### 🔍 Review

- Presents the conversation beside a pull-request-style, syntax-highlighted
  diff with generated files hidden and the pull request's conversations
  inline under their files (so you review the way you would on GitHub)
- Reviews uncommitted work, the last commit, what is not yet pushed, the
  whole branch or any single commit (so a branch of ten commits reviews
  commit by commit)
- Edits uncommitted work in place in its diff, every line the file still
  holds a field, and deletes a never-committed file after asking (so small
  fixes need no other app)
- Rejects individual lines of the last commit to amend it, and edits commit
  messages (so a review verdict is one click, not a rebase)
- Edits files in a built-in highlighted editor, renders Markdown, and takes
  over whatever a shell command opens through the bundled `agentide`
  command (so `git rebase -i` needs no terminal editor)
- Speaks editor shorthand: Cmd-/ toggles the language's line comment, Tab
  and Shift-Tab indent and dedent at the file's own unit (tabs where the
  file uses tabs), Return carries the line's indentation, Option-Up and
  Option-Down move lines, Cmd-D duplicates them, Cmd-Shift-K deletes
  them, and saving strips trailing whitespace and guarantees a final
  newline (so review-time fixes type the way your editor taught you)
- Reads the project's `.editorconfig` and does what it says: the
  indentation Tab inserts, the width tabs render at, and whether saving
  tidies whitespace and final newlines (so a fix here matches the
  project's own style, not this app's guess)
- Opens that editor beside the diff or, from any conversations page,
  filling the centre pane, and moves the open file between the two; an
  agent session always wins the centre back, its file stepping aside
  saved (so editing sits beside reviewing, and never over an agent)
- Previews web pages in an embedded browser and opens a shell running as
  your own user (so verifying behaviour never leaves the window)
- Selects like a document: a drag crosses lines in a history diff's hunks,
  copies leaving the line numbers behind, and crosses messages in the
  Messages tab (so several lines land in a prompt or report in one go)
- Finds with Cmd-F everywhere and never turns quotes curly or dashes long
  (so code and commit messages survive being typed)

### 🚢 Ship

- Pushes branches, saying what each push sends and whether a rebase would
  move the base, sign commits or both; a rebase integrates a remote that
  moved and a rewritten one is replaced on the next push (so no push ends
  in a terminal)
- Opens pull requests from an in-app form drafted from the branch's commits
  by the on-device model, the repository's template filled in with its AI
  disclosure, labels attached, and a fork used when the repository is not
  yours (so shipping needs no retyping)
- Stacks branches in one worktree, derived from git rather than recorded,
  each pull request opening against the branch below and the stack rebased
  and pushed bottom up (so a stack is one checkout and no bookkeeping)
- Copies unresolved review comments and failing CI logs into a prompt,
  condensed; resolves conversations, changes labels, resolves conflicts and
  merges or enables automerge, each with a click (so the last mile is not
  the slowest)

### 🧹 Tidy up

- Deletes a worktree and its branch once its pull request merges, wherever
  the merge happened (so finished work disappears without ceremony)
- Deletes a repository's checkout only while nothing in it could be lost,
  saying what holds it back otherwise (so a repository leaves as easily as
  a worktree, never with work in it)
- Keeps every conversation a repository has ever run browsable and
  resumable after its worktree is gone (so tidying up never loses one)

### 🛟 Resilience

- Keeps sessions in `herdr` under the sandbox user, not the app (so agents
  survive the app quitting, crashing or updating)
- Backs up each worktree's newest conversation to iCloud Drive (so the
  sandbox user is disposable)
- Defers idle sleep while agents run and resumes sessions that sleep killed
  (so a long response survives you walking away)
- Shows what a pane is waiting on until it has an answer, and an empty
  state only once proven empty (so a blank pane is never a lie)
- Collects every failure and status message into a Messages tab (so
  nothing scrolls past unseen)

## 🚫 Out of Scope Features

- A general-purpose IDE (use your preferred editor for long editing
  sessions; the built-in one is for review-time fixes)
- Windows or Linux support (being a native macOS app is the point)
- Replacing sandvault (AgentIDE drives it; sandboxing policy stays there)
- Running agents outside the sandbox (the agents' own flags exist if you
  must)
- Team, multi-user or hosted features (one developer, one Mac)
- An agent marketplace or bundled models (bring your own agent CLI)
- A native iOS app (SSH into `herdr` from any iOS client instead)
- A built-in updater or a Mac App Store build (Homebrew's cask updates it;
  the App Store sandbox forbids running agents as another user)

## 📋 Requirements

- **macOS** Golden Gate (27) or later
- [Homebrew](https://brew.sh) (installs the dependencies below)
- [sandvault](https://github.com/webcoyote/sandvault) (creates the sandbox
  user and shared workspace)
- [`gh`](https://cli.github.com) authenticated as you (it stays with your
  user; agents never see it)
- [`herdr`](https://herdr.dev) and [`mosh`](https://mosh.org) (installed
  by `script/bootstrap` via the `Brewfile`; `mosh` only matters from a
  phone)
- **Xcode** 27 or later (only needed to build from source)

## 🖥️ Usage

Every release on the
[releases page](https://github.com/MikeMcQuaid/AgentIDE/releases) is an
`AgentIDE-<version>.zip` holding `AgentIDE.app`, signed with a Developer
ID certificate and notarised by Apple so it opens without a Gatekeeper
warning: unzip it and move the app to `/Applications`.

Releases will also ship as a Homebrew cask
(`brew install --cask agentide`) once the cask exists; `brew upgrade`
will then update the app, which has no updater of its own.

To run the current source instead:

```bash
git clone https://github.com/MikeMcQuaid/AgentIDE
cd AgentIDE
script/bootstrap
script/install
open /Applications/AgentIDE.app
```

`script/bootstrap` installs the `Brewfile` dependencies and generates the
gitignored Xcode project; `script/install` builds and copies the app into
`/Applications`, so the copy you run survives rebuilds.

A shell pane runs your login shell with `AGENTIDE=1` set and the bundled
`agentide` command on `PATH`, so shell files can hand editing back to the
app:

```bash
if [ -n "${AGENTIDE}" ]; then
  export EDITOR="$(command -v agentide) --wait"
  export VISUAL="${EDITOR}"
fi
```

`agentide .` from any terminal switches the window to the worktree or
checkout you are in.

### 🚀 Releasing

Run the **Release** workflow from the Actions tab on `main` with a bare
`MAJOR.MINOR.PATCH` version such as `0.1.0`: three integers, with no
`v`, prerelease suffix or build metadata. The workflow validates and
locally tags the commit before building, so the tag becomes the app's
version as well as the GitHub release and zip name. It pushes the tag
only after signing and notarisation succeed. No new commit or push is
needed: dispatching it builds the current `main` commit. A push that
touches the release workflow, packaging scripts or metadata creates the
reserved local test tag `9999.0.0`, signs and notarises as a dry run but
publishes nothing; Dependabot skips that step because GitHub withholds
its secrets.

### 📱 From a phone

Sessions are reachable over SSH as the sandbox user, and
[Moshi](https://getmoshi.app) is the client that just works with this
flow: it speaks `mosh`, so a phone changing network keeps its session.
Only two things are particular to sandvault and `herdr`; harden `sshd`
however you otherwise would.

1. The sandbox user's home is built from a template sandvault owns, so
   the client's key goes into that template and the home is rebuilt (a
   sandvault upgrade replaces the template, so keep this in your dotfiles
   if it must stay automatic):

   ```bash
   guest_keys="$(brew --prefix sandvault)/libexec/guest/home/.ssh/authorized_keys"
   cat "${HOME}/Downloads/moshi.pub" >>"${guest_keys}"
   sv --rebuild build
   ```

2. `agentide new` needs the shared workspace named, which a login from
   outside the sandbox does not inherit, in
   `/etc/ssh/sshd_config.d/000-agentide.conf` with your own user name and
   path, then Remote Login on for that account:

   ```text
   Match User sandvault-mike
       SetEnv SHARED_WORKSPACE=/Users/Shared/sv-mike
   ```

Alias the command in the sandbox user's shell configuration, which also
names the session:

```bash
alias an='/Applications/AgentIDE.app/Contents/Resources/bin/agentide new'
export HERDR_SESSION=agentide
```

Connect as `sandvault-<you>` and run `herdr`: one attach presents every
agent workspace, `an` starts a new session, and every agent launched
inside the sandbox is reachable, so a session steered from the phone is
the same session.

## ⚙️ Configuration

Everything a user changes lives in the Settings window (Cmd-,):

- **General**: the agent, model and effort new sessions start on, whether
  commits must be signed, the browser Cmd-click opens and the way to the
  session manager
- **Notifications**: for a finished turn, a question asked of you and
  unread output, whether each notifies, counts in the Dock badge and what
  it sounds like
- **Editor**: the external editor command Cmd-click on a file runs, and
  the monospace font and size every code surface shares
- **Advanced**: where repositories and worktrees live, how often the
  system is re-read, whether idle sleep is deferred and the performance log

Two files in the shared workspace are the app's own: `user/` is the
template sandvault syncs into the sandbox home, where the app keeps its
agent hooks and where your keys and shell configuration go, and
`agentide/session-defaults` remembers what the new session form and
`agentide new` last chose. The app also keeps `[worktrees] directory` in
`herdr`'s own configuration pointed at its layout, so `herdr worktree
create` lands where the sidebar looks.

Environment variables, for shell files and scripts:

| Variable | Set by | Meaning |
| --- | --- | --- |
| `AGENTIDE` | the app, in shell panes | `1`, so shell files know they are inside the app |
| `SHARED_WORKSPACE` | you, for remote logins | the shared workspace `agentide` reads, when a login did not inherit it |
| `HERDR_SESSION` | your shell configuration | the `herdr` session name, `agentide` for the installed app |
| `AGENTIDE_SESSION` | the app, per pane | the session's label, which the agent hooks attribute events by |
| `AGENTIDE_EDITS` | the app, in shell panes | where `agentide --wait` spools the edit it is waiting on |
| `AGENTIDE_COLOR` | you | forces colour in `agentide`'s output where no terminal is detected |
| `AGENTIDE_PERFORMANCE_LOG` | you | turns the performance log on, as `script/performance-log on` does |
| `AGENTIDE_DEVELOPMENT_TEAM` | you, running `script/test` | the Apple team id that signs the app and the App Intents test runner alike, which the framework requires; unset, the bundle is skipped |
| `AGENTIDE_SKIP_INTENT_TESTS` | you, running `script/test` | leaves the App Intents bundle out even with a team set |
| `AGENTIDE_DRY_RUN` | you, running `agentide new` | prints what it would make instead of making it |

## 🚧 Status

Unstable and changing daily. AgentIDE is being designed exclusively for
[@MikeMcQuaid](https://github.com/MikeMcQuaid)'s personal workflow;
nothing here promises to suit anyone else's, interfaces and behaviour
break without notice and there is no support.

See [ARCHITECTURE.md](ARCHITECTURE.md) for how AgentIDE is designed and
[AGENTS.md](AGENTS.md) if you are working on this repository, human or
agent.

## 📄 Licence

[GNU Affero General Public License v3.0](LICENSE). If you reuse or adapt the
source the AGPL terms apply, including the network-use clause.

[Octicons](https://github.com/primer/octicons) are vendored in
`App/Assets.xcassets` and licensed under the
[MIT License](https://github.com/primer/octicons/blob/main/LICENSE).
