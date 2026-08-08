import SwiftUI
import WebKit

// MARK: - BrowserView

/// An embedded browser for previewing served pages and rendered
/// Markdown; agent-authored content is treated as untrusted, so the
/// data store is not persisted.
struct BrowserView: View {
    // MARK: Lifecycle

    /// Creates the browser.
    init() {
        // State holds the address.
    }

    // MARK: Internal

    /// An address bar over a web view.
    var body: some View {
        VStack(spacing: 0) {
            TextField("http://localhost:3000", text: $address)
                .textFieldStyle(.roundedBorder)
                .onSubmit { load() }
                .padding(Self.padding)
            Divider()
            WebPane(request: $request)
        }
    }

    // MARK: Private

    private static let padding: CGFloat = 8

    @State private var address = ""
    @State private var request: URLRequest?

    private func load() {
        guard let url = URL(string: address) else {
            return
        }

        request = URLRequest(url: url)
    }
}

// MARK: - WebPane

private struct WebPane: NSViewRepresentable {
    @Binding var request: URLRequest?

    func makeNSView(context _: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        return WKWebView(frame: .zero, configuration: configuration)
    }

    func updateNSView(_ view: WKWebView, context _: Context) {
        guard let request, view.url != request.url else {
            return
        }

        view.load(request)
    }
}
