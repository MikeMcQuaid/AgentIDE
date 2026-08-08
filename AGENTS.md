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
- `script/test`: run the unit and integration tests
- `script/analyze`: static analysis (SwiftLint analyzer and, on the
  host or CI, periphery for dead code)
- `script/style`: run all linters; `--fix` also applies safe fixes
- `script/attach <session>`: attach this terminal to a sandboxed
  tmux session (works as the host user or inside the sandbox)

## Repository Structure

- `README.md`: user workflow and features; the product specification
- `ARCHITECTURE.md`: system design, packages and data flows
- `AGENTS.md`: this file; `CLAUDE.md` is a symlink to it
- `Package.swift`, `Sources/`, `Tests/`: the Swift package targets
- `App/`: the app shell; `project.yml` defines the XcodeGen target
  (the generated `.xcodeproj` stays gitignored)
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

### Required Before Each Commit

- Run `script/style --fix` and resolve anything it cannot fix
- Run `script/test` and `script/analyze` when Swift changed
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
4. Derive state from tmux, git and `gh` on demand rather than caching
   it. AgentIDE must be killable at any moment losing nothing, and
   closed sessions and deleted worktrees must stay restorable and
   resumable.
5. Keep dependency directions clean: Domain depends on nothing,
   DataAccess and Features depend on Domain and App composes them.
6. Follow YAGNI and DRY: build only what the current slice needs and
   inline variables and functions used only once.
7. Keep agent-specific logic inside its adapter; everything else
   speaks one agent interface.
8. Describe third-party apps this project replaces by category, never
   by product name, in every committed file.
9. Keep diffs minimal and follow existing structure.
