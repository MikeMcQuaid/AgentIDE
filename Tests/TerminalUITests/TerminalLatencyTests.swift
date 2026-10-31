import AppKit
import Metal
import SanductorData
import SanductorDomain
import Synchronization
@testable import TerminalUI
import Testing

@MainActor
struct TerminalLatencyTests {
    @Test(.enabled(if: MTLCreateSystemDefaultDevice() != nil), arguments: [false, true])
    func `attached terminals render outside the main thread`(herdrBacked: Bool) {
        let view = PaneTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 400))
        view.isHerdrBacked = herdrBacked
        let window = NSWindow(contentRect: view.frame, styleMask: [], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = view
        #expect(view.isUsingMetalRenderer)
        #expect(view.isUsingRenderLoop)
        window.contentView = nil
        #expect(view.isUsingRenderLoop == false)
        window.contentView = view
        #expect(view.isUsingRenderLoop)
    }

    @Test
    func `keys and complete pastes reach herdr without another main queue turn`() async throws {
        let channel = HerdrTerminalChannel(command: ["/usr/bin/sed", "-l", "s/terminal.input/terminal.frame/"])
        let stream = try await channel.start()
        let received = Mutex([[UInt8]]())
        let delivered = DispatchSemaphore(value: 0)
        let reader = Task.detached {
            for await event in stream {
                if case let .frame(bytes) = event {
                    received.withLock { $0.append(bytes) }
                    delivered.signal()
                }
            }
        }
        let view = PaneTerminalView(frame: .zero)
        let coordinator = TerminalRepresentable.Coordinator(onProcessTerminated: nil)
        coordinator.channel = channel
        coordinator.view = view
        view.terminalDelegate = coordinator
        let payloads = [Array("a".utf8), HerdrTerminal.pasteBytes("two\nlines"), Array("b".utf8)]
        for bytes in payloads {
            view.send(data: bytes[...])
        }
        // Hold the main queue: delivery must not need another turn on it.
        for _ in payloads {
            // swiftformat:disable:next redundantClosure -- Deliberately block inside a synchronous context.
            #expect({ delivered.wait(timeout: .now() + 1) }() == .success)
        }
        #expect(received.withLock { $0 } == payloads)
        reader.cancel()
        coordinator.tearDown()
        await channel.stop()
    }
}
