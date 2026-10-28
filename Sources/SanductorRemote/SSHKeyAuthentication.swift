import Foundation
import NIOCore
import NIOSSH

// MARK: - SSHKeyAuthentication

final class SSHKeyAuthentication: NIOSSHClientUserAuthenticationDelegate {
    // MARK: Lifecycle

    init(username: String, key: Data) throws {
        offer = try NIOSSHUserAuthenticationOffer(
            username: username,
            serviceName: "ssh-connection",
            offer: .privateKey(.init(privateKey: NIOSSHPrivateKey(ed25519Key: .init(rawRepresentation: key)))),
        )
    }

    deinit { /* The channel owns this handler. */ }

    // MARK: Internal

    func nextAuthenticationType(
        availableMethods: NIOSSHAvailableUserAuthenticationMethods,
        nextChallengePromise: EventLoopPromise<NIOSSHUserAuthenticationOffer?>,
    ) {
        defer { offer = nil }
        nextChallengePromise.succeed(availableMethods.contains(.publicKey) ? offer : nil)
    }

    // MARK: Private

    private var offer: NIOSSHUserAuthenticationOffer?
}

// MARK: - SSHHostAuthentication

final class SSHHostAuthentication: NIOSSHClientServerAuthenticationDelegate {
    // MARK: Lifecycle

    init(pinned: String?) {
        self.pinned = pinned
    }

    deinit { /* The channel owns this handler. */ }

    // MARK: Internal

    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        let received = String(openSSHPublicKey: hostKey)
        guard let pinned else {
            validationCompletePromise.fail(SSHHostKeyError.unknown(received))
            return
        }
        guard pinned == received else {
            validationCompletePromise.fail(SSHHostKeyError.changed)
            return
        }

        validationCompletePromise.succeed(())
    }

    // MARK: Private

    private let pinned: String?
}

// MARK: - SSHAuthenticationResult

final class SSHAuthenticationResult: ChannelInboundHandler {
    // MARK: Lifecycle

    init(promise: EventLoopPromise<Void>) {
        self.promise = promise
    }

    deinit { /* The channel owns this handler. */ }

    // MARK: Internal

    typealias InboundIn = Any

    func handlerAdded(context: ChannelHandlerContext) {
        // NIOSSH consumes channelInactive; retain this handler through pipeline teardown.
        context.channel.closeFuture.assumeIsolated().whenComplete { [self] _ in
            promise?.fail(RemoteError(
                "SSH authentication failed. Install this phone's public key for the sandbox user.",
            ))
            promise = nil
        }
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if event is UserAuthSuccessEvent {
            promise?.succeed(())
            promise = nil
        }
        context.fireUserInboundEventTriggered(event)
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        promise?.fail(error)
        promise = nil
        context.close(promise: nil)
    }

    // MARK: Private

    private var promise: EventLoopPromise<Void>?
}
