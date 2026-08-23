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

/// The narration filling a pane while a launch runs: the steps so
/// far under a title with the launch's elapsed time, redrawn every
/// second so something on screen always moves. One block, centred
/// in the pane, every line sharing its left edge. A step's backtick
/// spans, its commands, paths and names, render in monospace so the
/// eye separates what is being done from what it is done to.
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
                HStack(spacing: Self.spacing) {
                    ProgressView()
                        .controlSize(.small)
                    Text(title)
                    Text(elapsed(at: context.date))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                ForEach(progress.steps) { step in
                    Text(Self.styled(step.text))
                        .font(.callout)
                        .lineLimit(Self.stepLines)
                }
            }
            .frame(maxWidth: Self.blockWidth, alignment: .leading)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        }
    }

    // MARK: Private

    private static let tickSeconds = 1.0
    private static let spacing: CGFloat = 6
    private static let blockWidth: CGFloat = 560
    private static let stepLines = 3

    private let title: String
    private let progress: LaunchProgress

    /// The step with its backtick spans marked as code; a span the
    /// markdown parser refuses renders as typed.
    private static func styled(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }

    /// How long the launch has run, from its first step.
    private func elapsed(at now: Date) -> String {
        guard let first = progress.steps.first else {
            return ""
        }

        return String(Int(now.timeIntervalSince(first.startedAt))) + "s"
    }
}
