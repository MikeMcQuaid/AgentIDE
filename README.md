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

- **Creates** or clones repositories into the shared workspace, symlinked
  into your home directory, so you and the sandbox share one checkout
- **Creates** a worktree and branch from a typed problem statement, an
  issue or a pull request, narrating each step until the agent is up
- **Starts** Claude Code or Codex CLI in `herdr` inside the sandbox, with
  no permission prompts and no access to your credentials
- **Starts** work from a terminal or a phone: `agentide new` asks for
  repository, agent, effort, model and prompt, each defaulting to what was
  last chosen, and attaches to the session it makes
- **Answers** Shortcuts and Siri: Start Agent Session, Show Worktree, Open
  Pull Requests and What Needs Me, so a Shortcut on your phone starts work
  on the Mac with no SSH

### 👀 Watch and steer

- **Shows** every agent's state, working, idle, done, waiting on input or
  exited, straight from `herdr`'s own detection, in the sidebar and the
  session strip
- **Groups** worktrees by repository with unread activity, open pull
  requests, merge conflicts, uncommitted work and how far each branch has
  drifted from what was pushed; worktrees made outside the app are adopted
- **Lists** directories of your own beside a repository's worktrees, for
  work by hand that no agent ever runs in
- **Says** what a pull request is doing in GitHub's own icons: state,
  number, a CI dot, review verdict and unresolved conversations, with
  in-flight checks and queued merges watched until they settle
- **Notifies** you when an agent finishes or needs input, badges the Dock
  and plays a chime per event, chosen in Settings
- **Renders** terminals locally from `herdr`'s control stream, so
  selection, copying and pasting behave like any other Mac text while the
  sessions keep running elsewhere; copies of prose reflow for pasting, code
  stays exactly as copied, and the pane's menu copies its whole output
- **Takes** a pasted or dropped file or screenshot straight into the agent
- **Commits** work an agent forgot to commit, clearly authored as such
- **Configures** itself in one Settings window: default agent, model and
  effort, notifications, the external editor and browser, locations,
  fonts, cadences and whether commits must be signed

### 🔍 Review

- **Presents** the conversation beside a pull-request-style diff, syntax
  highlighted, generated files hidden, with the open pull request's
  conversations inline under their files and resolvable there
- **Reviews** uncommitted work, the last commit, what is not yet pushed or
  the whole branch, and any single commit on its own
- **Edits** uncommitted work in place in its diff (click into a file and
  every line it still holds is a field; removed lines are history), and
  deletes a never-committed file after asking
- **Rejects** individual lines of the last commit to amend it, and edits
  commit messages
- **Edits** files in a built-in highlighted editor, Markdown rendered at
  the press of a button, and takes over whatever a shell command opens
  (`git rebase -i`, a commit message) through the bundled `agentide`
  command
- **Previews** web pages in an embedded browser that remembers each
  worktree's page, and opens a shell running as your own user
- **Finds** with Cmd-F everywhere, and never turns quotes curly or dashes
  long

### 🚢 Ship

- **Pushes** branches, showing what each push sends and whether a rebase
  would move the base, sign commits or both; a rebase integrates a remote
  that moved, and a rewritten one is replaced on the next push with no
  terminal step
- **Opens** pull requests from an in-app form: title and body drafted from
  the branch's commits by the on-device model, the repository's template
  filled in and its AI disclosure written, labels attached, and a fork
  created and used when the repository is not yours to push to
- **Stacks** branches in one worktree, derived from git rather than
  recorded: each pull request opens against the branch below, the stack's
  Rebase and Push put every branch back in place and push them bottom up,
  and GitHub is told the stack it belongs to
- **Copies** unresolved review comments and the failing CI runs' logs into
  a prompt, condensed to what a fix needs; resolves conversations, changes
  labels, resolves conflicts and merges or enables automerge, each with a
  click

### 🧹 Tidy up

- **Deletes** a worktree and its branch once its pull request merges,
  wherever the merge happened
- **Deletes** a repository's checkout, offered only while nothing in it
  could be lost, and says what holds it back otherwise
- **Keeps** every conversation a repository has ever run browsable and
  resumable, even after its worktree is gone

### 🛟 Resilience

- **Survives** the app quitting, crashing or updating: sessions belong to
  `herdr` and the sandbox user, not to the app
- **Backs up** each worktree's newest conversation to iCloud Drive, so the
  sandbox user is disposable
- **Defers** idle sleep while agents run and resumes sessions that sleep
  killed
- **Shows** what every pane is waiting on until it has an answer, and an
  empty state only once it has been proven empty
- **Collects** every failure and status message into a Messages tab that
  is always there

## 🚫 Out of Scope Features

- Being a general-purpose IDE (the built-in editor is for review-time fixes)
- Windows or Linux support (being a native macOS app is the point)
- Replacing sandvault (AgentIDE drives it; sandboxing policy stays there)
- Running agents outside the sandbox
- Team, multi-user or hosted features (one developer, one Mac)
- An agent marketplace or bundled models (bring your own agent CLI)
- A native iOS app (remote access is SSH into `herdr`)

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

```bash
git clone https://github.com/MikeMcQuaid/AgentIDE
cd AgentIDE
script/bootstrap
script/install
open /Applications/AgentIDE.app
```

`script/bootstrap` installs the `Brewfile` dependencies and generates the
gitignored Xcode project; `script/install` builds and copies the app into
`/Applications`, so the copy you run survives rebuilds. Releases ship as a
Homebrew cask, so `brew upgrade` moves the app on; there is no Mac App
Store build, since its sandbox forbids running agents as another user.

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
