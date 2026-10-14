import AppKit
import WebKit
import UsageCore

@MainActor
private final class ConsoleObservationHandler: NSObject, WKScriptMessageHandler {
    weak var owner: ClaudePlatformViewController?
    init(owner: ClaudePlatformViewController) { self.owner = owner }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        owner?.receiveObservation(message)
    }
}

@MainActor
final class ClaudePlatformViewController: NSViewController, WKNavigationDelegate, WKUIDelegate {
    private struct BrowserResponse: Decodable {
        let status: Int
        let contentType: String
        let body: String
        let redirected: Bool
    }

    private let profile: AccountProfile
    private let model: ApplicationModel
    private let webView: WKWebView
    private let status = InterfaceControls.label("")
    private let headingTitle = InterfaceControls.label("Connect API Credits", size: 17, weight: .semibold)
    private let instruction = InterfaceControls.label("", size: 12)
    private let accountContext = InterfaceControls.label("", size: 12)
    private var platformEmail: String?
    private var hasDiscoveredAccount = false
    private let organizationControls = NSStackView()
    private let connectionActions = NSPopUpButton(frame: .zero, pullsDown: true)
    private let reloadItem = NSMenuItem(title: "Reload Sign-in", action: #selector(showSignIn(_:)), keyEquivalent: "")
    private let detailsItem = NSMenuItem(title: "Connection Details…", action: #selector(showDetails(_:)), keyEquivalent: "")
    private let disconnectItem = NSMenuItem(title: "Disconnect", action: #selector(disconnect(_:)), keyEquivalent: "")
    private var statusDetail: String?
    private var needsSignIn = false
    private let organization = NSPopUpButton(frame: .zero, pullsDown: false)
    private let readButton = NSButton(title: "Continue", target: nil, action: nil)
    private var organizations: [ClaudeConsoleOrganization] = []
    private var isFetching = false
    private var navigationWaiter: CheckedContinuation<Void, Error>?
    private var awaitedNavigation: WKNavigation?
    private var navigationTimer: Timer?
    private var responseWaiter: (path: String, continuation: CheckedContinuation<Data, Error>)?
    private var responseTimer: Timer?
    private var refreshTask: Task<Void, Never>?
    private var isPaused = false
    private var isRetired = false
    var accountID: UUID { profile.id }
    var onBack: (() -> Void)?
    private var isPaneVisible = false
    private let billingURL = URL(string: "https://platform.claude.com/settings/billing")!

    init(profile: AccountProfile, model: ApplicationModel) {
        self.profile = profile
        self.model = model
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = WKWebsiteDataStore(forIdentifier: profile.id)
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init(nibName: nil, bundle: nil)
        configuration.userContentController.add(ConsoleObservationHandler(owner: self), name: "ClaudeConsoleObservation")
        configuration.userContentController.addUserScript(WKUserScript(source: Self.observationScript,
                                                                       injectionTime: .atDocumentStart,
                                                                       forMainFrameOnly: true))
        webView.navigationDelegate = self
        webView.uiDelegate = self
    }
    required init?(coder: NSCoder) { nil }

    override func loadView() {
        let root = NSView()
        view = root
        readButton.target = self
        readButton.action = #selector(readCredits(_:))
        organization.target = self
        organization.action = #selector(selectOrganization(_:))
        organization.setAccessibilityLabel("Claude Platform organization")
        organization.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        organization.widthAnchor.constraint(lessThanOrEqualToConstant: 340).isActive = true
        connectionActions.addItem(withTitle: "Connection")
        connectionActions.setAccessibilityLabel("Platform connection actions")
        connectionActions.menu?.autoenablesItems = false
        for item in [reloadItem, detailsItem, disconnectItem] {
            item.target = self
            connectionActions.menu?.addItem(item)
        }
        let back = NSButton(title: "Back", target: self, action: #selector(backToAccount(_:)))
        back.setAccessibilityLabel("Back to account overview")
        let heading = NSStackView(views: [back, headingTitle])
        heading.orientation = .horizontal
        heading.alignment = .firstBaseline
        heading.spacing = 16
        accountContext.lineBreakMode = .byTruncatingMiddle
        accountContext.maximumNumberOfLines = 2
        organizationControls.orientation = .horizontal
        organizationControls.alignment = .firstBaseline
        organizationControls.spacing = 8
        organizationControls.addArrangedSubview(InterfaceControls.label("Organization", size: 12))
        organizationControls.addArrangedSubview(organization)
        let controls = NSStackView(views: [organizationControls, readButton, connectionActions])
        controls.orientation = .horizontal
        controls.alignment = .firstBaseline
        controls.spacing = 12
        controls.detachesHiddenViews = true
        let chrome = InterfaceControls.stack([heading, accountContext, instruction, controls, status], spacing: 8)
        chrome.detachesHiddenViews = true
        for component in [chrome, webView] {
            component.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(component)
        }
        for label in [accountContext, instruction, status] {
            label.widthAnchor.constraint(equalTo: chrome.widthAnchor).isActive = true
        }
        NSLayoutConstraint.activate([
            chrome.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            chrome.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            chrome.topAnchor.constraint(equalTo: root.safeAreaLayoutGuide.topAnchor, constant: 16),
            webView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            webView.topAnchor.constraint(equalTo: chrome.bottomAnchor, constant: 12),
            webView.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])
        status.isHidden = status.stringValue.isEmpty
        updateControls()
    }

    private func updateControls() {
        let connectedOrganization = model.consoleConnections[profile.id]
        let connected = connectedOrganization != nil
        headingTitle.stringValue = connected ? "API Credits" : "Connect API Credits"
        let intendedAccount = "Claude account: \(InterfaceFormatting.accountIdentity(profile))"
        if hasDiscoveredAccount {
            var context = ["Claude Platform login: \(platformEmail ?? "Email unavailable")"]
            if platformEmail != InterfaceFormatting.accountEmail(profile) { context.append(intendedAccount) }
            accountContext.stringValue = context.joined(separator: "\n")
        } else { accountContext.stringValue = intendedAccount }
        accountContext.toolTip = accountContext.stringValue
        let discovered = !organizations.isEmpty && !needsSignIn
        instruction.stringValue = discovered
            ? "Choose the organization linked to this Claude account."
            : "Sign in to Claude Platform below, then choose Continue. Passkeys and security keys do not work here: if Google or Claude asks for one, choose Try another way and use your password or a code."
        organizationControls.isHidden = !discovered
        organization.isEnabled = discovered && !isFetching
        if !discovered { readButton.title = "Continue" }
        else if let connectedOrganization {
            readButton.title = selectedOrganizationID == connectedOrganization ? "Refresh Credits" : "Switch Organization"
        } else { readButton.title = "Connect" }
        readButton.isEnabled = !isFetching && (!discovered || selectedOrganizationID != nil)
        reloadItem.isEnabled = !isFetching
        disconnectItem.isHidden = !connected
        disconnectItem.isEnabled = connected && !isFetching
        detailsItem.isEnabled = statusDetail != nil
    }

    private func setStatus(_ message: String, detail: String? = nil) {
        status.stringValue = message
        status.isHidden = message.isEmpty
        statusDetail = detail
        status.toolTip = detail
        detailsItem.isEnabled = detail != nil
    }

    @objc private func selectOrganization(_ sender: Any?) { updateControls() }

    @objc private func showDetails(_ sender: Any?) {
        guard let statusDetail, let window = view.window else { return }
        let alert = NSAlert()
        alert.messageText = "API Credits Connection"
        alert.informativeText = statusDetail
        alert.addButton(withTitle: "Done")
        alert.beginSheetModal(for: window)
    }

    func presentPane() {
        guard !isRetired else { return }
        _ = view
        let wasVisible = isPaneVisible
        isPaneVisible = true
        isPaused = false
        webView.isHidden = false
        updateControls()
        if !isFetching, !wasVisible { webView.load(URLRequest(url: billingURL)) }
    }

    func hidePane(pauseRefresh: Bool = false) {
        isPaneVisible = false
        webView.isHidden = true
        guard !isRetired else { return }
        if pauseRefresh { pause(); parkBrowser() }
        else if !isFetching { parkBrowser() }
    }

    @objc private func backToAccount(_ sender: Any?) { onBack?() }

    func refreshInBackground() {
        guard model.consoleConnections[profile.id] != nil, !isFetching else { return }
        startFetch(isInteractive: false)
    }

    @objc private func readCredits(_ sender: Any?) { startFetch(isInteractive: true) }
    @objc private func showSignIn(_ sender: Any?) {
        guard !isFetching else { return }
        webView.isHidden = false
        webView.load(URLRequest(url: billingURL))
        needsSignIn = true
        hasDiscoveredAccount = false
        platformEmail = nil
        setStatus("")
        updateControls()
    }

    private func startFetch(isInteractive: Bool) {
        guard !isFetching else { return }
        isPaused = false
        isFetching = true
        updateControls()
        setStatus("Reading credits…")
        refreshTask = Task { [weak self] in
            guard let self else { return }
            defer {
                isFetching = false
                updateControls()
                refreshTask = nil
                if !isPaused, !isPaneVisible { parkBrowser() }
            }
            do {
                try await prepareBrowser()
                let account = try ClaudeConsoleAccount.decode(try await get(ClaudeConsoleClient.accountURL))
                needsSignIn = false
                hasDiscoveredAccount = true
                let email = account.email?.trimmingCharacters(in: .whitespacesAndNewlines)
                platformEmail = email?.isEmpty == false ? email : nil
                let previouslySelected = selectedOrganizationID
                organizations = account.organizations.filter { $0.capabilities.isEmpty || $0.capabilities.contains("api") || $0.capabilities.contains("api_individual") }
                guard !organizations.isEmpty else { throw UsageError.providerFailure("This Claude Platform login has no API organization.") }
                let connectedID = model.consoleConnections[profile.id]
                var selectedID = isInteractive ? (previouslySelected ?? connectedID) : connectedID
                configureOrganizations(selectedID: selectedID)
                if selectedID == nil, organizations.count == 1 { selectedID = organizations[0].id; organization.selectItem(at: 1) }
                guard let selectedID, organizations.contains(where: { $0.id == selectedID }) else {
                    if isInteractive {
                        setStatus("Select an organization to continue.")
                        return
                    }
                    throw UsageError.authenticationRequired("The saved Claude Platform login no longer has access to the connected organization. Choose Manage API Credits… on this account, then choose Connection → Reload Sign-in.")
                }
                let url = try ClaudeConsoleClient.balanceURL(organizationID: selectedID)
                let response = try await get(url)
                let observedAt = Date()
                try Task.checkCancellation()
                // Decode before saving the connection so malformed data cannot replace an existing connection.
                _ = try ClaudeConsoleBalance.decode(response, organizationID: selectedID)
                try await model.setConsoleConnection(accountID: profile.id, organizationID: selectedID, expectedIdentity: profile.providerAccountID)
                var linkStateData: Data?
                var invoicesData: Data?
                var monthlyErrors: [String] = []
                do { linkStateData = try await get(ClaudeConsoleClient.linkStateURL(organizationID: selectedID)) }
                catch {
                    try Task.checkCancellation()
                    monthlyErrors.append("Monthly plan details could not be read.")
                }
                do { invoicesData = try await get(ClaudeConsoleClient.invoicesURL(organizationID: selectedID)) }
                catch {
                    try Task.checkCancellation()
                    monthlyErrors.append("Monthly invoices could not be read.")
                }
                try await model.updateConsoleCredits(accountID: profile.id, organizationID: selectedID, responseData: response,
                                                     expectedIdentity: profile.providerAccountID, linkStateData: linkStateData,
                                                     invoicesData: invoicesData, observedAt: observedAt,
                                                     monthlyMetadataError: monthlyErrors.isEmpty ? nil : monthlyErrors.joined(separator: " "))
                let detail = "Read \(InterfaceFormatting.exactDate(observedAt)). Credits refresh every 5 minutes."
                    + (monthlyErrors.isEmpty ? "" : " " + monthlyErrors.joined(separator: " "))
                setStatus(monthlyErrors.isEmpty ? "Credits updated." : "Credits updated; monthly details need attention.", detail: detail)
                let intendedEmail = profile.providerEmail?.trimmingCharacters(in: .whitespacesAndNewlines)
                if isInteractive, isPaneVisible, monthlyErrors.isEmpty,
                   let platformEmail, !platformEmail.isEmpty, let intendedEmail, !intendedEmail.isEmpty,
                   platformEmail.caseInsensitiveCompare(intendedEmail) == .orderedSame { onBack?() }
            } catch {
                if Task.isCancelled || error is CancellationError { setStatus("Credit refresh paused."); return }
                let message = error.localizedDescription
                needsSignIn = if case .authenticationRequired = error as? UsageError { true } else { false }
                if needsSignIn { hasDiscoveredAccount = false; platformEmail = nil }
                setStatus(needsSignIn ? "Sign-in required." : "Could not read credits.", detail: message)
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
            awaitedNavigation = webView.load(URLRequest(url: isPaneVisible ? billingURL : ClaudeConsoleClient.accountURL, timeoutInterval: 20))
            navigationTimer = Timer.scheduledTimer(timeInterval: 20, target: self,
                                                  selector: #selector(navigationTimedOut(_:)), userInfo: nil, repeats: false)
        }
    }

    private func get(_ url: URL) async throws -> Data {
        try Task.checkCancellation()
        guard url.scheme == "https", url.host == "platform.claude.com", Self.isPermittedObservationPath(url.path),
              webView.url?.scheme == "https", webView.url?.host == "platform.claude.com" else {
            throw UsageError.invalidConfiguration("The billing request must use the official Claude Platform.")
        }
        let script = """
        if (location.origin !== 'https://platform.claude.com') throw new Error('Open the official Claude Platform sign-in page.');
        const controller = new AbortController();
        const timeout = setTimeout(() => controller.abort(), 20000);
        try {
          const response = await fetch(path, {method: 'GET', credentials: 'include', cache: 'no-store',
            headers: {'Accept': 'application/json', 'anthropic-client-platform': 'web_console'}, signal: controller.signal});
          return JSON.stringify({status: response.status, contentType: response.headers.get('content-type') || '',
            redirected: response.redirected, body: await response.text()});
        } finally { clearTimeout(timeout); }
        """
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let target = (components?.percentEncodedPath ?? url.path) + (components?.percentEncodedQuery.map { "?" + $0 } ?? "")
        let value = try await webView.callAsyncJavaScript(script, arguments: ["path": target], in: nil, contentWorld: .page)
        try Task.checkCancellation()
        guard let text = value as? String, let data = text.data(using: .utf8) else {
            throw UsageError.providerFailure("Claude Platform returned an unreadable response.")
        }
        let response = try JSONDecoder().decode(BrowserResponse.self, from: data)
        if response.status == 403 || response.status == 503 {
            // Let the provider create its own device-binding and account-context headers.
            return try await responseFromOfficialPage(for: url)
        }
        if response.status == 401 || response.status == 403 || response.redirected || !response.contentType.lowercased().contains("json") {
            throw UsageError.authenticationRequired("Sign in on the Claude Platform page below, then choose Continue.")
        }
        guard (200..<300).contains(response.status) else {
            throw UsageError.providerFailure("Claude Platform could not read credits (HTTP \(response.status)). Choose Connection → Reload Sign-in, then try again.")
        }
        guard response.body.utf8.count <= 1_048_576 else { throw UsageError.providerFailure("Claude Platform returned too much credit data.") }
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
        if !isFetching { setStatus("Could not load sign-in.", detail: error.localizedDescription) }
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.request.url?.scheme == "https" { webView.load(navigationAction.request) }
        return nil
    }

    private func completeNavigation(error: Error? = nil) {
        navigationTimer?.invalidate()
        navigationTimer = nil
        let waiter = navigationWaiter
        navigationWaiter = nil
        awaitedNavigation = nil
        if let error { waiter?.resume(throwing: error) } else { waiter?.resume() }
    }

    @objc private func navigationTimedOut(_ sender: Timer) {
        completeNavigation(error: UsageError.providerFailure("Claude Platform did not load within 20 seconds. Choose Connection → Reload Sign-in, then try again."))
        webView.stopLoading()
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        let error = UsageError.providerFailure("The Claude Platform page stopped. Choose Connection → Reload Sign-in, then try again.")
        completeNavigation(error: error)
        completeResponse(error: error)
        setStatus("Connection interrupted.", detail: error.localizedDescription)
    }

    func pause() {
        isPaused = true
        refreshTask?.cancel()
        completeNavigation(error: CancellationError())
        completeResponse(error: CancellationError())
        webView.stopLoading()
    }

    func retire() {
        isRetired = true
        pause()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "ClaudeConsoleObservation")
        // Replacing the document cancels pending JavaScript without changing the saved login store.
        webView.loadHTMLString("", baseURL: nil)
        if isViewLoaded { view.removeFromSuperview() }
    }

    private func responseFromOfficialPage(for url: URL) async throws -> Data {
        try Task.checkCancellation()
        setStatus("Reading the Claude Platform billing page…", detail: "If you have several organizations, select the same organization on the Claude Platform page.")
        return try await withCheckedThrowingContinuation { continuation in
            responseWaiter = (url.path, continuation)
            responseTimer = Timer.scheduledTimer(timeInterval: 20, target: self,
                                                selector: #selector(responseTimedOut(_:)), userInfo: nil, repeats: false)
            webView.load(URLRequest(url: billingURL, timeoutInterval: 20))
        }
    }

    @objc private func responseTimedOut(_ sender: Timer) {
        completeResponse(error: UsageError.authenticationRequired("Claude Platform did not report credits for this organization. Sign in, select the organization on the Claude Platform page, then choose Continue."))
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
        guard Self.isPermittedObservationPath(observation.path) else { return }
        completeResponse(data: Data(observation.body.utf8))
    }

    private static func isPermittedObservationPath(_ path: String) -> Bool {
        if path == "/api/account" { return true }
        let components = path.split(separator: "/")
        if components.count == 5, components[0] == "api", components[1] == "organizations",
           UUID(uuidString: String(components[2])) != nil, components[3] == "prepaid", components[4] == "credits" { return true }
        if components.count == 4, components[0] == "api", components[1] == "organizations",
           UUID(uuidString: String(components[2])) != nil, components[3] == "invoices" { return true }
        return components.count == 5 && components[0] == "api" && components[1] == "quirky-lollipop"
            && components[2] == "organizations" && UUID(uuidString: String(components[3])) != nil && components[4] == "link-state"
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
            (url.pathname === '/api/account' || /^\\/api\\/organizations\\/[0-9a-f-]{36}\\/(prepaid\\/credits|invoices)$/i.test(url.pathname) ||
             /^\\/api\\/quirky-lollipop\\/organizations\\/[0-9a-f-]{36}\\/link-state$/i.test(url.pathname));
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
        disconnectConnection()
    }

    func disconnectConnection() {
        guard !isRetired, !model.isDemo, !model.isRefreshing, !model.isChangingAccounts,
              model.consoleConnections[profile.id] != nil else { return }
        guard !isFetching else {
            model.onError?("API Credits are refreshing. Choose Disconnect API Credits again after the refresh finishes.")
            return
        }
        isFetching = true
        updateControls()
        Task {
            defer {
                isFetching = false
                updateControls()
            }
            do {
                try await model.setConsoleConnection(accountID: profile.id, organizationID: nil, expectedIdentity: profile.providerAccountID)
                await model.load()
                setStatus("API Credits disconnected.", detail: "Saved manual balances are available again.")
                updateControls()
            } catch {
                setStatus("Could not disconnect.", detail: error.localizedDescription)
                model.onError?(error.localizedDescription)
            }
        }
    }
}
