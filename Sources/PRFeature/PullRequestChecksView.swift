import AgentIDEDomain
import SwiftUI
import TerminalUI

// MARK: - PullRequestChecksView

/// All checks on the current head, with individual job logs on demand.
struct PullRequestChecksView: View {
    // MARK: Internal

    let model: PullRequestsModel
    let summary: PullRequestSummary

    var body: some View {
        if let checks = summary.checkDetails {
            if let selected = checks.first(where: { $0.id == selectedID }) {
                CheckLogView(check: selected, fetchLog: model.fetchCheckLog) { selectedID = nil }
                    .id(selected.id)
            } else {
                VStack(spacing: Self.spacing) {
                    Picker("Show checks", selection: $filter) {
                        ForEach(Filter.allCases, id: \.self) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, Self.spacing)
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(checks.filter(filter.includes)) { check in
                                Button { selectedID = check.id } label: {
                                    row(check)
                                        .padding(Self.spacing)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .hoverHelp("View the log for " + check.name)
                                Divider()
                            }
                            if checks.contains(where: filter.includes) == false {
                                Text(checks.isEmpty ? "No CI checks." : "No matching checks.")
                                    .interfaceFont(.callout)
                                    .foregroundStyle(.secondary)
                                    .padding()
                            }
                        }
                    }
                }
                .padding(.top, Self.spacing)
            }
        } else {
            LaunchProgressView(spinner: "Loading CI checks…")
        }
    }

    // MARK: Private

    private enum Filter: String, CaseIterable {
        case all = "All"
        case required = "Required"
        case unfinished = "Unfinished"
        case finished = "Finished"

        // MARK: Internal

        func includes(_ check: PullRequestCheck) -> Bool {
            switch self {
            case .all:
                true

            case .required:
                check.requirement == .required

            case .unfinished:
                check.isComplete == false

            case .finished:
                check.isComplete
            }
        }
    }

    private static let spacing: CGFloat = 8

    private static let dotInset: CGFloat = 3

    @State private var filter: Filter = .all
    @State private var selectedID: String?

    private func row(_ check: PullRequestCheck) -> some View {
        HStack(alignment: .top, spacing: Self.spacing) {
            Octicon(ChecksStyle.checksOcticonName, colour: ChecksStyle.colour(for: check.conclusion))
                .padding(.top, Self.dotInset)
            VStack(alignment: .leading, spacing: Self.dotInset) {
                Text(check.name).interfaceFont(.callout, weight: .semibold)
                Text(check.requirement.rawValue + " · " + check.statusDescription)
                    .interfaceFont(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            CheckDurationView(check: check)
            Image(systemName: "chevron.right").foregroundStyle(.secondary).accessibilityHidden(true)
        }
    }
}

// MARK: - CheckDurationView

struct CheckDurationView: View {
    let check: PullRequestCheck

    var body: some View {
        Group {
            if let duration = check.duration {
                Text(Duration.seconds(duration).formatted(
                    .units(allowed: [.hours, .minutes, .seconds], width: .abbreviated),
                ))
            } else if check.status == "IN_PROGRESS", let start = check.startedAt {
                Text(start, style: .timer)
            } else if check.isComplete || check.status == "IN_PROGRESS" || check.status == "PENDING" {
                Text("Duration unavailable")
            } else {
                Text("Not started")
            }
        }
        .interfaceFont(.caption)
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .fixedSize()
    }
}
