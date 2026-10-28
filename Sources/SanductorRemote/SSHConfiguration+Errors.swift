import Foundation
import NIOCore
import NIOPosix

public extension SSHConfiguration {
    /// Explains a failed connection with its destination and recovery steps.
    func errorMessage(_ error: any Error) -> String {
        if let message = (error as? any LocalizedError)?.errorDescription {
            return message
        }
        if let connection = error as? NIOConnectionError,
           let cause = connection.connectionErrors.first?.error ?? connection.dnsAError ?? connection.dnsAAAAError
        {
            return errorMessage(cause)
        }
        switch error {
        case let failure as IOError:
            return socketErrorMessage(failure)

        case is SocketAddressError.UnknownHost:
            return "Could not find " + destination + ". Check the hostname or use your Mac's IP address."

        case ChannelError.connectTimeout:
            return "The connection to " + destination + " timed out. Check that your Mac is awake and reachable."

        case ChannelError.alreadyClosed,
             ChannelError.eof,
             ChannelError.ioOnClosedChannel:
            return "The connection to " + destination + " closed. Check your network and reconnect."

        default:
            return "The SSH connection to " + destination + " failed. Check your SSH settings and reconnect. "
                + String(describing: error)
        }
    }

    // MARK: Private

    private var destination: String {
        endpointHost + " on port " + String(port)
    }

    private func socketErrorMessage(_ error: IOError) -> String {
        switch error.errnoCode {
        case EACCES,
             EPERM:
            "Network permission was denied for " + destination
                + ". In iPhone Settings, allow Sanductor access to the local network and check VPN restrictions."

        case ECONNREFUSED:
            "The Mac refused the connection to " + destination
                + ". Enable Remote Login on your Mac and check the SSH port."

        case ETIMEDOUT:
            "The connection to " + destination + " timed out. Check that your Mac is awake and reachable."

        case EHOSTUNREACH,
             ENETDOWN,
             ENETUNREACH:
            "Cannot reach " + destination + ". Check your network or VPN and that your Mac is awake."

        case ECONNABORTED,
             ECONNRESET,
             EPIPE:
            "The connection to " + destination + " closed. Check your network and reconnect."

        default:
            "The connection to " + destination + " failed: " + error.description
        }
    }
}
