import Foundation
import NIOCore
import NIOPosix
import NIOSSH

// MARK: - SSHConnection

/// One authenticated connection multiplexing command and terminal channels.
actor SSHConnection {
    // MARK: Lifecycle

    init() {
        // The connection opens on demand.
    }

    // MARK: Internal

    func connect(_ configuration: SSHConfiguration) async throws {
        guard configuration.isValid else {
            throw RemoteError("Enter a host and sandbox username.")
        }

        try await connect(
            configuration,
            key: SSHCredentials.privateKey().rawRepresentation,
            pinned: SSHCredentials.hostKey(for: configuration.hostIdentity),
        )
    }

    func connect(_ configuration: SSHConfiguration, key: Data, pinned: String?) async throws {
        let loop = MultiThreadedEventLoopGroup.singleton.next()
        let authenticated = loop.makePromise(of: Void.self)
        let connecting = ClientBootstrap(group: loop)
            .connectTimeout(.seconds(Self.connectTimeout))
            .channelOption(ChannelOptions.socketOption(.so_keepalive), value: 1)
            .channelOption(ChannelOptions.socket(IPPROTO_TCP, TCP_KEEPALIVE), value: Self.keepaliveSeconds)
            .channelOption(ChannelOptions.socket(IPPROTO_TCP, TCP_KEEPINTVL), value: Self.keepaliveSeconds)
            .channelOption(ChannelOptions.socket(IPPROTO_TCP, TCP_KEEPCNT), value: Self.keepaliveRetries)
            .channelInitializer { channel in
                channel.eventLoop.makeCompletedFuture {
                    let ssh = try NIOSSHHandler(
                        role: .client(.init(
                            userAuthDelegate: SSHKeyAuthentication(username: configuration.username, key: key),
                            serverAuthDelegate: SSHHostAuthentication(pinned: pinned),
                        )),
                        allocator: channel.allocator,
                        inboundChildChannelInitializer: nil,
                    )
                    try channel.pipeline.syncOperations.addHandler(ssh)
                    try channel.pipeline.syncOperations.addHandler(SSHAuthenticationResult(promise: authenticated))
                }
            }
            .connect(host: configuration.endpointHost, port: configuration.port)
        connecting.cascadeFailure(to: authenticated)
        let connected = try await connecting.get()
        channel = connected
        let timeout = loop.scheduleTask(in: .seconds(Self.authenticationTimeout)) { connected.close(promise: nil) }
        defer { timeout.cancel() }
        do {
            try await authenticated.futureResult.get()
        } catch {
            try? await connected.close().get()
            channel = nil
            throw error
        }
    }

    func open(_ command: String) async throws -> SSHCommand {
        guard let channel, channel.isActive else {
            throw RemoteError("The SSH connection is closed.")
        }

        let (output, continuation) = AsyncThrowingStream<Data, Error>.makeStream()
        let promise = channel.eventLoop.makePromise(of: Channel.self)
        channel.eventLoop.execute {
            do {
                let handler = try channel.pipeline.syncOperations.handler(type: NIOSSHHandler.self)
                handler.createChannel(promise, channelType: .session) { child, _ in
                    child.eventLoop.makeCompletedFuture {
                        try child.pipeline.syncOperations.addHandler(
                            SSHCommandHandler(command: command, output: continuation),
                        )
                    }
                }
            } catch {
                promise.fail(error)
            }
        }
        let child = try await promise.futureResult.get()
        continuation.onTermination = { _ in child.close(promise: nil) }
        return SSHCommand(channel: child, output: output)
    }

    func execute(_ command: String, input: String = "") async throws -> String {
        let running = try await open(command)
        let timeout = channel?.eventLoop.scheduleTask(in: .seconds(Self.commandTimeout)) { running.close() }
        defer { timeout?.cancel(); running.close() }
        running.send(Data(input.utf8))
        running.endInput()
        var result = Data()
        for try await data in running.output {
            guard result.count + data.count <= Self.maximumOutputBytes else {
                throw RemoteError("The command returned too much data.")
            }

            result.append(data)
        }
        guard let text = String(data: result, encoding: .utf8) else {
            throw RemoteError("The remote command returned invalid text.")
        }

        return text
    }

    func disconnect() async {
        let closing = channel
        channel = nil
        try? await closing?.close().get()
    }

    // MARK: Private

    private static let maximumOutputBytes = 1_048_576
    private static let connectTimeout: Int64 = 15
    private static let authenticationTimeout: Int64 = 20
    private static let commandTimeout: Int64 = 120
    private static let keepaliveSeconds: Int32 = 10
    private static let keepaliveRetries: Int32 = 3

    private var channel: any Channel?
}

// MARK: - SSHCommand

/// Ordered byte input and streamed output for one remote command.
public struct SSHCommand: Sendable {
    // MARK: Lifecycle

    init(channel: any Channel, output: AsyncThrowingStream<Data, Error>) {
        self.channel = channel
        self.output = output
    }

    // MARK: Public

    public let output: AsyncThrowingStream<Data, Error>

    /// Writes bytes to this command’s standard input.
    public func send(_ data: Data) {
        channel.writeAndFlush(SSHChannelData(type: .channel, data: .byteBuffer(ByteBuffer(bytes: data))), promise: nil)
    }

    /// Releases the remote command channel.
    public func close() {
        channel.close(promise: nil)
    }

    // MARK: Internal

    func endInput() {
        channel.close(mode: .output, promise: nil)
    }

    // MARK: Private

    private let channel: any Channel
}
