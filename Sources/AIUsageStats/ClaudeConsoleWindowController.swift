import AppKit
import WebKit
import UsageCore

@MainActor
private final class ConsoleObservationHandler: NSObject, WKScriptMessageHandler {
    weak var owner: ClaudeConsoleWindowController?
    init(owner: ClaudeConsoleWindowController) { self.owner = owner }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        owner?.receiveObservation(message)
    }
}

@MainActor
final class ClaudeConsoleWindowController: NSWindowController, WKNavigationDelegate, WKUIDelegate, NSWindowDelegate {
    private struct BrowserResponse: Decodable {
        let status: Int
        let contentType: String
        let body: String
        let redirected: Bool
    }

    private let profile: AccountProfile
    private let model: ApplicationModel
    private let webView: WKWebView
    private let status = InterfaceControls.label("Sign in on the official Claude Console page, then read your API credits.")
    private let organization = NSPopUpButton(frame: .zero, pullsDown: false)
    private let readButton = NSButton(title: "Read API Credits", target: nil, action: nil)
    private let signInButton = NSButton(title: "Open Sign-In", target: nil, action: nil)
    private let disconnectButton = NSButton(title: "Disconnect", target: nil, action: nil)
    private var organizations: [ClaudeConsoleOrganization] = []
    private var isFetching = false
    private var navigationWaiter: CheckedContinuation<Void, Error>?
    private var awaitedNavigation: WKNavigation?
    private var navigationTimer: Timer?
    private var responseWaiter: (path: String, continuation: CheckedContinuation<Data, Error>)?
    private var responseTimer: Timer?
    private var refreshTask: Task<Void, Never>?
    private var isPaused = false
    private let billingURL = URL(string: "https://platform.claude.com/settings/billing")!

    init(profile: AccountProfile, model: ApplicationModel) {
        self.profile = profile
        self.model = model
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = WKWebsiteDataStore(forIdentifier: profile.id)
        webView = WKWebView(frame: .zero, configuration: configuration)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 950, height: 760),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "\(profile.label) · Claude API Credits"
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 700, height: 560)
        super.init(window: window)
        configuration.userContentController.add(ConsoleObservationHandler(owner: self), name: "ClaudeConsoleObservation")
        configuration.userContentController.addUserScript(WKUserScript(source: Self.observationScript,
                                                                       injectionTime: .atDocumentStart,
                                                                       forMainFrameOnly: true))
        window.delegate = self
        webView.navigationDelegate = self
        webView.uiDelegate = self
        readButton.target = self
        readButton.action = #selector(readCredits(_:))
        signInButton.target = self
        signInButton.action = #selector(showSignIn(_:))
        disconnectButton.target = self
        disconnectButton.action = #selector(disconnect(_:))
        organization.setAccessibilityLabel("Claude Console organization")
        organization.addItem(withTitle: "Organization appears after sign-in")
        let controls = NSStackView(views: [organization, readButton, signInButton, disconnectButton])
        controls.orientation = .horizontal
        controls.spacing = 8
        let explanation = InterfaceControls.label("This account uses its own saved Console login. AI Usage Stats reads balances and grant expiration dates. Billing changes are made only on the official provider page.")
        if let root = window.contentView {
            for component in [explanation, controls, status, webView] {
                component.translatesAutoresizingMaskIntoConstraints = false
                root.addSubview(component)
            }
            NSLayoutConstraint.activate([
                explanation.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
                explanation.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
                explanation.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
                controls.leadingAnchor.constraint(equalTo: explanation.leadingAnchor),
                controls.trailingAnchor.constraint(equalTo: explanation.trailingAnchor),
                controls.topAnchor.constraint(equalTo: explanation.bottomAnchor, constant: 10),
                status.leadingAnchor.constraint(equalTo: explanation.leadingAnchor),
                status.trailingAnchor.constraint(equalTo: explanation.trailingAnchor),
                status.topAnchor.constraint(equalTo: controls.bottomAnchor, constant: 8),
                webView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
                webView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
                webView.topAnchor.constraint(equalTo: status.bottomAnchor, constant: 12),
                webView.bottomAnchor.constraint(equalTo: root.bottomAnchor)
            ])
        }
        window.center()
    }
    required init?(coder: NSCoder) { nil }

    override func showWindow(_ sender: Any?) {
        isPaused = false
        webView.isHidden = false
        if !isFetching { webView.load(URLRequest(url: billingURL)) }
        super.showWindow(sender)
    }

    func refreshInBackground() {
        guard model.consoleConnections[profile.id] != nil, !isFetching else { return }
        startFetch(isInteractive: false)
    }

    @objc private func readCredits(_ sender: Any?) { startFetch(isInteractive: true) }
    @objc private func showSignIn(_ sender: Any?) {
        guard !isFetching else { return }
        webView.isHidden = false
        webView.load(URLRequest(url: billingURL))
        status.stringValue = "Sign in to Claude Console, then read your API credits."
    }

    private func startFetch(isInteractive: Bool) {
        guard !isFetching else { return }
        isPaused = false
        isFetching = true
        readButton.isEnabled = false
        signInButton.isEnabled = false
        disconnectButton.isEnabled = false
        status.stringValue = "Reading Claude Console organizations and balances…"
        refreshTask = Task { [weak self] in
            guard let self else { return }
            defer {
                isFetching = false
                readButton.isEnabled = true
                signInButton.isEnabled = true
                disconnectButton.isEnabled = true
                refreshTask = nil
                if !isPaused, window?.isVisible != true { parkBrowser() }
            }
            do {
                try await prepareBrowser()
                let account = try ClaudeConsoleAccount.decode(try await get(ClaudeConsoleClient.accountURL))
                let previouslySelected = selectedOrganizationID
                organizations = account.organizations.filter { $0.capabilities.isEmpty || $0.capabilities.contains("api") || $0.capabilities.contains("api_individual") }
                guard !organizations.isEmpty else { throw UsageError.providerFailure("This Console login has no API organization.") }
                let connectedID = model.consoleConnections[profile.id]
                var selectedID = isInteractive ? (previouslySelected ?? connectedID) : connectedID
                configureOrganizations(selectedID: selectedID)
                if selectedID == nil, organizations.count == 1 { selectedID = organizations[0].id; organization.selectItem(at: 1) }
                guard let selectedID, organizations.contains(where: { $0.id == selectedID }) else {
                    if isInteractive {
                        status.stringValue = "Signed in\(account.email.map { " as \($0)" } ?? ""). Select your API organization, then read credits."
                        return
                    }
                    throw UsageError.authenticationRequired("The saved Console login no longer has access to the connected organization. Open Manage Claude API Credits to sign in again.")
                }
                let url = try ClaudeConsoleClient.balanceURL(organizationID: selectedID)
                let response = try await get(url)
                try Task.checkCancellation()
                // Decode before saving the connection so malformed data cannot replace an existing connection.
                _ = try ClaudeConsoleBalance.decode(response, organizationID: selectedID)
                try await model.setConsoleConnection(accountID: profile.id, organizationID: selectedID, expectedIdentity: profile.providerAccountID)
                try await model.updateConsoleCredits(accountID: profile.id, organizationID: selectedID, responseData: response, expectedIdentity: profile.providerAccountID)
                status.stringValue = "Connected\(account.email.map { " as \($0)" } ?? "") · Read \(InterfaceFormatting.exactDate(Date())). Credits refresh every 5 minutes."
            } catch {
                if Task.isCancelled || error is CancellationError { status.stringValue = "Credits refresh paused."; return }
                let message = error.localizedDescription
                status.stringValue = message
                model.recordConsoleError(accountID: profile.id, message: message)
            }
        }
    }

    private var selectedOrganizationID: String? {
        let index = organization.indexOfSelectedItem - 1
        return organizations.indices.contains(index) ? organizations[index].id : nil
    }

    private func configureOrganizations(selectedID: String?) {
        organization.removeAllItems()
        organization.addItem(withTitle: "Select organization…")
        organization.addItems(withTitles: organizations.map(\.name))
        if let selectedID, let index = organizations.firstIndex(where: { $0.id == selectedID }) {
            organization.selectItem(at: index + 1)
        }
    }

    private func prepareBrowser() async throws {
        try Task.checkCancellation()
        if webView.url?.host == "platform.claude.com", webView.url?.scheme == "https", !webView.isLoading { return }
        try await withCheckedThrowingContinuation { continuation in
            navigationWaiter = continuation
            awaitedNavigation = webView.load(URLRequest(url: window?.isVisible == true ? billingURL : ClaudeConsoleClient.accountURL, timeoutInterval: 20))
            navigationTimer = Timer.scheduledTimer(timeInterval: 20, target: self,
                                                  selector: #selector(navigationTimedOut(_:)), userInfo: nil, repeats: false)
        }
    }

    private func get(_ url: URL) async throws -> Data {
        try Task.checkCancellation()
        guard url.scheme == "https", url.host == "platform.claude.com",
              webView.url?.scheme == "https", webView.url?.host == "platform.claude.com" else {
            throw UsageError.invalidConfiguration("The billing request must use the official Claude Console.")
        }
        let script = """
        if (location.origin !== 'https://platform.claude.com') throw new Error('Open the official Claude Console sign-in page.');
        const controller = new AbortController();
        const timeout = setTimeout(() => controller.abort(), 20000);
        try {
          const response = await fetch(path, {credentials: 'include', cache: 'no-store',
            headers: {'Accept': 'application/json', 'anthropic-client-platform': 'web_console'}, signal: controller.signal});
          return JSON.stringify({status: response.status, contentType: response.headers.get('content-type') || '',
            redirected: response.redirected, body: await response.text()});
        } finally { clearTimeout(timeout); }
        """
        let value = try await webView.callAsyncJavaScript(script, arguments: ["path": url.path], in: nil, contentWorld: .page)
        try Task.checkCancellation()
        guard let text = value as? String, let data = text.data(using: .utf8) else {
            throw UsageError.providerFailure("Claude Console returned an unreadable response.")
        }
        let response = try JSONDecoder().decode(BrowserResponse.self, from: data)
        if response.status == 403 || response.status == 503 {
            // Let the provider create its own device-binding and account-context headers.
            return try await responseFromOfficialPage(for: url)
        }
        if response.status == 401 || response.status == 403 || response.redirected || !response.contentType.lowercased().contains("json") {
            throw UsageError.authenticationRequired("Sign in on the official Claude Console page, then read credits again.")
        }
        guard (200..<300).contains(response.status) else {
            throw UsageError.providerFailure("Claude Console could not read credits (HTTP \(response.status)). Open Sign-In and try again.")
        }
        return Data(response.body.utf8)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if navigation === awaitedNavigation { completeNavigation() }
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if navigation === awaitedNavigation { completeNavigation(error: error) }
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if navigation === awaitedNavigation { completeNavigation(error: error) }
        if !isFetching { status.stringValue = "Could not load Claude Console: \(error.localizedDescription)" }
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.request.url?.scheme == "https" { webView.load(navigationAction.request) }
        return nil
    }
    func windowWillClose(_ notification: Notification) { if !isFetching && !isPaused { parkBrowser() } }

    private func completeNavigation(error: Error? = nil) {
        navigationTimer?.invalidate()
        navigationTimer = nil
        let waiter = navigationWaiter
        navigationWaiter = nil
        awaitedNavigation = nil
        if let error { waiter?.resume(throwing: error) } else { waiter?.resume() }
    }

    @objc private func navigationTimedOut(_ sender: Timer) {
        completeNavigation(error: UsageError.providerFailure("Claude Console did not load within 20 seconds. Open Sign-In and try again."))
        webView.stopLoading()
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        let error = UsageError.providerFailure("The Console browser stopped. Open Sign-In and try again.")
        completeNavigation(error: error)
        completeResponse(error: error)
        status.stringValue = error.localizedDescription
    }

    func pause() {
        isPaused = true
        refreshTask?.cancel()
        completeNavigation(error: CancellationError())
        completeResponse(error: CancellationError())
        webView.stopLoading()
    }

    func retire() {
        pause()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "ClaudeConsoleObservation")
        // Replacing the document cancels pending JavaScript without changing the saved login store.
        webView.loadHTMLString("", baseURL: nil)
        close()
    }

    private func responseFromOfficialPage(for url: URL) async throws -> Data {
        try Task.checkCancellation()
        status.stringValue = "Reading the official Console page. If you have several organizations, select the same organization on that page."
        return try await withCheckedThrowingContinuation { continuation in
            responseWaiter = (url.path, continuation)
            responseTimer = Timer.scheduledTimer(timeInterval: 20, target: self,
                                                selector: #selector(responseTimedOut(_:)), userInfo: nil, repeats: false)
            webView.load(URLRequest(url: billingURL, timeoutInterval: 20))
        }
    }

    @objc private func responseTimedOut(_ sender: Timer) {
        completeResponse(error: UsageError.authenticationRequired("The official Console page did not report credits for this organization. Sign in, select the organization on the provider page, then read credits again."))
    }

    private func completeResponse(data: Data? = nil, error: Error? = nil) {
        responseTimer?.invalidate()
        responseTimer = nil
        let waiter = responseWaiter
        responseWaiter = nil
        if let error { waiter?.continuation.resume(throwing: error) }
        else if let data { waiter?.continuation.resume(returning: data) }
    }

    fileprivate func receiveObservation(_ message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame,
              message.frameInfo.request.url?.host == "platform.claude.com",
              message.frameInfo.request.url?.scheme == "https",
              let text = message.body as? String, text.utf8.count <= 1_048_576,
              let data = text.data(using: .utf8) else { return }
        struct Observation: Decodable { let path: String; let body: String }
        guard let observation = try? JSONDecoder().decode(Observation.self, from: data),
              observation.path == responseWaiter?.path else { return }
        if observation.path != "/api/account" {
            let components = observation.path.split(separator: "/")
            guard components.count == 5, components[0] == "api", components[1] == "organizations",
                  UUID(uuidString: String(components[2])) != nil,
                  components[3] == "prepaid", components[4] == "credits" else { return }
        }
        completeResponse(data: Data(observation.body.utf8))
    }

    private static let observationScript = """
    (() => {
      if (location.origin !== 'https://platform.claude.com') return;
      const original = window.fetch;
      window.fetch = async function(...parameters) {
        const response = await original.apply(this, parameters);
        try {
          const input = parameters[0];
          const url = new URL(input instanceof Request ? input.url : String(input), location.href);
          const method = (parameters[1]?.method || (input instanceof Request ? input.method : 'GET')).toUpperCase();
          const permitted = url.origin === 'https://platform.claude.com' &&
            (url.pathname === '/api/account' || /^\\/api\\/organizations\\/[0-9a-f-]{36}\\/prepaid\\/credits$/i.test(url.pathname));
          if (method === 'GET' && permitted && response.ok && !response.redirected &&
              (response.headers.get('content-type') || '').includes('json')) {
            response.clone().text().then(body => {
              if (body.length <= 1048576) window.webkit.messageHandlers.ClaudeConsoleObservation
                .postMessage(JSON.stringify({path: url.pathname, body}));
            }).catch(() => {});
          }
        } catch (_) {}
        return response;
      };
    })();
    """

    private func parkBrowser() {
        webView.isHidden = true
        webView.stopLoading()
        // The authenticated JSON document has no application interface or ongoing visual animation.
        webView.load(URLRequest(url: ClaudeConsoleClient.accountURL))
    }

    @objc private func disconnect(_ sender: Any?) {
        guard !isFetching else { return }
        Task {
            do {
                try await model.setConsoleConnection(accountID: profile.id, organizationID: nil, expectedIdentity: profile.providerAccountID)
                await model.load()
                status.stringValue = "Automatic API credits disconnected. Saved manual balances are available again."
            } catch { status.stringValue = error.localizedDescription }
        }
    }
}
