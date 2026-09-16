import AgentIDEDomain
import SwiftUI
import TerminalUI

/// A pop-up for an open issue or pull request that searches as you
/// type: opening it focuses a field over the list, digits jump to a
/// number and anything else matches titles. Arrows move the
/// highlight, return or a click picks and Escape closes it.
struct NumberedItemPicker: View {
    // MARK: Internal

    struct Item: Identifiable {
        let number: Int
        let title: String

        var id: Int {
            number
        }

        var label: String {
            "#" + String(number) + " " + title
        }
    }

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
                Text(items.first { $0.number == selection }?.label ?? placeholder)
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

    private static let spacing: CGFloat = 8
    private static let rowPadding: CGFloat = 4
    private static let width: CGFloat = 420
    private static let listHeight: CGFloat = 260
    private static let highlightOpacity = 0.25

    @State private var isPresented = false
    @State private var query = ""
    @State private var highlighted = 0
    @FocusState private var fieldFocused: Bool

    private var results: [Item] {
        NumberedItemSearch.rank(items, query: query, number: \.number, title: \.title)
    }

    private var search: some View {
        VStack(alignment: .leading, spacing: Self.spacing) {
            TextField(searchPrompt, text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($fieldFocused)
                .onChange(of: query) { highlighted = 0 }
                .onSubmit { pickHighlighted() }
                .onKeyPress(.downArrow) { moveHighlight(by: 1) }
                .onKeyPress(.upArrow) { moveHighlight(by: -1) }
            if results.isEmpty {
                Group {
                    if items.isEmpty, isLoading {
                        ProgressView(loadingTitle)
                    } else {
                        Text(items.isEmpty ? emptyTitle : "Nothing matches")
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: Self.listHeight)
            } else {
                resultsList
            }
        }
        .padding(Self.spacing)
        .frame(width: Self.width)
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
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, item in
                        row(item, isHighlighted: index == highlighted)
                            .onTapGesture { pick(item) }
                            .accessibilityAddTraits(.isButton)
                            .id(index)
                    }
                }
            }
            .onAppear { proxy.scrollTo(highlighted) }
            .onChange(of: highlighted) { proxy.scrollTo(highlighted) }
        }
        .frame(height: Self.listHeight)
        .hoverHelp("Arrows move the highlight; return or a click picks")
    }

    private func row(_ item: Item, isHighlighted: Bool) -> some View {
        HStack(spacing: Self.spacing) {
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
        .padding(.horizontal, Self.spacing)
        .padding(.vertical, Self.rowPadding)
        .background(isHighlighted ? Color.accentColor.opacity(Self.highlightOpacity) : .clear)
        .contentShape(Rectangle())
    }

    private func moveHighlight(by offset: Int) -> KeyPress.Result {
        guard results.isEmpty == false else {
            return .ignored
        }

        highlighted = min(max(0, highlighted + offset), results.count - 1)
        return .handled
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
