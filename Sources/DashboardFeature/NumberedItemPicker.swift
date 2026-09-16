import AgentIDEDomain
import SwiftUI
import TerminalUI

// MARK: - NumberedItemPicker

/// A pop-up for an open issue or pull request that searches as you
/// type: opening it focuses a field over the list, digits jump to a
/// number and anything else matches titles. Arrows move the
/// highlight, return or a click picks and Escape closes it.
struct NumberedItemPicker<Item: NumberedItem>: View {
    // MARK: Internal

    @Binding var selection: Int?

    let items: [Item]
    let placeholder: String
    let searchPrompt: String
    let loadingTitle: String
    let emptyTitle: String
    let isLoading: Bool

    var body: some View {
        Button {
            isPresented = true
        } label: {
            HStack {
                Text(selectedLabel ?? placeholder)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .imageScale(.small)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity)
        }
        .popover(isPresented: $isPresented, arrowEdge: .bottom) { search }
    }

    // MARK: Private

    @State private var isPresented = false
    @State private var query = ""
    @State private var highlighted = 0
    @FocusState private var fieldFocused: Bool

    private var selectedLabel: String? {
        items.first { $0.number == selection }.map { "#" + String($0.number) + " " + $0.title }
    }

    private var results: [Item] {
        NumberedItemSearch.rank(items, query: query)
    }

    private var search: some View {
        VStack(alignment: .leading, spacing: Layout.spacing) {
            TextField(searchPrompt, text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($fieldFocused)
                .onChange(of: query) { highlighted = 0 }
                .onSubmit { pickHighlighted() }
                .highlightNavigation($highlighted, count: results.count)
            if results.isEmpty {
                Group {
                    if items.isEmpty, isLoading {
                        ProgressView(loadingTitle)
                    } else {
                        Text(items.isEmpty ? emptyTitle : "Nothing matches")
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: Layout.listHeight)
            } else {
                resultsList
            }
        }
        .padding(Layout.spacing)
        .frame(width: Layout.width)
        .onExitCommand { isPresented = false }
        .onAppear {
            highlighted = results.firstIndex { $0.number == selection } ?? 0
            fieldFocused = true
        }
        // Clearing on close rather than open: the query's onChange
        // would otherwise reset the highlight just set to the pick.
        .onDisappear { query = "" }
    }

    private var resultsList: some View {
        HighlightedResultsList(
            results,
            id: \.number,
            highlighted: highlighted,
            help: "Arrows move the highlight; return or a click picks",
            onPick: { pick($0) },
            row: { row($0) },
        )
        .frame(height: Layout.listHeight)
    }

    private func row(_ item: Item) -> some View {
        HStack(spacing: Layout.spacing) {
            Text("#" + String(item.number))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Text(item.title).lineLimit(1)
            Spacer(minLength: 0)
            if item.number == selection {
                Image(systemName: "checkmark")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Chosen")
            }
        }
        .padding(.horizontal, Layout.spacing)
        .padding(.vertical, Layout.rowPadding)
    }

    private func pickHighlighted() {
        if results.indices.contains(highlighted) {
            pick(results[highlighted])
        }
    }

    private func pick(_ item: Item) {
        selection = item.number
        isPresented = false
    }
}

// MARK: - Layout

/// The picker's measurements, outside it because generic types
/// cannot hold static stored properties.
private enum Layout {
    static let spacing: CGFloat = 8
    static let rowPadding: CGFloat = 4
    static let width: CGFloat = 420
    static let listHeight: CGFloat = 260
}
