import SwiftUI

/// How this app draws a name git owns: a branch, a ref, a worktree's
/// path. They are identifiers rather than words, and a reader picks
/// one out of a row of prose by its shape, so every surface draws
/// them monospaced, a size down from the prose beside them since a
/// monospaced face reads larger at the same size.
///
/// Code itself has its own typography (`CodeStyle`, a face and size
/// Settings owns); this is for chrome naming a thing, not for
/// showing its contents.
public nonisolated enum NameStyle {
    /// A name in a row of its own: a sidebar row, a popover's list.
    public static let font: Font = .system(.callout, design: .monospaced)

    /// A name in a detail line, beside counts and badges.
    public static let small: Font = .system(.caption, design: .monospaced)
}
