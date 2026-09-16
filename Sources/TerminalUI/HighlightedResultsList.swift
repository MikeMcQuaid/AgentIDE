import SwiftUI

// MARK: - HighlightedResultsList

/// The one result list under a search field: rows in a scroll that
/// keeps the keyboard highlight on screen, a click picking a row.
/// Rows bring their own content and padding; callers set the height.
public struct HighlightedResultsList<Item, ID: Hashable, Row: View>: View {
    // MARK: Lifecycle

    /// Creates the list over results identified by `id`.
    public init(
        _ results: [Item],
        id: KeyPath<Item, ID>,
        highlighted: Int,
        help: String,
        onPick: @escaping (Item) -> Void,
        @ViewBuilder row: @escaping (Item) -> Row,
    ) {
        self.results = results
        self.id = id
        self.highlighted = highlighted
        self.help = help
        self.onPick = onPick
        self.row = row
    }

    // MARK: Public

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(rows) { indexed in
                        let index = indexed.index
                        let item = indexed.item
                        row(item)
                            .background(index == highlighted ? Color.accentColor.opacity(highlightOpacity) : .clear)
                            .contentShape(Rectangle())
                            .onTapGesture { onPick(item) }
                            .accessibilityAddTraits(.isButton)
                            .id(index)
                    }
                }
            }
            // Arrowing past the visible rows scrolls the highlight
            // into view rather than moving it off screen.
            .onAppear { proxy.scrollTo(highlighted) }
            .onChange(of: highlighted) { proxy.scrollTo(highlighted) }
        }
        .hoverHelp(help)
    }

    // MARK: Private

    private let results: [Item]
    private let id: KeyPath<Item, ID>
    private let highlighted: Int
    private let help: String
    private let onPick: (Item) -> Void
    private let row: (Item) -> Row

    /// Rows keep their results' identity rather than their position.
    private var rows: [IndexedResult<Item, ID>] {
        results.enumerated().map { IndexedResult(index: $0.offset, item: $0.element, id: $0.element[keyPath: id]) }
    }
}

// MARK: - IndexedResult

/// A result beside its position, identified by the result's own id.
private struct IndexedResult<Item, ID: Hashable>: Identifiable {
    let index: Int
    let item: Item
    let id: ID
}

/// Generic types cannot hold static stored properties.
private let highlightOpacity = 0.25

// MARK: - HighlightNavigation

public extension View {
    /// Up and down arrows move the highlight within `count` rows,
    /// leaving the keys alone when there are none.
    func highlightNavigation(_ highlighted: Binding<Int>, count: Int) -> some View {
        onKeyPress(.downArrow) { moveHighlight(highlighted, by: 1, count: count) }
            .onKeyPress(.upArrow) { moveHighlight(highlighted, by: -1, count: count) }
    }
}

private func moveHighlight(_ highlighted: Binding<Int>, by offset: Int, count: Int) -> KeyPress.Result {
    guard count > 0 else {
        return .ignored
    }

    highlighted.wrappedValue = min(max(0, highlighted.wrappedValue + offset), count - 1)
    return .handled
}
