import AgentIDEDomain
import SwiftUI

// MARK: - LaunchProgress

/// The step log one launch narrates into. Creation and resumes
/// report each step and what it is waiting on; the pane covering the
/// split shows the log with a clock, so a slow step names itself
/// rather than leaving a blank pane.
@Observable
public final class LaunchProgress {
    // MARK: Lifecycle

    /// Creates an empty log.
    public init() {
        // Steps arrive as launches report them.
    }

    deinit {
        // Nothing to release.
    }

    // MARK: Public

    /// One reported step and when it was reported.
    public struct Step: Identifiable, Sendable {
        /// Ordinal within the log, so identical texts stay distinct.
        public let id: Int

        /// What the launch is doing or waiting on.
        public let text: String

        /// When the step began.
        public let startedAt: Date
    }

    /// The steps reported since the last launch began.
    public private(set) var steps: [Step] = []

    /// The reporter services narrate through.
    public var reporter: LaunchReporter {
        { [self] text in report(text) }
    }

    /// Starts a fresh narration with its first step.
    public func begin(_ text: String) {
        steps = []
        report(text)
    }

    /// Appends a step.
    public func report(_ text: String) {
        steps.append(Step(id: steps.count, text: text, startedAt: Date()))
    }
}

// MARK: - LaunchProgressView

/// The narration filling a pane while a launch runs: every step with
/// how long it took, the current one still counting, redrawn every
/// second so something on screen always moves.
public struct LaunchProgressView: View {
    // MARK: Lifecycle

    /// Creates the view over a log, under a title saying what the
    /// launch is.
    public init(_ title: String, progress: LaunchProgress) {
        self.title = title
        self.progress = progress
    }

    // MARK: Public

    public var body: some View {
        TimelineView(.periodic(from: .now, by: Self.tickSeconds)) { context in
            VStack(alignment: .leading, spacing: Self.spacing) {
                ProgressView(title)
                ForEach(progress.steps) { step in
                    HStack(alignment: .firstTextBaseline, spacing: Self.spacing) {
                        Text(duration(of: step, now: context.date))
                            .foregroundStyle(.secondary)
                            .frame(width: Self.durationWidth, alignment: .trailing)
                        Text(step.text)
                            .lineLimit(Self.stepLines)
                    }
                    .font(.callout.monospaced())
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding()
        }
    }

    // MARK: Private

    private typealias Step = LaunchProgress.Step

    private static let tickSeconds = 1.0
    private static let spacing: CGFloat = 6
    private static let durationWidth: CGFloat = 44
    private static let stepLines = 3

    private let title: String
    private let progress: LaunchProgress

    /// How long a step took, or has taken so far for the last one.
    private func duration(of step: Step, now: Date) -> String {
        let end = progress.steps.first { $0.id == step.id + 1 }?.startedAt ?? now
        let seconds = Int(end.timeIntervalSince(step.startedAt))
        return (step.id == progress.steps.count - 1 ? "… " : "") + String(seconds) + "s"
    }
}
