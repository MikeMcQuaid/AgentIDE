import AppKit
import Metal
@testable import SwiftTerm
@testable import TerminalUI
import Testing

@MainActor
struct TerminalRenderContentionTests {
    // MARK: Internal

    @Test(.enabled(if: MTLCreateSystemDefaultDevice() != nil), arguments: [false, true])
    func `typing does not wait for the renderer to acquire a drawable`(herdrBacked: Bool) throws {
        let view = PaneTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 400))
        view.isHerdrBacked = herdrBacked
        let window = NSWindow(contentRect: view.frame, styleMask: [], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = view
        let target = StalledTarget()
        try #require(view.renderOwner.replaceMetalRenderer(
            MetalTerminalRenderer(target: target), needsExternalDraw: true,
        ))
        view.feed(text: "prompt")
        view.frameTick()
        try #require(target.surface.entered.wait(timeout: .now() + 2) == .success)
        defer { target.surface.release.signal() }
        let start = ContinuousClock.now
        view.send(data: Array("a".utf8)[...])
        #expect(start.duration(to: .now) < .milliseconds(100))
    }

    // MARK: Private

    private struct StalledSurface: MetalRenderSurface {
        let entered: DispatchSemaphore = .init(value: 0)
        let release: DispatchSemaphore = .init(value: 0)

        func acquireDrawableFrame() -> MetalDrawableFrame? {
            entered.signal()
            _ = release.wait(timeout: .now() + 0.5)
            return nil
        }
    }

    private final class StalledTarget: MetalRenderTarget {
        // MARK: Lifecycle

        deinit {
            // No drawable resources are allocated.
        }

        // MARK: Internal

        let surface: StalledSurface = .init()
        var renderDevice: any MTLDevice? = MTLCreateSystemDefaultDevice()
        let renderPixelFormat: MTLPixelFormat = .bgra8Unorm
        var renderDrawableSize: CGSize = .init(width: 800, height: 400)
        let renderBounds: CGRect = .init(x: 0, y: 0, width: 800, height: 400)
        var renderContentsScale: CGFloat = 1
        let needsExternalDrawCall = true

        var renderGeometry: MetalSurfaceGeometry {
            MetalSurfaceGeometry(
                bounds: renderBounds, drawableSize: renderDrawableSize, contentsScale: renderContentsScale,
            )
        }

        var detachedRenderSurface: any MetalRenderSurface? {
            surface
        }

        func acquireDrawableFrame() -> MetalDrawableFrame? {
            nil
        }

        func requestDisplay() {
            // The test requests its frame explicitly.
        }
    }
}
