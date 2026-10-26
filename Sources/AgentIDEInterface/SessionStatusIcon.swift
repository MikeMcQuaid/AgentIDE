import AgentIDEDomain
import SwiftUI

/// The sidebar's shared vocabulary for agent activity.
public struct SessionStatusIcon: View {
    // MARK: Lifecycle

    public init(status: SessionStatus, activity: AgentActivity?) {
        self.status = status
        self.activity = activity
    }

    // MARK: Public

    public var body: some View {
        Image(systemName: appearance.symbol)
            .foregroundStyle(appearance.colour)
            .accessibilityLabel(appearance.help)
            .help(appearance.help)
    }

    // MARK: Private

    private struct Appearance {
        let symbol: String
        let colour: Color
        let help: String
    }

    private let status: SessionStatus
    private let activity: AgentActivity?

    private var appearance: Appearance {
        switch status {
        case .finished:
            Appearance(
                symbol: "xmark.circle",
                colour: .secondary,
                help: "The agent's process exited; the conversation stays resumable",
            )

        case .running:
            switch activity {
            case .blocked:
                Appearance(
                    symbol: "questionmark.circle.fill",
                    colour: .orange,
                    help: "The agent asked a question or wants an approval",
                )

            case .working:
                Appearance(symbol: "play.circle.fill", colour: .blue, help: "The agent is working on its turn")

            case .done:
                Appearance(
                    symbol: "stop.circle.fill",
                    colour: .green,
                    help: "The turn is done; the answer is waiting",
                )

            case .idle:
                Appearance(
                    symbol: "stop.circle",
                    colour: .secondary,
                    help: "At rest: nothing asked, interrupted or completed over 24 hours ago without further input",
                )

            case nil:
                Appearance(
                    symbol: "circle.dotted",
                    colour: .secondary,
                    help: "Running, but herdr cannot tell what the agent is doing",
                )
            }
        }
    }
}
