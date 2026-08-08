import AgentIDEDomain
import SwiftUI

/// One worktree row with its status badges.
struct WorktreeRowView: View {
    // MARK: Internal

    let item: WorktreeItem

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(iconColour)
                .accessibilityHidden(true)
            VStack(alignment: .leading) {
                Text(item.worktree.branch)
                Text(badges).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if item.hasUnread {
                Circle().fill(.blue).frame(width: Self.unreadDotSize, height: Self.unreadDotSize)
            }
        }
    }

    // MARK: Private

    private static let unreadDotSize: CGFloat = 8

    private var icon: String {
        switch item.session?.status {
        case .running:
            "play.circle.fill"

        case .finished:
            "checkmark.circle"

        case nil:
            "circle.dashed"
        }
    }

    private var iconColour: Color {
        switch item.session?.status {
        case .running:
            .green

        case .finished:
            .secondary

        case nil:
            .secondary
        }
    }

    private var badges: String {
        var parts = [String]()
        if let agent = item.session?.agent {
            parts.append(agent.rawValue)
        }
        if item.isDirty {
            parts.append("uncommitted")
        }
        if let ahead = item.aheadOfUpstream, ahead > 0 {
            parts.append("unpushed \(ahead)")
        }
        if item.aheadOfUpstream == nil {
            parts.append("no upstream")
        }
        return parts.isEmpty ? "idle" : parts.joined(separator: " · ")
    }
}
