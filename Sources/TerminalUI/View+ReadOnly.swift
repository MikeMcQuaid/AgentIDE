import SwiftUI

/// A text field or editor that can be read and copied from but not
/// changed: `.disabled` would take selection away with editing, and
/// a commit message or a template one cannot copy is worse than
/// one that cannot be typed into. The binding drops writes instead,
/// and the view dims to say so.
public extension View {
    /// Dims the view when read-only; pair with `Binding.readOnly`.
    func readOnly(_ isReadOnly: Bool) -> some View {
        opacity(isReadOnly ? ReadOnlyStyle.dimmedOpacity : 1)
            .hoverHelp(isReadOnly ? "Read-only here; the text can still be selected and copied" : "")
    }
}

// MARK: - ReadOnlyStyle

/// How read-only text looks.
enum ReadOnlyStyle {
    /// Dim enough to read as not editable, bright enough to read.
    static let dimmedOpacity = 0.6
}

public extension Binding where Value == String {
    /// The same binding with writes ignored while read-only.
    func readOnly(_ isReadOnly: Bool) -> Binding<String> {
        Binding(
            get: { wrappedValue },
            set: { newValue in
                if isReadOnly == false {
                    wrappedValue = newValue
                }
            },
        )
    }
}
