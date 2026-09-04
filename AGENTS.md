# Agent Instructions for MikeMcQuaid/AgentIDE

Most importantly: run `script/style --fix` before finishing any change,
read `README.md` and `ARCHITECTURE.md` before changing anything and
update them in the same commit when behaviour they describe changes.
This repository is readme-driven: documentation leads, code follows.

AgentIDE is a native SwiftUI macOS app for running, steering and
reviewing sandboxed AI coding agents.

Write sentence-case imperative commit messages without
conventional-commit prefixes such as `feat:`, `fix:` or `chore:`.

## Commands

- `script/bootstrap`: install `Brewfile` dependencies and generate
  `AgentIDE.xcodeproj` with XcodeGen
- `script/build`: regenerate the Xcode project when sources
  changed, then build the app with xcodebuild
- `script/install`: build, then copy the app into /Applications so
  the running copy survives rebuilds
- `script/test`: run the unit and integration tests, then on the
  host the App Intents tests through `xcodebuild` (a UI testing
  bundle, since `AppIntentsTesting` drives the system's own runtime;
  they need `AGENTIDE_DEVELOPMENT_TEAM` set to a real team id, since
  the framework refuses a runner signed differently from the app, and
  `AGENTIDE_SKIP_INTENT_TESTS=1` leaves them out regardless)
- `script/analyze`: static analysis (SwiftLint analyzer and, on the
  host or CI, periphery for dead code)
- `script/style`: run all linters; `--fix` also applies safe fixes
- `script/performance-log [on|off|status]`: switch the installed
  app's performance log on or off (off by default; on, every process
  run, `gh` call and cache hit or miss lands in the shared
  `tmp/agentide/performance.log`)
- `script/attach [workspace]`: attach this terminal to the sandboxed
  herdr session, or list its workspaces when run without arguments
  (works as the host user or inside the sandbox)

## Repository Structure

- `README.md`: user workflow and features; the product specification
- `ARCHITECTURE.md`: system design, packages and data flows
- `AGENTS.md`: this file; `CLAUDE.md` is a symlink to it
- `Package.swift`, `Sources/`, `Tests/`: the Swift package targets
- `App/`: the app shell; `project.yml` defines the XcodeGen target
  (the generated `.xcodeproj` stays gitignored). `Package.swift`
  also carries these sources as `AgentIDEAppSources`, which builds
  no bundle and exists only so `swift build` type-checks them
- `bin/`: the `agentide` command shipped inside the app bundle: the
  editor shim a shell pane puts on its `PATH` (waiting only with
  `--wait`, and taking a directory anywhere inside a worktree or
  checkout to switch the window to it),
  and `agentide new`,
  which asks its way to a session over SSH the way the app does,
  defaulting to what the window last chose (published by the app as
  `agentide/session-defaults`). Nothing installs it: an SSH login
  aliases the bundled path. It speaks the way Homebrew's own scripts
  do, a blue `==>` before each step, bold labels, green defaults and
  bold `Warning:`/`Error:` labels, colour only on a terminal that has
  not set `NO_COLOR`. `CommandLineSessionTests` pins its names to
  `SessionName`
- `docs/`: the images `README.md` embeds
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
- Name every argument a shelled command takes: `gh` and git both
  fall back to whatever is checked out or configured, and code has
  no reason to lean on the shorthand a human types. `gh pr create`
  names `--head` and `--base`, a rebase names its branch
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
  delay over half a second; under that, show nothing rather than a
  flash. A wait that ends within a few seconds is a spinner under a
  title (`LaunchProgressView(spinner:)`). Only a transition that can
  run long (resuming, attaching, cloning) names each step and what
  it waits on as it happens, through `LaunchProgress`, and keeps
  something on screen changing at least once a second, the block
  pinned near the top of the pane so it grows downwards. Prefer
  showing the last known state instantly over showing a wait at all:
  the sidebar, the selection and every
  pane that can be cached paint before anything is read, and only
  what herdr owns is allowed to arrive late. Work that need not be
  serial is not: anything the launch does not depend on yet runs
  beside it. The same holds for every pane whose data
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
  explanations in hover help. A context menu of more than three
  items groups them with separators, the destructive item last in
  its own group. Slow or unrepeatable actions go
  through `BusyButton` and lock any inputs they read or write
  while running.
- State changes animate briefly (about 150 ms) and only where the
  change would otherwise jump: a disclosure chevron, rows appearing,
  a bar sliding in, a page fading over a pane. Nothing decorative,
  nothing slower, and never on a surface that is mid-drag or holds
  a live terminal.
- Semantic AppKit colours only in UI chrome: selection uses the
  system selection colours and greys out when the window is not
  key, text surfaces use `textColor` over `textBackgroundColor`.
  Literal white or black belongs only in terminal palettes.
- A shortcut or action that opens a surface with a text field
  focuses that field, and Escape closes or cancels what it opened.
  The window title always names the selection (repository and
  branch) even though the title bar hides it: Mission Control and
  the Window menu read it.

### Performance Principles

- Prefer events to polling: file changes arrive through FSEvents or
  dispatch sources, herdr changes through its own channel. A poll
  that remains must say in a comment why no event can serve it, and
  it slows to a safety tick while the window is occluded.
- Never read or decode files during view body evaluation. Models
  keep decoded state in memory (`MetadataStore` holds the one
  in-memory copy of the metadata) and views read that memory.
- A published model value changes only when something user-visible
  changed. No free-running timestamps or counters: row equality is
  what lets a poll tick redraw nothing.
- Memoise parsing: tree-sitter tokens, markdown blocks and
  attributed strings are cached by content and invalidated by
  content, never rebuilt per render.
- Budget process spawns: batch, cache or event-drive anything the
  performance log shows running more than a few times a minute at
  idle. Processes finish through termination handlers rather than
  blocking a thread, and refreshes already in flight coalesce
  rather than stack.
- First paint reads only memory and caches; anything slower starts
  after the window is up and fills in.

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
- An `NSViewRepresentable` whose `sizeThatFits` lays out the live
  view hangs the window and then kills it. `DiffHunkTextView` set
  its own text view's container size and called `ensureLayout` on
  its layout manager; a text view that is vertically resizable and
  tracks its container gets resized by that, so the measurement
  invalidated layout, SwiftUI asked again, and the display cycle
  never finished. AppKit gives up with `NSGenericException`,
  "marked as needing another Display Window pass, but it has
  already had more Display Window passes than there are views in
  the window" (Update Constraints overflows the same way). Measure
  on a container with no view attached, held as the coordinator.
  Nothing in the crash report names the app, and the reason is lost
  to `objc_exception_rethrow`; the log around the crash has it:

  ```bash
  log show --predicate 'process == "AgentIDE"' --info
  ```

  The symptoms lie about the cause: the scroll view's document
  flipped between 480 x 222 and 463 x 6567, a scroller's width
  apart, so both `.scrollIndicators(.never)` and macOS's overlay
  scrollers ("Show scroll bars: When scrolling") stopped the crash
  without touching it. What found it: swapping
  `-[NSView setNeedsUpdateConstraints:]` for a counting version,
  resetting the count each run-loop turn, and dumping every scroll
  view's frames and the live stack once a turn passed forty. The
  offending frame was ten deep in the fourth dump.
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
- `Validate plug-in "SwiftTermBuildInfoPlugin"` failing a build means
  a non-interactive `xcodebuild` met an untrusted package plugin
  (SwiftTerm 1.19 ships one); only the Xcode app can show the trust
  prompt, so every script passes `-skipPackagePluginValidation`.
- Xcode runs SwiftTerm's build tool plugin under `sandbox-exec`,
  which cannot nest, so `xcodebuild` cannot get past it in here
  however its flags are set: `CustomTask Generate SwiftTerm build
  information` fails with `sandbox_apply: Operation not permitted`,
  and regenerating the file by hand does not help, since the trigger
  beside it carries a fresh UUID per planning pass. `script/build`
  therefore uses `swift build --disable-sandbox` in the sandbox,
  which runs the same plugin unsandboxed and compiles every target,
  `App` included, through the `AgentIDEAppSources` target that
  exists for that alone. The bundle itself, and both of
  `script/analyze`'s passes, belong to the host and CI: SwiftLint's
  analyser wants a full `xcodebuild` log and reads a `swift build`
  one as a confident zero, and periphery cannot load the manifest
  here either. `script/analyze` says so and stops rather than
  passing on nothing.
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
- A fullscreen space sent to another display leaves the display it
  came from black until a space switch repaints it. This is macOS's
  vacated space, not a pane of ours: the app owns exactly one window
  (one `WindowGroup`, no panels, no `collectionBehavior` changes).
  A fullscreen window that keeps the menu bar fills its screen's
  visible frame rather than its whole frame, which is correct;
  reporting that difference to the messages pane said so on every
  move and told nobody anything. Setting the
  frame of a window in a fullscreen space to chase this blacks out
  both displays until the app is killed; do not try it.
- A window changing screens can leave an `NSViewRepresentable`'s
  AppKit view on the old screen's geometry while the SwiftUI chrome
  around it lays out correctly (seen: the editor's text bleeding
  across the window under the sidebar). The editor's coordinator
  watches the screen-change notifications and snaps its scroll view
  back onto its hosting container, a no-op while frames agree.
- The utility pane's review, editor and pull request surfaces stay
  mounted and hide rather than being rebuilt on a tab switch: each
  costs a git or GitHub read to come back, and flipping between
  them showed a loading state every time. A model that can paint
  from its cache does so in its initialiser, not on its first
  reload.
- Every mounted terminal pane watches the wheel through its own
  event monitor, and panes stack: hidden shells and other
  worktrees' terminals hold the same frame. A pane takes a wheel
  event only when the window's hit test lands on it and no other
  pane has claimed that event.
- Agent TUIs (Codex, Claude Code) query the terminal's colours via
  OSC 10/11 once at startup and cache them; re-theming the pane on
  a macOS appearance switch made Codex draw white text on a white
  composer. Agent panes pin the palette recorded at session launch
  (`terminalSchemes` in the metadata) instead of following the
  appearance; only shell panes re-theme live. Codex 0.148 through
  at least 0.150 misthemes its composer in both palettes and its
  theme setting does not control it; a forced dark palette proved
  worse than the default, so Codex follows the launch appearance
  like every other agent.
- herdr's terminal frames carry the rendered screen (cursor moves,
  colours, synchronised updates) and never the private modes the
  agent set, so a herdr-backed pane's local terminal never learns
  bracketed paste is on and sent a paste as keystrokes, every
  newline submitting the lines before it. `PaneTerminalView`
  wraps a paste in the bracketed-paste markers itself on those
  panes (`bracketsPastes`); a local shell pane sees the modes and
  needs nothing. herdr 0.8.2 also takes a short PTY write as a whole
  one, so a reader stalled while a paste larger than the input queue
  (1,022 bytes) is in flight loses about a kibibyte from the middle;
  `HerdrSlowReaderIntegrationTests` reproduces it under load, and
  `HerdrLargeInputIntegrationTests` meets it whenever the run is
  contended; both stay disabled until herdr waits or retries.
- An agent pane keeps no scrollback of its own, through
  `changeScrollback(nil)`: herdr owns the history and answers a
  scroll with a full repaint, so a local history filled up with
  the screens those repaints replaced and the same output showed
  two and three times over.
- `agentide <file>` can be handed anything readable: a file
  belonging to no worktree opens in whichever worktree is on
  screen, and the editor takes an absolute path as the file
  itself rather than resolving it against a worktree.
- Building and testing inside the sandbox has to leave the user's
  agents alone: both run capped (`--jobs 6`) and niced. The
  background band (`taskpolicy -b`) was tried and dropped: it
  throttles file I/O as well as CPU, which took a full rebuild from
  about a minute to twelve. `script/test` also sweeps the herdr
  servers a killed run orphaned, matching them by a socket under
  this checkout's `.test-scratch` and never by name: a run the
  system kills never reaches its own teardown, and seven orphaned
  servers were found holding memory after one such kill.
- herdr servers and their workspaces outlive the app, so changes to
  launch commands, workspace shapes or server behaviour often need
  the running `agentide` or `agentide-dev` herdr session stopped
  (`herdr session stop <name>` as the sandbox user, or `herdr server
  reload-config` for config alone) to take effect: when finishing
  such a change, tell the user exactly what to restart or stop.

### Required Before Each Commit

- Run `script/style --fix` and resolve anything it cannot fix
- Run `script/test` and `script/analyze` when Swift changed; if
  `script/analyze` has run for more than five minutes, stop it and
  let CI run it instead rather than holding the commit
- Run `script/analyze` on the host before opening or updating a
  pull request, and say plainly that you could not when you are in
  the sandbox, where it compiles every target and stops: neither
  its passes can run there (see the platform notes). Unused imports
  and dead code otherwise surface in CI first (sandboxed
  runs reuse the analyze build's index store, so
  periphery's dead-code pass now runs everywhere). Both passes
  always run and the script fails at the end if either did: the
  beta's macro plugin server trips SwiftLint's analyzer often
  enough that aborting on it hid the dead-code pass entirely
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
