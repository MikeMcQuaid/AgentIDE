@testable import AgentIDERemote
import Crypto
import NIOCore
import NIOPosix
import NIOSSH
import Testing

struct SSHAuthenticationResultTests {
    enum Outcome: CaseIterable {
        case pending
        case authenticated
        case failed
    }

    @Test(.timeLimit(.minutes(1)), arguments: Outcome.allCases)
    func `closing SSH completes authentication without replacing earlier results`(outcome: Outcome) async throws {
        let loop = MultiThreadedEventLoopGroup.singleton.next()
        let server = try await ServerBootstrap(group: loop).bind(host: "127.0.0.1", port: 0).get()
        defer { server.close(promise: nil) }
        let authenticated = loop.makePromise(of: Void.self)
        let key = Curve25519.Signing.PrivateKey().rawRepresentation
        let client = try await ClientBootstrap(group: loop)
            .channelInitializer { channel in
                channel.eventLoop.makeCompletedFuture {
                    try channel.pipeline.syncOperations.addHandler(NIOSSHHandler(
                        role: .client(.init(
                            userAuthDelegate: SSHKeyAuthentication(username: "sandvault-test", key: key),
                            serverAuthDelegate: SSHHostAuthentication(pinned: nil),
                        )),
                        allocator: channel.allocator,
                        inboundChildChannelInitializer: nil,
                    ))
                    try channel.pipeline.syncOperations.addHandler(SSHAuthenticationResult(promise: authenticated))
                }
            }
            .connect(host: "127.0.0.1", port: #require(server.localAddress?.port))
            .get()
        defer { client.close(promise: nil) }
        try await loop.submit {
            switch outcome {
            case .pending:
                break

            case .authenticated:
                client.pipeline.fireUserInboundEventTriggered(UserAuthSuccessEvent())

            case .failed:
                client.pipeline.fireErrorCaught(SSHHostKeyError.changed)
            }
            client.close(promise: nil)
        }
        .get()
        try await client.closeFuture.get()
        let result = try await loop.submit { authenticated.futureResult.assumeIsolated().result }.get()
        // Settle an unfinished promise after recording the result, so a regression cannot hang the test.
        if result == nil {
            authenticated.fail(RemoteError("Test cleanup"))
        }
        let completed = try #require(result)
        switch outcome {
        case .pending:
            let error = #expect(throws: RemoteError.self) { try completed.get() }
            #expect(error?.errorDescription?.contains("Install this phone's public key") == true)

        case .authenticated:
            try completed.get()

        case .failed:
            #expect(throws: SSHHostKeyError.self) { try completed.get() }
        }
    }
}
