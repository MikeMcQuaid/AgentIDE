import AgentIDEDomain
import SwiftUI
import TerminalUI

/// Fuzzy-finds a repository across every GitHub organisation the
/// user can reach, in the middle pane: picking a cloned one jumps
/// to it, picking any other clones it into the workspace first.
public struct RepositoryFinderPane: View {
    // MARK: Lifecycle

    /// Creates the finder.
    public init(model: DashboardModel) {
        self.model = model
    }

    // MARK: Public

    /// A search field over the fuzzy-ranked repository list.
    public var body: some View {
        VStack(alignment: .leading, spacing: Self.spacing) {
            HStack {
                Text("Open repository").font(.subheadline.weight(.semibold))
                Spacer()
                Button("Cancel") { model.showsRepositoryFinder = false }
                    .controlSize(.small)
                    .keyboardShortcut(.cancelAction)
                    .hoverHelp("Close without opening anything")
            }
            TextField("Find a repository across your organisations", text: $query)
                .textFieldStyle(.roundedBorder)
                .onChange(of: query) { highlighted = 0 }
                .onSubmit { openHighlighted() }
                .onKeyPress(.downArrow) { moveHighlight(by: 1) }
                .onKeyPress(.upArrow) { moveHighlight(by: -1) }
            if all.isEmpty {
                ProgressView("Listing repositories…")
                    .frame(maxWidth: .infinity, minHeight: Self.listHeight)
            } else {
                resultsList
            }
        }
        .padding([.horizontal, .bottom])
        .padding(.top, Self.topPadding)
        .frame(maxWidth: Self.maximumWidth, maxHeight: .infinity, alignment: .top)
        // The cached listing paints instantly; the fetch refreshes.
        .task {
            all = model.cachedAccessibleRepositories()
            all = await model.accessibleRepositories()
        }
    }

    // MARK: Private

    private static let spacing: CGFloat = 10
    private static let rowPadding: CGFloat = 4
    private static let resultLimit = 15
    private static let listHeight: CGFloat = 300
    private static let topPadding: CGFloat = 3
    private static let maximumWidth: CGFloat = 640
    private static let highlightOpacity = 0.25

    @State private var query = ""
    @State private var all: [String] = []
    @State private var highlighted = 0

    private let model: DashboardModel

    private var results: [String] {
        query.isEmpty
            ? Array(all.prefix(Self.resultLimit))
            : Array(FuzzyMatcher.rank(all, query: query).prefix(Self.resultLimit))
    }

    private var clonedNames: Set<String> {
        Set(model.repositories.flatMap { [$0.fullName ?? "", $0.name] })
    }

    private var resultsList: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(results.enumerated()), id: \.element) { index, fullName in
                    row(fullName, isHighlighted: index == highlighted)
                        .onTapGesture { open(fullName) }
                        .accessibilityAddTraits(.isButton)
                }
            }
        }
        .frame(minHeight: Self.listHeight, maxHeight: Self.listHeight)
        .hoverHelp("Arrows move the highlight; return or a click opens, cloning first when needed")
    }

    private func row(_ fullName: String, isHighlighted: Bool) -> some View {
        let name = fullName.split(separator: "/").last.map(String.init) ?? fullName
        let isCloned = clonedNames.contains(fullName) || clonedNames.contains(name)
        return HStack(spacing: Self.spacing) {
            Image(systemName: isCloned ? "internaldrive" : "icloud.and.arrow.down")
                .foregroundStyle(.secondary)
                .accessibilityLabel(isCloned ? "Already cloned" : "Will clone")
            Text(fullName).lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Self.spacing)
        .padding(.vertical, Self.rowPadding)
        .background(isHighlighted ? Color.accentColor.opacity(Self.highlightOpacity) : .clear)
        .contentShape(Rectangle())
        .hoverHelp(isCloned ? "In the workspace already; opens it" : "Clones into the workspace, then opens it")
    }

    private func moveHighlight(by offset: Int) -> KeyPress.Result {
        guard results.isEmpty == false else {
            return .ignored
        }

        highlighted = min(max(0, highlighted + offset), results.count - 1)
        return .handled
    }

    private func openHighlighted() {
        guard results.indices.contains(highlighted) else {
            return
        }

        open(results[highlighted])
    }

    private func open(_ fullName: String) {
        Task { await model.openRepository(fullName: fullName) }
    }
}
