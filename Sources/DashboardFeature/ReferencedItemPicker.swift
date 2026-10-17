import AgentIDEDomain
import SwiftUI
import TerminalUI

// MARK: - ReferencedItemPicker

/// A pop-up for an open issue, pull request or security advisory
/// that searches as you type through `ReferencedItemSearchList`.
struct ReferencedItemPicker<Item: ReferencedItem>: View {
    // MARK: Lifecycle

    /// Creates the picker; `label` names it for assistive technology
    /// the way a picker's own label would, since the button shows
    /// only the pick.
    init(
        _ label: String,
        selection: Binding<Item.ID?>,
        items: [Item],
        placeholder: String,
        searchPrompt: String,
        loadingTitle: String,
        emptyTitle: String,
        isLoading: Bool,
    ) {
        self.label = label
        _selection = selection
        self.items = items
        self.placeholder = placeholder
        self.searchPrompt = searchPrompt
        self.loadingTitle = loadingTitle
        self.emptyTitle = emptyTitle
        self.isLoading = isLoading
    }

    // MARK: Internal

    @Binding var selection: Item.ID?

    let label: String
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
        .accessibilityLabel(label)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            ReferencedItemSearchList(
                items: items,
                selection: selection,
                searchPrompt: searchPrompt,
                loadingTitle: loadingTitle,
                emptyTitle: emptyTitle,
                isLoading: isLoading,
                onPick: { item in
                    selection = item.id
                    isPresented = false
                },
                onClose: { isPresented = false },
            )
        }
    }

    // MARK: Private

    @State private var isPresented = false

    private var selectedLabel: String? {
        items.first { $0.id == selection }.map { $0.reference + " " + $0.title }
    }
}

// MARK: - ReferencedItemSearchList

/// A popover's searchable list of referenced items: opening it
/// focuses a field over the list, digits jump to a number and
/// anything else matches a GHSA id, a branch name or a title. Arrows
/// move the highlight, return or a click picks and Escape closes it.
struct ReferencedItemSearchList<Item: ReferencedItem>: View {
    // MARK: Internal

    let items: [Item]
    /// The current pick, checked and highlighted on opening.
    let selection: Item.ID?
    let searchPrompt: String
    let loadingTitle: String
    let emptyTitle: String
    let isLoading: Bool
    let onPick: (Item) -> Void
    let onClose: () -> Void

    var body: some View {
        let ranked = results
        return ScrollViewReader { proxy in
            PopoverContent(width: Layout.width) {
                VStack(alignment: .leading, spacing: Layout.spacing) {
                    TextField(searchPrompt, text: $query)
                        .textFieldStyle(.roundedBorder)
                        .focused($fieldFocused)
                        .onChange(of: query) { highlighted = 0 }
                        .onSubmit { pick(ranked, at: highlighted) }
                        .highlightNavigation($highlighted, count: ranked.count)
                    if ranked.isEmpty {
                        Group {
                            if items.isEmpty, isLoading {
                                ProgressView(loadingTitle)
                            } else {
                                Text(items.isEmpty ? emptyTitle : "Nothing matches")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        resultsList(ranked)
                    }
                }
                .padding(Layout.spacing)
            }
            .onChange(of: highlighted) { proxy.scrollTo(highlighted) }
        }
        .onExitCommand { onClose() }
        .onAppear {
            highlighted = ranked.firstIndex { $0.id == selection } ?? 0
            fieldFocused = true
        }
        // Clearing on close rather than open: the query's onChange
        // would otherwise reset the highlight just set to the pick.
        .onDisappear { query = "" }
    }

    // MARK: Private

    @State private var query = ""
    @State private var highlighted = 0
    @FocusState private var fieldFocused: Bool

    private var nameStyle: NameStyle = .init()

    /// Ranked once per render, since the body reads it several times.
    private var results: [Item] {
        ReferencedItemSearch.rank(items, query: query)
    }

    private func resultsList(_ results: [Item]) -> some View {
        HighlightedResultsList(
            results,
            id: \.id,
            highlighted: highlighted,
            help: "Arrows move the highlight; return or a click picks",
            scrolls: false,
            onPick: { onPick($0) },
            row: { row($0) },
        )
    }

    private func row(_ item: Item) -> some View {
        HStack(spacing: Layout.spacing) {
            if Item.isGitName {
                Text(item.reference)
                    .font(nameStyle.font)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text(item.reference)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Text(item.title).lineLimit(1)
            }
            Spacer(minLength: 0)
            if item.id == selection {
                Image(systemName: "checkmark")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Chosen")
            }
        }
        .padding(.horizontal, Layout.spacing)
        .padding(.vertical, Layout.rowPadding)
    }

    private func pick(_ results: [Item], at index: Int) {
        if results.indices.contains(index) {
            onPick(results[index])
        }
    }
}

// MARK: - Layout

/// The picker's measurements, outside it because generic types
/// cannot hold static stored properties.
private enum Layout {
    static let spacing: CGFloat = 8
    static let rowPadding: CGFloat = 4
    static let width: CGFloat = 420
}
