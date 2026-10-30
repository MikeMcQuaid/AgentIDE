import Foundation
import NIOCore
import NIOSSH

final class SSHCommandHandler: ChannelInboundHandler {
    // MARK: Lifecycle

    init(command: String, output: AsyncThrowingStream<Data, Error>.Continuation) {
        self.command = command
        self.output = output
    }

    deinit { /* The channel owns this handler. */ }

    // MARK: Internal

    typealias InboundIn = SSHChannelData

    func channelActive(context: ChannelHandlerContext) {
        let channel = context.channel
        channel.setOption(ChannelOptions.allowRemoteHalfClosure, value: true).whenFailure { error in
            channel.pipeline.fireErrorCaught(error)
        }
        channel.triggerUserOutboundEvent(SSHChannelRequestEvent.ExecRequest(command: command, wantReply: true))
            .whenFailure { error in channel.pipeline.fireErrorCaught(error) }
    }

    func channelRead(context _: ChannelHandlerContext, data: NIOAny) {
        let payload = unwrapInboundIn(data)
        guard case let .byteBuffer(buffer) = payload.data else {
            return
        }

        let bytes = Data(buffer.readableBytesView)
        if payload.type == .stdErr {
            errors.append(contentsOf: bytes.prefix(max(0, Self.maximumErrorBytes - errors.count)))
        } else {
            output.yield(bytes)
        }
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if let status = event as? SSHChannelRequestEvent.ExitStatus {
            exitStatus = status.exitStatus
        }
        context.fireUserInboundEventTriggered(event)
    }

    func channelInactive(context: ChannelHandlerContext) {
        if exitStatus == 0 {
            output.finish()
        } else {
            let message = (String(data: errors, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            output.finish(throwing: RemoteError(message.isEmpty ? "The remote command disconnected." : message))
        }
        context.fireChannelInactive()
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        output.finish(throwing: error)
        context.close(promise: nil)
    }

    // MARK: Private

    private static let maximumErrorBytes = 65_536

    private let command: String
    private let output: AsyncThrowingStream<Data, Error>.Continuation
    private var exitStatus: Int?
    private var errors: Data = .init()
}
