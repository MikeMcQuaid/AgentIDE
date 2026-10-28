import Foundation

/// A bounded history of visible transitions, never refresh ticks.
public struct FeedbackActivity: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let date: Date
    public let message: String
}
