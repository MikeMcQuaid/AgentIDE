import SwiftUI
import TerminalUI
import WebKit

// MARK: - BrowserView

/// An embedded browser for dev servers and pull request pages, one
/// per worktree. The data store persists and is shared, so a GitHub
/// login survives tab switches and restarts, and each worktree's
/// address is remembered so a page closed or lost to a restart comes
/// back where it was.
public struct BrowserView: View {
    // MARK: Lifecycle

    /// Creates the browser for a worktree. `isActive` says whether
    /// this is the pane on screen: the others stay loaded, but only
    /// this one takes an address asked for from elsewhere.
    public init(worktreePath: String, isActive: Bool) {
        self.worktreePath = worktreePath
        self.isActive = isActive
    }

    // MARK: Public

    /// An address bar over a web view. Programmatic address changes
    /// load immediately; typing loads only on return, since every
    /// keystroke of a partial address would otherwise navigate.
    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Self.padding) {
                TextField("Address", text: $address)
                    .textFieldStyle(.roundedBorder)
                    .focused($editingAddress)
                    .onSubmit { load() }
                    .hoverHelp("Enter an address and press return; useful for dev servers the agent starts")
                Button("Reset browser", systemImage: "xmark.circle") { reset() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .disabled(request == nil && address.isEmpty)
                    .hoverHelp("Close the page and clear the address, back to the empty browser")
            }
            .padding(Self.padding)
            Divider()
            ZStack {
                WebPane(request: $request, onProcess: record(processIdentifier:), onNavigate: follow(_:))
                if request == nil || (address.isEmpty && editingAddress == false) {
                    ContentUnavailableView(
                        "Nothing loaded",
                        systemImage: "safari",
                        description: Text("Enter an address above."),
                    )
                    // Opaque: it covers a reset page fully, in both
                    // colour schemes.
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.background, ignoresSafeAreaEdges: [])
                }
            }
        }
        .task(id: worktreePath) {
            // A worktree with no address of its own takes the one
            // last asked for, which is how a pull request page opens
            // in a worktree that has never had a browser.
            address = Self.addresses(in: storedAddresses)[worktreePath] ?? (isActive ? requestedAddress : "")
            load()
        }
        .onChange(of: address) {
            remember()
            if editingAddress == false {
                load()
            }
        }
        // An address asked for from elsewhere goes to the pane on
        // screen, never to the ones loaded behind it. The count is
        // what changes: the same page asked for twice writes the
        // same address, and the pane would sit on whatever it had
        // wandered to since.
        .onChange(of: requestedCount) {
            guard isActive, requestedAddress.isEmpty == false else {
                return
            }

            address = requestedAddress
            load()
        }
        .onDisappear { BrowserPanes.shared.remove(worktreePath: worktreePath) }
    }

    // MARK: Private

    private static let padding: CGFloat = 8

    /// The address bus other panes write to, and every worktree's
    /// own address, stored as path-address lines.
    @AppStorage(UtilityTabTarget.addressKey)
    private var requestedAddress = ""
    @AppStorage(UtilityTabTarget.requestKey)
    private var requestedCount = 0
    @AppStorage("browserAddresses")
    private var storedAddresses = ""

    @State private var address = ""
    @State private var request: URLRequest?

    @FocusState private var editingAddress: Bool

    private let worktreePath: String
    private let isActive: Bool

    /// Parses the stored path-address lines.
    private static func addresses(in lines: String) -> [String: String] {
        var addresses = [String: String]()
        for line in lines.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 1)
            if let path = parts.first, parts.count > 1, let page = parts.last {
                addresses[String(path)] = String(page)
            }
        }
        return addresses
    }

    /// Tells the register what this page is and what is rendering
    /// it, so the session manager can list and close it.
    private func record(processIdentifier: Int32?) {
        BrowserPanes.shared.record(BrowserPane(
            worktreePath: worktreePath,
            address: address,
            processIdentifier: processIdentifier,
        ))
    }

    /// Keeps this worktree's address for the next time its browser
    /// opens, including after a restart.
    private func remember() {
        var addresses = Self.addresses(in: storedAddresses)
        addresses[worktreePath] = address
        storedAddresses = addresses
            .filter { $0.value.isEmpty == false }
            .map { $0.key + "\t" + $0.value }
            .sorted()
            .joined(separator: "\n")
    }

    private func load() {
        guard let url = URL(string: address) else {
            return
        }

        request = URLRequest(url: url)
    }

    /// The page moved on its own, by a click or a redirect: the
    /// address bar says where it is now, and the worktree remembers
    /// it. Left alone while the field is being typed into, so a
    /// half-typed address is not replaced under the cursor. The
    /// request follows too, so the pane is not asked to load the
    /// page it is already on.
    private func follow(_ url: URL) {
        guard editingAddress == false, url.absoluteString != address, url.absoluteString != "about:blank" else {
            return
        }

        request = URLRequest(url: url)
        address = url.absoluteString
    }

    /// Back to the default empty page: a blank load replaces the
    /// page and the placeholder covers it.
    private func reset() {
        address = ""
        request = URL(string: "about:blank").map { URLRequest(url: $0) }
    }
}

// MARK: - WebPane

private struct WebPane: NSViewRepresentable {
    /// Reports the web content process behind the page whenever a
    /// navigation commits, since that is when WebKit has one and
    /// when it may have swapped for another.
    final class Coordinator: NSObject, WKNavigationDelegate {
        // MARK: Lifecycle

        init(onProcess: @escaping (Int32?) -> Void, onNavigate: @escaping (URL) -> Void) {
            self.onProcess = onProcess
            self.onNavigate = onNavigate
        }

        deinit {
            // The delegate dies with its view.
        }

        // MARK: Internal

        // The delegate's own signature hands over an implicitly
        // unwrapped navigation, which nothing here reads.
        // swiftlint:disable:next implicitly_unwrapped_optional
        func webView(_ webView: WKWebView, didCommit _: WKNavigation!) {
            onProcess(BrowserPanes.processIdentifier(of: webView))
            // Every committed navigation, clicked or redirected, is
            // where the page is now.
            if let url = webView.url {
                onNavigate(url)
            }
        }

        // MARK: Private

        private let onProcess: (Int32?) -> Void
        private let onNavigate: (URL) -> Void
    }

    @Binding var request: URLRequest?

    let onProcess: (Int32?) -> Void
    let onNavigate: (URL) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onProcess: onProcess, onNavigate: onNavigate)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // The shared persistent store keeps logins across tabs and
        // restarts.
        configuration.websiteDataStore = .default()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        return view
    }

    func updateNSView(_ view: WKWebView, context _: Context) {
        guard let request, view.url != request.url else {
            return
        }

        view.load(request)
    }
}
