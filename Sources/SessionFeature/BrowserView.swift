import SwiftUI
import TerminalUI
import WebKit

// MARK: - BrowserView

/// An embedded browser for dev servers and pull request pages. The
/// data store persists and is shared, so a GitHub login survives
/// tab switches and restarts.
public struct BrowserView: View {
    // MARK: Lifecycle

    /// Creates the browser.
    public init() {
        // State holds the address.
    }

    // MARK: Public

    /// An address bar over a web view. Programmatic address changes
    /// load immediately; typing loads only on return, since every
    /// keystroke of a partial address would otherwise navigate.
    public var body: some View {
        VStack(spacing: 0) {
            TextField("http://localhost:3000", text: $address)
                .textFieldStyle(.roundedBorder)
                .focused($editingAddress)
                .onSubmit { load() }
                .padding(Self.padding)
                .hoverHelp("Enter an address and press return; useful for dev servers the agent starts")
            Divider()
            ZStack {
                WebPane(request: $request)
                if request == nil {
                    ContentUnavailableView(
                        "Nothing loaded",
                        systemImage: "safari",
                        description: Text("Preview what the agent built: enter a local dev server address above."),
                    )
                }
            }
        }
        .onAppear { load() }
        .onChange(of: address) {
            if editingAddress == false {
                load()
            }
        }
    }

    // MARK: Private

    private static let padding: CGFloat = 8

    @AppStorage("browserAddress")
    private var address = ""
    @State private var request: URLRequest?

    @FocusState private var editingAddress: Bool

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
        // The shared persistent store keeps logins across tabs and
        // restarts.
        configuration.websiteDataStore = .default()
        return WKWebView(frame: .zero, configuration: configuration)
    }

    func updateNSView(_ view: WKWebView, context _: Context) {
        guard let request, view.url != request.url else {
            return
        }

        view.load(request)
    }
}
