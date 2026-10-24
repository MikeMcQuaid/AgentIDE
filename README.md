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
- Opens the workspace immediately after initial setup, checks prerequisites in the background and shows setup guidance only when a check fails.
- Starts sessions while others are launching and keeps failed launches available to retry with their original choices.
- Starts a new task from a prompt, GitHub issue, pull request or security advisory in triage or draft.
- Starts sessions on several picked issues or pull requests at once, each in its own worktree with the same optional prompt.
- Starts an agent on a listed pull request from its context menu, or straight away without a prompt by holding Option.
- Starts a session on top of another branch's work, with the repository’s context menu prefilling the selected branch, so a large change splits into stacked pull requests.
- Schedules repository prompts daily, weekly or monthly while AgentIDE is open, catching up once after reopening or waking.
- Shows agent activity, pull requests, CI checks and uncommitted changes across repositories in one sidebar.
- Keeps agents running when the app closes and conversations browsable and resumable after their worktrees are deleted.
- Scrolls the agent conversation under the pointer.
- Switches between visited agents instantly, preserving their terminal size and content.
- Reviews uncommitted changes, individual commits or whole branches as syntax-highlighted diffs with inline pull request comments.
- Shows local AI findings beside matching code in Review and with captured code in PR conversations, and copies them together with GitHub comments using the existing conversation copy buttons.
- Requests reviews from another agent or your choice of Copilot or CodeRabbit.
- Reviews committed changes with their full commit messages without a diff size limit, while uncommitted review snapshots remain limited to 256 KiB.
- Gathers local findings, required CI failures, both bots’ comments, GitHub Code Quality and security comments and verified private reviewers’ comments, including nitpicks, for Copy all and autofix.
- Omits CodeRabbit’s labels, tracking comments and review information from copied feedback and autofix prompts to save agent context.
- Remembers local and remote reviewer choices for new pull requests and worktrees in each repository.
- Addresses existing local findings, ready GitHub feedback and unfinished local changes before requesting fresh reviews, preserving unrelated edits and the automatic-push opt-in.
- Offers an explicit Start loop action that completes local review rounds before shared GitHub CI and review rounds, with separate limits of one to three and automatic pushing off by default for each PR.
- Applies autofixes through the branch's existing agent session, including when local reviewing is disabled or uncommitted work is present, and explains any wait preventing delivery.
- Asks the fixing agent to commit unfinished autofix changes, then pushes verified commits and updates published branches above them when automatic pushing is enabled.
- Reconciles manual commits, signing and confirmed pushes with autofix progress without repeating handled feedback.
- Wakes the configured commit signer when starting autofix and opens a Push retry popover if automatic signing or pushing fails.
- Keeps the sidebar and agent notifications responsive while autofix waits for GitHub or commit signing.
- Shows autofix progress in the main agent pane while local reviewers use their own prompts without the main conversation's context.
- Rotates the autofix icon in the toolbar and sidebar while a loop is running and distinguishes loops that have not started, are running or have finished, stopped or failed.
- Notifies and plays the chosen completion or attention sound when an autofix loop finishes or needs you, and resets loop progress on app launch while preserving duplicate-prevention and thread-resolution records.
- Opens review and autofix controls from one feedback-loop toolbar icon, with a single play/stop control and status beneath it only while a loop is active.
- Shows reviewer icons in menus and infers the PR’s review button from existing bot comments, asking which bot to request when neither or both have commented.
- Keeps Review, Copy all and loop actions together with progress and expandable activity, with a local-only autofix popover in Review and GitHub and push controls in PR.
- Sizes popovers to their contents, scrolling only when they would exceed the screen.
- Renders Markdown previews, PR descriptions, conversations and review comments consistently with GitHub-style headings, nested lists, task lists, tables, code, alerts and expandable details.
- Selects and copies rendered conversation text and author names.
- Shows PR comment headers with cached GitHub avatars and dates, keeping only the latest CodeRabbit or Copilot timeline entry with its total comment count and hiding bot commands, billing notices and promotions.
- Keeps local review controls separate from GitHub automation and exposes reviewer errors with the model, effort and captured output.
- Completes local review and commit rounds before pushing and gathering GitHub feedback, then verifies the final CI and review results before reporting success or continued failure.
- Resolves review threads marked for the next push only after GitHub confirms a new head, preserving threads that receive further comments.
- Collapses resolved conversations and those marked for the next push, keeping contents expandable and copyable with a distinct pending icon.
- Filters compact CI checks by requirement and progress beside PR conversation tabs, with full workflow names, event types, required status and timings.
- Opens individual CI logs with collapsible Actions groups, highlighted diagnostics and optional timestamps, copying complete logs while other checks run.
- Copies failing CI logs with a count of finished checks, clearing the clipboard immediately while logs load.
- Preserves CI errors, warnings and failure markers such as ❌ with surrounding diagnostics and stack traces in Checks, Copy all and autofix prompts, including failures in the middle of long logs.
- Reads complete failed required job logs and condenses them into bounded autofix and clipboard output, prioritising errors over warnings and including diagnostics outside GitHub's recognised steps.
- Copies pull request URLs and branch names from context menus on pull request rows, headers and actions, including stacked pull requests.
- Edits code with syntax highlighting, search and change tracking, keeping each worktree's open file and scroll position.
- Runs multiple shell tabs in each worktree for development servers, tests and other commands.
- Commits or amends selected files with messages drafted by Apple's on-device model.
- Signs, rebases and pushes branches in one action before opening pull requests, including forks and stacked branches.
- Assigns issues linked by closing references to you after opening a pull request.
- Browses and drafts every local stack entry, publishing branches and opening pull requests in order.
- Creates and extends GitHub stacks directly and shows their reported positions even when other branches are not available locally.
- Merges pull requests and stacks, enables automerge for waiting standalone pull requests with or without a merge queue and shows when automerge is enabled or a pull request is queued.
- Can automatically remove clean, fully merged worktrees and branches when it observes a merge, leaving the selected worktree and main checkout in place.
- Notifies you when an agent finishes or needs input.
- Starts and steers work through Shortcuts and Siri.
- Offers an [iPhone companion](#-iphone-companion) for switching between running agents and starting work in existing repositories over SSH.

## 🚫 Out of Scope

- Windows or Linux support; being a native macOS app is the point.
- Running agents without a sandboxed non-admin user.
- Team, multi-user or hosted features: one developer, one Mac.
- An agent marketplace or bundled models; bring your own agent CLI.
- An updater or a Mac App Store build; Homebrew's cask upgrades it, and the App Store sandbox forbids running agents as another user.

## 📋 Requirements

- An Apple silicon Mac running macOS Tahoe (26) or later.
- [Homebrew](https://brew.sh), with Git, [`gh`](https://cli.github.com), [`herdr`](https://herdr.dev) and [ripgrep](https://github.com/BurntSushi/ripgrep) installed.
- [sandvault](https://github.com/webcoyote/sandvault), which creates the sandbox user and the shared workspace.
- [`gh`](https://cli.github.com) authenticated as you; it stays with your user and agents never see it.
- Claude Code or Codex CLI installed and signed in inside sandvault.
- Xcode 27 or later, only to build from source.

## 📦 Installation

```bash
brew install --cask agentide
```

The [`agentide` cask](https://github.com/Homebrew/homebrew-cask/blob/main/Casks/a/agentide.rb) installs the latest release, and `brew upgrade` updates it.
Releases are signed with a Developer ID certificate and notarised by Apple.

You can also download `AgentIDE-<version>.zip` from the [releases page](https://github.com/MikeMcQuaid/AgentIDE/releases), unzip it and move `AgentIDE.app` to /Applications.

To run the current source instead:

```bash
script/bootstrap
script/install
```

## ⚙️ Configuration

Settings (Cmd-,) controls:

- **General**: Choose session defaults, commit signing requirements and the external browser.
- **Schedules**: Manage each repository's recurring prompts, agent choices and next run.
- **Sessions**: Inspect and stop running agent sessions and browser pages.
- **Review**: Choose the reviewer, model and effort and customise the local review, local fix, GitHub fix and commit follow-up prompts.
- **Notifications**: Choose which events notify, badge the Dock or play a sound.
- **Fonts**: Customise fonts and sizes throughout the Mac app.
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

## 📱 iPhone companion

The iPhone companion lets you view and steer running agents and start work in existing repositories over SSH.
Established connections stay open across app switches when iOS allows, with automatic reconnection after interruptions.
Its session list shares the Mac's sidebar order, repository avatars, agent icons, activity indicators, branch names and local Git status.
Interface text follows your iPhone's system text size, with a separate terminal size control in Settings.
Run `script/bootstrap` and `script/install` on your Mac to install the matching Mac build, then select a signing team in Xcode and build the `AgentIDE-iOS` scheme for iOS 26 or later.
Enter your Mac's IP address or hostname and your Mac username; the companion adds the `sandvault-` prefix for the sandbox account.
Keep the SSH port at `22` unless your Mac uses another port, and choose `agentide` for the installed Mac app or `agentide-dev` for a development build from the session menu.
Install the public key shown in Settings using the steps below.
Confirm the Mac's host key on first connection against `ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub`; a changed key requires an explicit replacement in Settings.

1. Copy the public key from iPhone Settings to your Mac's clipboard, for example with Universal Clipboard.
   The commands below save it as `~/Downloads/agentide-phone.pub`, add it to sandvault's guest template and rebuild the sandbox home.
   A sandvault upgrade replaces the template, so keep this in your dotfiles:

   ```bash
   printf '%s\n' "$(pbpaste)" >"${HOME}/Downloads/agentide-phone.pub"
   guest_keys="$(brew --prefix sandvault)/libexec/guest/home/.ssh/authorized_keys"
   cat "${HOME}/Downloads/agentide-phone.pub" >>"${guest_keys}"
   sv --rebuild build
   ```

2. Name the shared workspace for logins from outside the sandbox, which do not inherit it, in `/etc/ssh/sshd_config.d/000-agentide.conf` with your own user name and path in place of `<you>`, then turn on macOS's Remote Login for that account:

   ```text
   Match User sandvault-<you>
       SetEnv SHARED_WORKSPACE=/Users/Shared/sv-<you>
   ```

Choose **Connect** in the iPhone app to see the same sessions as your Mac.

## 🛠️ Development

- `script/bootstrap`: install `Brewfile` dependencies and generate the Xcode project with XcodeGen
- `script/build`: build the app in Release, or Debug with `XCODE_CONFIGURATION=Debug`; `AgentIDE.app` in the repository root symlinks its output
- `script/version`: print the version and build number git says, which scripted and Xcode builds both use
- `script/install`: stream the build output, stop the old app, copy the new app to /Applications and launch it automatically
- `script/test [--sanitize address|thread] [swift test options]`: unit, integration and App Intents tests, optionally checking memory accesses or data races
- `script/style [--fix]`: SwiftLint and SwiftFormat, every rule on
- `script/analyze`: static analysis and dead code
- `script/zip` and `script/package`: zip, sign and notarise a release
- `script/attach`: attach this terminal to the sandboxed `herdr` session

CI checks the Mac and iPhone apps for regressions and provides downloadable builds for testing.
See [ARCHITECTURE.md](ARCHITECTURE.md#dependencies-and-toolchain) for build, testing and analysis details.

To publish a release, run the **Release** workflow from the Actions tab on `main` with a bare `MAJOR.MINOR.PATCH` version.
The workflow validates and publishes the app automatically; see the [release process](ARCHITECTURE.md#releases) for details.

## 🚧 Status

Stable but changing regularly.
AgentIDE is being designed exclusively for [@MikeMcQuaid](https://github.com/MikeMcQuaid)'s personal workflow; nothing here promises to suit anyone else's, interfaces and behaviour may break without notice and there is no support.

## 📮 Contact

[Mike McQuaid](mailto:mike@mikemcquaid.com)

## 📄 Licence

[AGPL-3.0](LICENSE).
If you reuse or adapt the source the AGPL terms apply, including the network-use clause.

[Octicons](https://github.com/primer/octicons) are vendored in `App/Assets.xcassets` and licensed under the [MIT License](https://github.com/primer/octicons/blob/main/LICENSE).
