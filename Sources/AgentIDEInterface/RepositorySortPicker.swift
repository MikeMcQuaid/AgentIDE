import AgentIDEDomain
import SwiftUI

/// A compact sort menu with a checkmark beside the current order.
public struct RepositorySortPicker: View {
    // MARK: Lifecycle

    public init(sort: Binding<RepositorySort>) {
        _sort = sort
    }

    // MARK: Public

    public var body: some View {
        Menu {
            Picker("Sort repositories", selection: $sort) {
                ForEach(RepositorySort.allCases, id: \.self) { value in
                    Text(value.rawValue).tag(value)
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down").accessibilityHidden(true)
        }
        .foregroundStyle(.primary)
        .accessibilityLabel("Sort repositories")
        .accessibilityValue(sort.rawValue)
        .help("Sort repositories: " + sort.rawValue)
        #if os(macOS)
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        #else
            .frame(minWidth: Self.minimumTouchSize, minHeight: Self.minimumTouchSize)
        #endif
    }

    // MARK: Private

    private static let minimumTouchSize: CGFloat = 44

    @Binding private var sort: RepositorySort
}
