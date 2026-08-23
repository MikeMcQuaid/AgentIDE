# Agent Instructions for MikeMcQuaid/AgentIDE

Most importantly: run `script/style --fix` before finishing any change,
read `README.md` and `ARCHITECTURE.md` before changing anything and
update them in the same commit when behaviour they describe changes.
This repository is readme-driven: documentation leads, code follows.

AgentIDE is a native SwiftUI macOS app for running, steering and
reviewing sandboxed AI coding agents. See the Status section of
`README.md` for the slice order.

Write sentence-case imperative commit messages without
conventional-commit prefixes such as `feat:`, `fix:` or `chore:`.

## Commands

- `script/bootstrap`: install `Brewfile` dependencies and generate
  `AgentIDE.xcodeproj` with XcodeGen
- `script/build`: build the app with xcodebuild
- `script/install`: build, then copy the app into /Applications so
  the running copy survives rebuilds
- `script/test`: run the unit and integration tests
- `script/analyze`: static analysis (SwiftLint analyzer and, on the
  host or CI, periphery for dead code)
- `script/style`: run all linters; `--fix` also applies safe fixes
- `script/attach [workspace]`: attach this terminal to the sandboxed
  herdr session, or list its workspaces when run without arguments
  (works as the host user or inside the sandbox)

## Repository Structure

- `README.md`: user workflow and features; the product specification
- `ARCHITECTURE.md`: system design, packages and data flows
- `AGENTS.md`: this file; `CLAUDE.md` is a symlink to it
- `Package.swift`, `Sources/`, `Tests/`: the Swift package targets
- `App/`: the app shell; `project.yml` defines the XcodeGen target
  (the generated `.xcodeproj` stays gitignored)
- `bin/`: commands shipped inside the app bundle (the `agentide`
  editor shim a shell pane puts on its `PATH`)
- `script/`: development tasks
- `Brewfile`: development dependencies
- `.github/workflows/tests.yml`: CI

## Code Standards

- Swift 6.4 with strict concurrency: App and Feature targets use
  MainActor default isolation; Domain and DataAccess are nonisolated
- Every SwiftLint and SwiftFormat rule is enabled; disable per line
  with a comment explaining why (configuration excludes only rules
  that conflict with other enabled rules or tools, with reasons)
- SwiftLint needs the full Xcode selected via xcode-select;
  CommandLineTools alone cannot load SourceKit
- UK English (organised, colour) in documentation, comments and UI
  strings; proper nouns keep their official spellings
- Keep comments minimal; prefer self-documenting code
- Two-space indentation, four-space for Swift (see `.editorconfig`)

### UI Principles

- One implementation per concern: terminals, editors, conversation
  views, markdown rendering, git access and GitHub access each have
  exactly one shared component or client. Before adding a second
  approach to any such concern, or duplicating behaviour that an
  existing surface already provides, get explicit confirmation.
- Transitions that wait on anything (resuming a session, fetching
  remote data, cloning) show a loading state that fills the pane
  instantly; never leave the old content interactive so that the
  result pops over it later. The bar is any actual or possible
  delay over half a second. A transition made of several steps
  names each step and what it waits on as it happens, through
  `LaunchProgress`, and keeps something on screen changing at
  least once a second. The same holds for every pane whose data
  arrives later than the pane: it shows `LaunchProgressView` naming
  what it waits on until the first result lands, then snaps to the
  finished UI. An empty state ("Nothing running", "No changes")
  appears only once a load has proven it empty, never before.
- Buttons follow Apple HIG and Liquid Glass, in that order, then
  this app's conventions: at most one primary action per surface,
  rendered prominent and bound to Cmd-Return when the surface takes
  text input; every other button is plain glass, icon-only with
  hover help when the icon is unambiguous and short text otherwise.
  Order buttons in the sequence they are expected to be clicked,
  left to right, primary last; put counts in the label and
  explanations in hover help. Slow or unrepeatable actions go
  through `BusyButton` and lock any inputs they read or write
  while running.

### Platform Notes

Hard-won on macOS 27 beta; check before assuming they expired.

- SwiftUI `List`/`Section` crash AppKit's outline diff when rows are
  removed conditionally; the sidebar is a plain `ScrollView`.
- `NavigationSplitView` floats a sidebar toggle that survives
  `.toolbar(removing: .sidebarToggle)` and covers nearby controls,
  and `HSplitView` neither persists divider positions nor honours
  ideal widths; the window is plain panes with `PaneDivider`
  drag handles, `SidebarMaterial` supplying the sidebar blur and
  the sidebar never hiding (only resizing).
- Shape-style `.background` fills expand into ignored safe areas
  by default and paint over sibling rows in the titlebar band;
  pass `ignoresSafeAreaEdges: []` inside panes that ignore the
  top safe area.
- Toolbars need a non-empty `.principal` item and one trailing
  `ToolbarItemGroup`, or items reflow to the leading edge; segmented
  pickers in toolbars also move unpredictably, so tabs are buttons.
- `@State` objects outlive view re-initialisation: rebuild models
  when their identity input changes (see `ReviewView`).
- `Text("\(someInt)")` applies digit grouping; use `String(_:)`.
- Trailing closures after multiline calls fight SwiftFormat; keep
  them single-line or make the closure a non-final argument.
- Length-limit splits use cross-file extensions; same-file grouping
  extensions are banned by SwiftLint.
- GitHub: never repository-wide `gh pr list` on large repositories
  (the GraphQL gateway times out); query per branch, cache answers,
  keep the last good value on failure. The expensive fields are
  checks, mergeability and review decision: wide listings fetch
  light fields only and enrich one pull request on selection.
- `@AppStorage` keys are the cross-module signal bus (utility tab
  name, finder mode and focus, browser address); tabs travel by
  name, never index, so reordering cannot repoint them. A repeated
  request needs a counter beside its value: writing the same string
  publishes no change, so asking twice for one page did nothing.
- Octicon SVG imagesets in `App/Assets.xcassets` render as template
  images; `ChecksStyle` maps GitHub states to them.
- `cannot execute tool 'metal' due to missing Metal Toolchain` breaks
  every build of SwiftTerm-dependent targets, which is the app and
  most tests. The toolchain is a downloadable asset each user mounts
  under its own home, but mounts are visible to everyone: when the
  host user has it mounted, Xcode finds that mount, cannot read it
  across the sandbox boundary and refuses rather than making its own.
  Eject the host user's mount, as the host user, then ask for the
  component again inside the sandbox, which mounts its own copy at
  `<hash>_1`:

  ```bash
  cd ~/Library/Developer/DVTDownloads/MetalToolchain/mounts
  diskutil eject <hash>
  xcodebuild -downloadComponent MetalToolchain  # in the sandbox
  ```

  The coordinator writes its failures to stderr, not `os_log`, so
  `log show` finds nothing however good the predicate is. Until it is
  fixed, `swift build --target AgentIDEDomain`, `--target
  AgentIDEData` and `--target AgentIDEDataTests` still typecheck,
  since none of them reach SwiftTerm.
- A binary Gatekeeper refuses dies with `zsh: killed` (rc 137) at
  exec and nothing in the sandbox explains why; `xattr -l` on it shows
  `com.apple.quarantine`, `spctl -a -t exec -vv` rejects it and the
  host's `log show` names `syspolicyd` with AgentIDE as the responsible
  app.
  Terminal works because it holds the Developer Tools privilege, which
  has no request API. Codex's command host is the known case, so
  `Quarantine` clears the attribute from the agent's install before
  every launch.
- herdr servers and their workspaces outlive the app, so changes to
  launch commands, workspace shapes or server behaviour often need
  the running `agentide` or `agentide-dev` herdr session stopped
  (`herdr session stop <name>` as the sandbox user, or `herdr server
  reload-config` for config alone) to take effect: when finishing
  such a change, tell the user exactly what to restart or stop.

### Required Before Each Commit

- Run `script/style --fix` and resolve anything it cannot fix
- Run `script/test` and `script/analyze` when Swift changed
- Run `script/analyze` again before opening or updating a pull
  request; unused imports and dead code otherwise surface in CI
  first (sandboxed runs reuse the analyze build's index store, so
  periphery's dead-code pass now runs everywhere)
- Reread changed documentation for UK English, working links and
  72-column wrapping of this file
- Confirm `README.md` and `ARCHITECTURE.md` still describe behaviour
  after your change

## Key Guidelines

1. Documentation first: update `README.md` and `ARCHITECTURE.md`
   before writing code whose behaviour they describe.
2. Never widen the sandvault sudoers rules or otherwise weaken the
   sandbox; treat all agent output as untrusted input.
3. Never run `gh` or any host-credentialled command inside the
   sandbox. The host fetches GitHub data and passes it into prompts;
   sandboxed pushes use per-repository deploy keys only.
4. Derive state from herdr, git and `gh` on demand rather than caching
   it. AgentIDE must be killable at any moment losing nothing, and
   every conversation must stay browsable and resumable after its
   session closes or its worktree is deleted.
5. Keep dependency directions clean: Domain depends on nothing,
   DataAccess and Features depend on Domain and App composes them.
6. Follow YAGNI and DRY: build only what the current slice needs and
   inline variables and functions used only once. For non-trivial
   parsing or protocol work, prefer widely used, well maintained
   libraries, Apple's own first (markdown parses through
   apple/swift-markdown), over bespoke reimplementations.
7. Keep agent-specific logic inside its adapter; everything else
   speaks one agent interface.
8. Describe third-party apps this project replaces by category, never
   by product name, in every committed file.
9. Never place app files in bare `/tmp`: cross-user files belong in
   the shared workspace or the owning user's home, per-user scratch
   in that user's macOS temporary directory, and test scratch in the
   gitignored `.test-scratch` of the checkout, which each run sweeps.
10. Keep diffs minimal and follow existing structure.
