import SanductorDomain
import SwiftUI

/// One blocker editor shared by the desktop and phone.
public struct WorkBlockEditor: View {
    // MARK: Lifecycle

    @preconcurrency
    public init(
        target: SidebarTarget,
        block: WorkBlock?,
        targets: [SidebarTarget],
        additionalTargets: [SidebarTarget] = [],
        loadSources: @escaping @MainActor (String) async -> SidebarResponse,
        save: @escaping @MainActor (WorkBlock?, WorkBlock?) async -> String?,
        dismiss: @escaping @MainActor () -> Void,
    ) {
        self.target = target
        _block = State(initialValue: block)
        self.targets = targets
        self.additionalTargets = additionalTargets
        self.loadSources = loadSources
        self.save = save
        self.dismiss = dismiss
        _scope = State(initialValue: block?.scope ?? .worktree)
        _repositoryPath = State(initialValue: target.repositoryPath)
        switch block?.dependency {
        case let .note(text):
            _note = State(initialValue: text)

        case let .worktree(other):
            _source = State(initialValue: .worktree)
            _selected = State(initialValue: other.path)

        case let .issue(path, number, _):
            _source = State(initialValue: .issue)
            _repositoryPath = State(initialValue: path)
            _selected = State(initialValue: String(number))

        case let .pullRequest(path, number, _):
            _source = State(initialValue: .pullRequest)
            _repositoryPath = State(initialValue: path)
            _selected = State(initialValue: String(number))

        case nil:
            break
        }
    }

    // MARK: Public

    public var body: some View {
        VStack(alignment: .leading, spacing: Self.spacing) {
            Text("Block " + (
                additionalTargets.isEmpty ? target.label : String(additionalTargets.count + 1) + " worktrees"
            ))
            .interfaceFont(.headline)
            VStack(alignment: .leading, spacing: Self.fieldSpacing) {
                Picker("Apply to", selection: $scope) {
                    ForEach(WorkBlock.Scope.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                Picker("Waiting for", selection: $source) {
                    ForEach(Source.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                if source == .note {
                    TextField("What is blocking this work?", text: $note, axis: .vertical)
                        .lineLimit(Self.noteLines)
                        .focused($focused)
                    Text("Remove this block manually when it is resolved.")
                        .interfaceFont(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    dependencyPicker
                }
            }
            .disabled(isSaving)
            if let error {
                Text(error).foregroundStyle(.red).interfaceFont(.callout)
            }
            actions
        }
        .interfaceFont(.body)
        .padding()
        .onAppear { focused = true }
        .onChange(of: source) { _, _ in selected = nil; search = ""; focused = true }
        .task(id: source.rawValue + repositoryPath) { await reloadSources() }
    }

    // MARK: Private

    private enum Source: String, CaseIterable {
        case note = "Note"
        case worktree = "Worktree"
        case issue = "Issue"
        case pullRequest = "Pull request"
    }

    private static let spacing: CGFloat = 12
    private static let fieldSpacing: CGFloat = 10
    private static let choiceSpacing: CGFloat = 8
    private static let choicePadding: CGFloat = 5
    private static let minimumListHeight: CGFloat = 180
    private static let maximumListHeight: CGFloat = 300
    private static let noteLines = 2 ... 5

    @State private var scope: WorkBlock.Scope
    @State private var source: Source = .note
    @State private var repositoryPath: String
    @State private var note = ""
    @State private var search = ""
    @State private var selected: String?
    @State private var sources: SidebarResponse = .init()
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var error: String?
    @FocusState private var focused: Bool

    @State private var block: WorkBlock?

    private let target: SidebarTarget
    private let targets: [SidebarTarget]
    private let additionalTargets: [SidebarTarget]
    private let loadSources: @MainActor (String) async -> SidebarResponse
    private let save: @MainActor (WorkBlock?, WorkBlock?) async -> String?
    private let dismiss: @MainActor () -> Void

    private var choices: [(id: String, label: String)] {
        let all: [(id: String, label: String)] =
            switch source {
            case .note:
                []

            case .worktree:
                targets.filter { candidate in
                    ([target] + additionalTargets).contains { $0.path == candidate.path } == false
                }
                .map { ($0.path, $0.label) }

            case .issue:
                sources.issues.map { (String($0.number), $0.reference + ": " + $0.title) }

            case .pullRequest:
                sources.pullRequests
                    .filter { $0.state == "OPEN" }
                    .map { (String($0.number), $0.reference + ": " + $0.title) }
            }
        return all.filter { search.isEmpty || $0.label.localizedStandardContains(search) }
    }

    private var dependency: BlockDependency? {
        switch source {
        case .note:
            let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty || text.utf8.count > WorkBlock.maximumNoteBytes ? nil : .note(text)

        case .worktree:
            return targets.first { $0.path == selected }.map(BlockDependency.worktree)

        case .issue:
            return sources.issues
                .first { String($0.number) == selected }
                .map { .issue(repositoryPath: repositoryPath, number: $0.number, title: $0.title) }

        case .pullRequest:
            return sources.pullRequests
                .first { String($0.number) == selected }
                .map { .pullRequest(repositoryPath: repositoryPath, number: $0.number, title: $0.title) }
        }
    }

    private var actions: some View {
        HStack {
            Button("Cancel", action: dismiss).keyboardShortcut(.cancelAction).disabled(isSaving)
            if block != nil {
                BusyButton("Remove block", busy: "Removing", disabled: isSaving) {
                    await submit(nil)
                }
            }
            Spacer(minLength: 0)
            BusyButton(
                "Block",
                busy: "Saving",
                prominent: true,
                disabled: dependency == nil || isSaving || isLoading,
            ) {
                guard let dependency else {
                    return
                }

                await submit(WorkBlock(target: target, scope: scope, dependency: dependency))
            }
            .keyboardShortcut(.return, modifiers: .command)
        }
    }

    private var dependencyPicker: some View {
        VStack(alignment: .leading, spacing: Self.choiceSpacing) {
            if source != .worktree {
                Picker("Repository", selection: $repositoryPath) {
                    ForEach(Array(Set(targets.map(\.repositoryPath))).sorted(), id: \.self) { path in
                        Text(targets.first { $0.repositoryPath == path }?.repository ?? path).tag(path)
                    }
                }
                .onChange(of: repositoryPath) { _, _ in selected = nil }
            }
            TextField("Find by name or number", text: $search).focused($focused)
            if isLoading {
                LaunchProgressView(spinner: "Loading open issues and pull requests…")
            } else {
                choiceList
            }
        }
        .frame(minHeight: Self.minimumListHeight, maxHeight: Self.maximumListHeight)
    }

    private var choiceList: some View {
        ScrollView {
            LazyVStack(alignment: .leading) {
                ForEach(choices, id: \.id) { choice in
                    Button {
                        selected = choice.id
                    } label: {
                        HStack {
                            Image(systemName: selected == choice.id ? "checkmark.circle.fill" : "circle")
                                .accessibilityLabel(selected == choice.id ? "Selected" : "Not selected")
                            Text(choice.label).multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                        .padding(.vertical, Self.choicePadding)
                    }
                    .buttonStyle(.plain)
                }
                if choices.isEmpty {
                    Text("No matching " + source.rawValue.lowercased() + "s")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func reloadSources() async {
        guard source == .issue || source == .pullRequest else {
            isLoading = false; return
        }

        isLoading = true
        let loaded = await loadSources(repositoryPath)
        guard Task.isCancelled == false else {
            return
        }

        sources = loaded
        error = loaded.error
        isLoading = false
    }

    private func submit(_ block: WorkBlock?) async {
        isSaving = true
        error = await save(block, self.block)
        isSaving = false
        if error == nil {
            dismiss()
        }
    }
}
