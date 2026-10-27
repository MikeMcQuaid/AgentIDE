import Foundation

/// Repository group orders shared by the desktop and phone.
public enum RepositorySort: String, CaseIterable, Sendable {
    case status = "Highest-priority status"
    case name = "Owner / repository"
    case activity = "Recent activity"

    // MARK: Public

    public struct Key {
        // MARK: Lifecycle

        public init(name: String, statuses: [SidebarStatus], activity: Int) {
            self.name = name
            priority = statuses.compactMap { SidebarStatus.allCases.firstIndex(of: $0) }.min()
                ?? SidebarStatus.allCases.count
            self.activity = activity
        }

        // MARK: Internal

        let name: String
        let priority: Int
        let activity: Int
    }

    /// Reads each group's facts once; equal priorities and timestamps use its full name.
    public func sorted<Element>(_ elements: [Element], key: (Element) -> Key) -> [Element] {
        elements.map { (element: $0, key: key($0)) }
            .sorted { first, second in
                switch self {
                case .status:
                    if first.key.priority != second.key.priority {
                        return first.key.priority < second.key.priority
                    }

                case .activity:
                    if first.key.activity != second.key.activity {
                        return first.key.activity > second.key.activity
                    }

                case .name:
                    break
                }
                return first.key.name.localizedStandardCompare(second.key.name) == .orderedAscending
            }
            .map(\.element)
    }
}
