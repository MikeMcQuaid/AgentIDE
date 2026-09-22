/// Human feedback retained from reviews saved before per-comment actions.
public struct ReviewFeedback: Codable, Equatable, Sendable {
    // The earlier Agree/Disagree choice, retained with the saved notes.
    // periphery:ignore - retained when decoding and re-encoding earlier human feedback.
    // swiftlint:disable:next discouraged_optional_boolean
    public var agrees: Bool?
    public var notes = ""
}
