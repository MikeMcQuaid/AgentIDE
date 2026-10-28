import Foundation

// MARK: - SSHConfiguration

/// The saved destination; private keys are stored separately in Keychain.
public struct SSHConfiguration: Codable, Equatable, Sendable {
    // MARK: Lifecycle

    public init() {
        // Preferences supply the initial values.
    }

    // MARK: Public

    public static let usernamePrefix = "sandvault-"

    public var host = ""
    public var port = 22
    public var username: String = Self.usernamePrefix
    public var session = "sanductor"

    public var isValid: Bool {
        endpointHost.isEmpty == false
            && (1 ... Self.maximumPort).contains(port)
            && username.hasPrefix(Self.usernamePrefix) && username.count > Self.usernamePrefix.count
            && username.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "-_.".contains($0)) }
            && session.isEmpty == false && session != "default"
            && session.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }

    public var hostIdentity: String {
        endpointHost.lowercased() + ":" + String(port)
    }

    /// The destination shared by connections, host-key pins and diagnostics.
    public var endpointHost: String {
        host.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func command(_ arguments: [String]) -> String {
        "unset HERDR_SOCKET_PATH; export PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin; "
            + "export HERDR_SESSION="
            + Self.quote(session) + "; exec " + arguments.map(Self.quote).joined(separator: " ")
    }

    // MARK: Internal

    static func quote(_ value: String) -> String {
        "'" + value.replacing("'", with: "'\\''") + "'"
    }

    // MARK: Private

    private static let maximumPort = 65_535
}

// MARK: - RemoteError

/// A remote command failed before its result could be used.
public struct RemoteError: Error, LocalizedError, Sendable {
    // MARK: Lifecycle

    public init(_ message: String) {
        self.message = message
    }

    // MARK: Public

    public var errorDescription: String? {
        message
    }

    // MARK: Private

    private let message: String
}
