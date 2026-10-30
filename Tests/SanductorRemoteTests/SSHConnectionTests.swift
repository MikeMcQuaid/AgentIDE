import Crypto
import Foundation
import NIOCore
import NIOPosix
import NIOSSH
@testable import SanductorRemote
import Testing

// MARK: - SSHConnectionTests

struct SSHConnectionTests {
    @Test(.timeLimit(.minutes(1)))
    func `a refused SSH connection gives Remote Login guidance`() async throws {
        let server = try await SSHTestServer.start()
        try await server.channel.close().get()
        let connection = SSHConnection()
        do {
            try await connection.connect(server.configuration, key: server.key, pinned: server.hostKey)
            Issue.record("Connected to a closed SSH port")
        } catch {
            let message = server.configuration.errorMessage(error)
            #expect(message.contains("Remote Login"))
            #expect(message.contains(String(server.configuration.port)))
        }
        await connection.disconnect()
    }

    @Test(.timeLimit(.minutes(1)), arguments: ["127.0.0.1", " \t127.0.0.1\r\n"])
    func `authenticated channels preserve input EOF output and exit failures`(host: String) async throws {
        let server = try await SSHTestServer.start()
        defer { server.channel.close(promise: nil) }
        let connection = SSHConnection()
        var configuration = server.configuration
        configuration.host = host
        try await connection.connect(configuration, key: server.key, pinned: server.hostKey)
        do {
            async let first = connection.execute("echo", input: "first\n雪\n")
            async let second = connection.execute("echo", input: "second")
            #expect(try await first == "first\n雪\n")
            #expect(try await second == "second")
            await #expect(throws: RemoteError.self) { try await connection.execute("fail") }
            #expect(try await connection.execute("echo", input: "still connected") == "still connected")
        } catch {
            await connection.disconnect()
            throw error
        }
        await connection.disconnect()
    }

    @Test(.timeLimit(.minutes(1)))
    func `unknown and changed host keys cannot authenticate`() async throws {
        let server = try await SSHTestServer.start()
        defer { server.channel.close(promise: nil) }
        for pin in [nil, "ssh-ed25519 wrong"] {
            let connection = SSHConnection()
            do {
                try await connection.connect(server.configuration, key: server.key, pinned: pin)
                Issue.record("An unverified host was accepted")
            } catch let error as SSHHostKeyError {
                switch error {
                case let .unknown(key):
                    #expect(pin == nil && key == server.hostKey)

                case .changed:
                    #expect(pin != nil)
                }
            }
            await connection.disconnect()
        }
    }
}

// MARK: - SSHTestServer

private struct SSHTestServer {
    let channel: any Channel
    let configuration: SSHConfiguration
    let key: Data
    let hostKey: String

    static func start() async throws -> Self {
        let identity = Curve25519.Signing.PrivateKey()
        let host = Curve25519.Signing.PrivateKey()
        let hostBytes = host.rawRepresentation
        let publicKey = NIOSSHPrivateKey(ed25519Key: identity).publicKey
        let listener = try await ServerBootstrap(group: MultiThreadedEventLoopGroup.singleton)
            .childChannelInitializer { channel in
                channel.eventLoop.makeCompletedFuture {
                    let signingKey = try NIOSSHPrivateKey(ed25519Key: .init(rawRepresentation: hostBytes))
                    let role = SSHConnectionRole.server(.init(
                        hostKeys: [signingKey], userAuthDelegate: SSHTestAuthentication(key: publicKey),
                    ))
                    let ssh = NIOSSHHandler(role: role, allocator: channel.allocator) { child, _ in
                        child.eventLoop.makeCompletedFuture {
                            try child.pipeline.syncOperations.addHandler(SSHTestCommand())
                        }
                    }
                    try channel.pipeline.syncOperations.addHandler(ssh)
                }
            }
            .bind(host: "127.0.0.1", port: 0)
            .get()
        var destination = SSHConfiguration()
        destination.host = "127.0.0.1"
        destination.port = try #require(listener.localAddress?.port)
        destination.username = "sandvault-test"
        return Self(
            channel: listener,
            configuration: destination,
            key: identity.rawRepresentation,
            hostKey: String(openSSHPublicKey: NIOSSHPrivateKey(ed25519Key: host).publicKey),
        )
    }
}

// MARK: - SSHTestAuthentication

private final class SSHTestAuthentication: NIOSSHServerUserAuthenticationDelegate {
    // MARK: Lifecycle

    init(key: NIOSSHPublicKey) {
        self.key = key
    }

    deinit { /* The server owns the delegate. */ }

    // MARK: Internal

    var supportedAuthenticationMethods: NIOSSHAvailableUserAuthenticationMethods {
        .publicKey
    }

    func requestReceived(
        request: NIOSSHUserAuthenticationRequest,
        responsePromise: EventLoopPromise<NIOSSHUserAuthenticationOutcome>,
    ) {
        guard request.username == "sandvault-test", case let .publicKey(received) = request.request else {
            responsePromise.succeed(.failure)
            return
        }

        responsePromise.succeed(received.publicKey == key ? .success : .failure)
    }

    // MARK: Private

    private let key: NIOSSHPublicKey
}

// MARK: - SSHTestCommand

private final class SSHTestCommand: ChannelInboundHandler {
    // MARK: Lifecycle

    deinit { /* The channel owns the handler. */ }

    // MARK: Internal

    typealias InboundIn = SSHChannelData

    func handlerAdded(context: ChannelHandlerContext) {
        context.channel.setOption(ChannelOptions.allowRemoteHalfClosure, value: true).whenFailure { error in
            Issue.record(error)
        }
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if let request = event as? SSHChannelRequestEvent.ExecRequest {
            fails = request.command == "fail"
            if request.wantReply {
                context.triggerUserOutboundEvent(ChannelSuccessEvent(), promise: nil)
            }
        } else if let channelEvent = event as? ChannelEvent, channelEvent == .inputClosed {
            let channel = context.channel
            if fails {
                channel.writeAndFlush(
                    SSHChannelData(type: .stdErr, data: .byteBuffer(ByteBuffer(string: "failed"))),
                    promise: nil,
                )
            }
            channel.triggerUserOutboundEvent(SSHChannelRequestEvent.ExitStatus(exitStatus: fails ? 1 : 0))
                .whenComplete { _ in channel.close(promise: nil) }
        }
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        context.writeAndFlush(data, promise: nil)
    }

    // MARK: Private

    private var fails = false
}
