import AgentIDEDomain
import SwiftUI
import TerminalUI

/// Opens a repository in two steps in the middle pane: pick an
/// organisation or user (or type any owner), then pick from that
/// owner's repositories. Picking a cloned repository jumps to it;
/// any other clones into the workspace first.
public struct RepositoryFinderPane: View {
    // MARK: Lifecycle

    /// Creates the finder.
    public init(model: DashboardModel) {
        self.model = model
    }

    // MARK: Public

    /// A search field over the current step's fuzzy-ranked list.
    public var body: some View {
        VStack(alignment: .leading, spacing: Self.spacing) {
            header
            TextField(fieldPrompt, text: $query)
                .textFieldStyle(.roundedBorder)
                .onChange(of: query) { highlighted = 0 }
                .onSubmit { pickHighlighted() }
                .onKeyPress(.downArrow) { moveHighlight(by: 1) }
                .onKeyPress(.upArrow) { moveHighlight(by: -1) }
            if results.isEmpty, query.isEmpty {
                ProgressView(owner == nil ? "Listing organisations…" : "Listing repositories…")
                    .frame(maxWidth: .infinity, minHeight: Self.listHeight)
            } else {
                resultsList
            }
        }
        .padding([.horizontal, .bottom])
        .padding(.top, Self.topPadding)
        .frame(maxWidth: Self.maximumWidth, maxHeight: .infinity, alignment: .top)
        // Cached listings paint instantly; the fetches refresh.
        .task {
            owners = model.cachedOrganisations()
            owners = await model.organisations()
        }
        .task(id: owner) {
            guard let owner else {
                return
            }

            repositories = model.cachedRepositories(owner: owner)
            let fresh = await model.repositories(owner: owner)
            // A slow answer for a previously picked owner must not
            // overwrite the currently shown owner's list.
            guard Task.isCancelled == false, owner == self.owner else {
                return
            }

            repositories = fresh
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
    @State private var owner: String?
    @State private var owners: [String] = []
    @State private var repositories: [String] = []
    @State private var highlighted = 0

    private let model: DashboardModel

    private var fieldPrompt: String {
        owner == nil
            ? "Organisation or user; return also accepts any typed owner"
            : "Find a repository"
    }

    private var results: [String] {
        let source = owner == nil ? owners : repositories
        return query.isEmpty
            ? Array(source.prefix(Self.resultLimit))
            : Array(FuzzyMatcher.rank(source, query: query).prefix(Self.resultLimit))
    }

    private var clonedNames: Set<String> {
        Set(model.repositories.flatMap { [$0.fullName ?? "", $0.name] })
    }

    private var header: some View {
        HStack(spacing: Self.spacing) {
            if let owner {
                Button("Back to organisations", systemImage: "chevron.backward") { stepBack() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .hoverHelp("Back to the organisation step")
                Text("Open repository in \(owner)").font(.subheadline.weight(.semibold))
            } else {
                // No cancel button: any other middle-pane action,
                // like selecting a worktree, replaces this page.
                Text("Open repository").font(.subheadline.weight(.semibold))
            }
        }
    }

    private var resultsList: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(results.enumerated()), id: \.element) { index, result in
                    row(result, isHighlighted: index == highlighted)
                        .onTapGesture { pick(result) }
                        .accessibilityAddTraits(.isButton)
                }
            }
        }
        .frame(minHeight: Self.listHeight, maxHeight: Self.listHeight)
        .hoverHelp("Arrows move the highlight; return or a click picks")
    }

    @ViewBuilder
    private func row(_ result: String, isHighlighted: Bool) -> some View {
        if owner == nil {
            listRow(result, systemImage: "building.2", isHighlighted: isHighlighted)
                .hoverHelp("List this owner's repositories")
        } else {
            let name = result.split(separator: "/").last.map(String.init) ?? result
            let isCloned = clonedNames.contains(result) || clonedNames.contains(name)
            listRow(
                result,
                systemImage: isCloned ? "internaldrive" : "icloud.and.arrow.down",
                isHighlighted: isHighlighted,
            )
            .hoverHelp(isCloned ? "In the workspace already; opens it" : "Clones into the workspace, then opens it")
        }
    }

    private func listRow(_ title: String, systemImage: String, isHighlighted: Bool) -> some View {
        HStack(spacing: Self.spacing) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(title).lineLimit(1)
            Spacer(minLength: 0)
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

    /// Return picks the highlight; on the owner step a typed owner
    /// with no match is accepted as free text.
    private func pickHighlighted() {
        if results.indices.contains(highlighted) {
            pick(results[highlighted])
            return
        }

        let typed = query.trimmingCharacters(in: .whitespaces)
        if owner == nil, typed.isEmpty == false {
            pick(typed)
        }
    }

    private func pick(_ result: String) {
        guard owner == nil else {
            Task { await model.openRepository(fullName: result) }
            return
        }

        owner = result
        repositories = []
        query = ""
        highlighted = 0
    }

    private func stepBack() {
        owner = nil
        repositories = []
        query = ""
        highlighted = 0
    }
}
