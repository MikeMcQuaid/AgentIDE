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

/// The narration filling a pane while a launch or a load runs: the
/// steps so far under a title with the elapsed time, redrawn every
/// second so something on screen always moves, until the finished
/// UI snaps into place. One block, centred in the pane, every line
/// sharing its left edge. A step's backtick spans, its commands,
/// paths and names, render in monospace so the eye separates what
/// is being done from what it is done to.
public struct LaunchProgressView: View {
    // MARK: Lifecycle

    /// Creates the view over a log, under a title saying what the
    /// launch is.
    public init(_ title: String, progress: LaunchProgress) {
        self.title = title
        self.progress = progress
        waitingOn = nil
    }

    /// Creates the view for a load with one thing to wait on, named
    /// so the pane says what is slow; the clock runs from the view
    /// appearing.
    public init(_ title: String, waitingOn: String) {
        self.title = title
        progress = nil
        self.waitingOn = waitingOn
    }

    // MARK: Public

    public var body: some View {
        // Fast enough to type: each tick reveals a few more
        // characters, so the log writes itself out the way a
        // terminal does rather than appearing all at once.
        TimelineView(.periodic(from: appearedAt, by: Self.frameSeconds)) { context in
            let elapsed = max(0, context.date.timeIntervalSince(appearedAt))
            VStack(alignment: .leading, spacing: Self.lineSpacing) {
                if showsBanner {
                    Text(Self.typed(Self.bannerText, secondsIn: elapsed))
                        .foregroundStyle(Self.ink.opacity(Self.promptOpacity))
                }
                header(at: elapsed)
                ForEach(steps) { step in
                    line(step, at: context.date)
                }
            }
            .font(.system(.callout, design: .monospaced))
            // Phosphor: the same white bled a little around itself,
            // and a frame's dimming as each line lands.
            .shadow(color: Self.ink.opacity(Self.glowOpacity), radius: Self.glowRadius)
            .opacity(flicker(at: context.date))
            .frame(maxWidth: Self.blockWidth, alignment: .leading)
            // Pinned near the top so the log grows downwards: centred,
            // it shifted every line each time a step arrived.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(Self.padding)
            .padding(.top, Self.topInset)
            .background(alignment: .topLeading) {
                Self.screen.overlay(Scanlines())
            }
        }
    }

    // MARK: Private

    /// The type-on rate: characters a second, and how often the
    /// view redraws to show them.
    private static let charactersPerSecond = 20.0
    private static let framesPerSecond = 20.0
    private static let frameSeconds = 1.0 / framesPerSecond

    /// A dot a second on the newest step, cycling through three.
    private static let dotSeconds = 1.0
    private static let dotCycle = 3

    private static let lineSpacing: CGFloat = 3
    private static let blockWidth: CGFloat = 620
    private static let stepLines = 3
    private static let topInset: CGFloat = 40
    private static let padding: CGFloat = 20
    /// What the machine says before it says anything else, and
    /// what a finished line ends with, as a boot log's do.
    /// The bundle's own version, so a screenshot of a wait says
    /// which build took it; unversioned only when nothing built it.
    private static let bannerText: String = {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        return "AGENTIDE " + (version ?? "dev") + " · SANDBOXED AGENTS · READY"
    }()

    private static let doneMarker = " ... OK"
    private static let glowOpacity = 0.55
    private static let glowRadius: CGFloat = 2.5
    private static let flickerOpacity = 0.82
    private static let cursorBlinkSeconds = 0.6
    private static let blinkParity = 2
    private static let promptOpacity = 0.55

    /// The panel the log is written on: the app's own dark card,
    /// under whichever appearance the window is in, so the pane
    /// reads as a screen rather than as an empty view.
    private static let screenOpacity = 0.85
    private static let screen = Color.black.opacity(screenOpacity)

    /// Written in the phosphor white the icon uses, with the prompt
    /// and the clock dimmer than what they introduce.
    private static let ink: Color = .white

    /// Whether this view is the first, and so the one to say it.
    private static var bannerClaimed = false

    @State private var appearedAt: Date = .init()

    /// The machine announces itself once a run: the first wait the
    /// app shows carries the banner, and every wait after it is
    /// just the work.
    @State private var showsBanner: Bool = Self.claimBanner()

    private let title: String
    private let progress: LaunchProgress?
    private let waitingOn: String?

    private var steps: [LaunchProgress.Step] {
        progress?.steps
            ?? waitingOn.map { [LaunchProgress.Step(id: 0, text: "Waiting on " + $0, startedAt: appearedAt)] }
            ?? []
    }

    /// The banner: what is happening, and how long it has taken.
    private func header(at elapsed: TimeInterval) -> some View {
        HStack(spacing: 0) {
            Text(Self.typed(title, secondsIn: elapsed))
                .foregroundStyle(Self.ink)
            cursor(at: elapsed, shown: Self.isTyping(title, secondsIn: elapsed))
            Spacer(minLength: Self.lineSpacing)
            Text(String(Int(elapsed)) + "s")
                .foregroundStyle(Self.ink.opacity(Self.promptOpacity))
                .monospacedDigit()
        }
    }

    /// One step, typed out from the moment it was reported, with the
    /// cursor sitting at the end of the newest line.
    private func line(_ step: LaunchProgress.Step, at now: Date) -> some View {
        let since = max(0, now.timeIntervalSince(step.startedAt))
        let isDone = step.id != steps.last?.id
        let text = step.text + (isDone ? Self.doneMarker : waitingDots(on: step, at: now))
        return HStack(spacing: 0) {
            Text(verbatim: "> ")
                .foregroundStyle(Self.ink.opacity(Self.promptOpacity))
            Text(Self.styled(isDone ? text : Self.typed(text, secondsIn: since)))
                .foregroundStyle(Self.ink)
                .lineLimit(Self.stepLines)
            cursor(at: since, shown: step.id == steps.last?.id)
            Spacer(minLength: 0)
        }
    }

    /// The block cursor: solid while characters are still arriving,
    /// blinking once they have stopped, so a wait looks alive.
    @ViewBuilder
    private func cursor(at elapsed: TimeInterval, shown: Bool) -> some View {
        if shown {
            let blinking = Int(elapsed / Self.cursorBlinkSeconds).isMultiple(of: Self.blinkParity)
            Text(verbatim: "\u{2588}")
                .foregroundStyle(Self.ink)
                .opacity(blinking ? 1 : 0)
        }
    }

    private static func claimBanner() -> Bool {
        guard bannerClaimed == false else {
            return false
        }

        bannerClaimed = true
        return true
    }

    /// As much of a line as has been typed by now.
    private static func typed(_ text: String, secondsIn seconds: TimeInterval) -> String {
        String(text.prefix(Int(seconds * charactersPerSecond)))
    }

    private static func isTyping(_ text: String, secondsIn seconds: TimeInterval) -> Bool {
        typed(text, secondsIn: seconds).count < text.count
    }

    /// The step with its backtick spans marked as code; a span the
    /// markdown parser refuses renders as typed.
    private static func styled(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }

    /// One frame dimmer as each line arrives, then steady again.
    private func flicker(at now: Date) -> Double {
        guard let latest = steps.last?.startedAt else {
            return 1
        }

        let since = now.timeIntervalSince(latest)
        return since >= 0 && since < Self.frameSeconds ? Self.flickerOpacity : 1
    }

    /// A dot a second on the newest step, up to three: a step that
    /// waits without reporting anything still has to show the app is
    /// working rather than stopped.
    private func waitingDots(on step: LaunchProgress.Step, at now: Date) -> String {
        guard step.id == steps.last?.id else {
            return ""
        }

        let ticks = Int(max(0, now.timeIntervalSince(step.startedAt)) / Self.dotSeconds)
        return String(repeating: ".", count: 1 + ticks % Self.dotCycle)
    }
}

// MARK: - Scanlines

/// The faint banding a screen has, tiled down the panel: one
/// gradient repeated rather than a view for every line.
private struct Scanlines: View {
    // MARK: Internal

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                ForEach(0 ..< rows(in: geometry.size.height), id: \.self) { _ in
                    LinearGradient(
                        colors: [.black.opacity(Self.opacity), .clear, .black.opacity(Self.opacity)],
                        startPoint: .top,
                        endPoint: .bottom,
                    )
                    .frame(height: Self.height)
                }
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: Private

    private static let opacity = 0.16
    private static let height: CGFloat = 3

    private func rows(in height: CGFloat) -> Int {
        Int(height / Self.height) + 1
    }
}
