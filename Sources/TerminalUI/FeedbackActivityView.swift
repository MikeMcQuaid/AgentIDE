import AgentIDEData
import SwiftUI

/// Keep the current wait readable without opening the detailed history.
struct FeedbackActivityView: View {
    // MARK: Internal

    let state: PullRequestAutomation

    var body: some View {
        VStack(alignment: .leading, spacing: Self.spacing) {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: Self.spacing) {
                    Text(state.nextTrigger).foregroundStyle(.secondary)
                    log
                }
                .interfaceFont(.callout)
                .padding(.top, Self.spacing)
            } label: {
                HStack(alignment: .firstTextBaseline) {
                    Text("Activity")
                    Text(state.activityStatus)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .hoverHelp(state.activityStatus)
                }
            }
            if state.lastResult.isEmpty == false {
                Text(state.lastResult)
                    .interfaceFont(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(Self.resultLines)
                    .hoverHelp(state.lastResult)
            }
        }
        .textSelection(.enabled)
    }

    // MARK: Private

    private static let spacing: CGFloat = 8
    private static let resultLines = 2

    private var log: some View {
        VStack(alignment: .leading, spacing: Self.spacing) {
            if state.activityLog?.isEmpty != false {
                Text("No activity yet").foregroundStyle(.secondary)
            }
            ForEach((state.activityLog ?? []).reversed()) { entry in
                HStack(alignment: .top) {
                    Text(entry.date, format: .dateTime.hour().minute().second())
                        .foregroundStyle(.secondary)
                    Text(entry.message)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
