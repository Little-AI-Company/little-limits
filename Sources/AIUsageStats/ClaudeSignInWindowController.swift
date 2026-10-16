import AppKit
import Network
import UsageCore

@MainActor
final class ClaudeSignInWindowController: NSWindowController, NSWindowDelegate {
    private let model: ApplicationModel
    private let existingProfileID: UUID?
    private let accountLabel: String
    /// Called with the connected account after a successful sign-in closes the sheet.
    var onConnected: ((UUID) -> Void)?
    private let status = InterfaceControls.label("Preparing sign-in…", size: 13)
    private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    private var request: ClaudeAuthorizationRequest?
    private var listener: ClaudeAuthorizationListener?
    private var signInTask: Task<Void, Never>?
    private var expiryTask: Task<Void, Never>?
    private var finished = false

    init(model: ApplicationModel, existingProfileID: UUID?, label: String) {
        self.model = model
        self.existingProfileID = existingProfileID
        accountLabel = label
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 260),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let heading = existingProfileID == nil ? "Add Claude Account" : "Reconnect \(label)"
        window.title = heading
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        cancelButton.target = self
        cancelButton.action = #selector(cancel(_:))
        cancelButton.keyEquivalent = "\u{1b}"
        let title = InterfaceControls.label(heading, size: 13, weight: .bold)
        title.lineBreakMode = .byTruncatingMiddle
        title.maximumNumberOfLines = 1
        let explanation = InterfaceControls.label("Sign-in opens claude.ai in your browser. API Credits use a separate Claude Platform sign-in at platform.claude.com.")
        let controls = InterfaceControls.stack([title, explanation, status, cancelButton], spacing: 16)
        controls.translatesAutoresizingMaskIntoConstraints = false
        if let root = window.contentView {
            root.addSubview(controls)
            NSLayoutConstraint.activate([
                controls.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
                controls.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
                controls.topAnchor.constraint(equalTo: root.topAnchor, constant: 24),
                controls.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -24),
                title.widthAnchor.constraint(equalTo: controls.widthAnchor),
                status.widthAnchor.constraint(equalTo: controls.widthAnchor),
                explanation.widthAnchor.constraint(equalTo: controls.widthAnchor)
            ])
        }
        window.initialFirstResponder = cancelButton
        window.recalculateKeyViewLoop()
    }

    required init?(coder: NSCoder) { nil }

    func presentSheet(in parent: NSWindow) {
        guard let window, parent.attachedSheet == nil else { return }
        parent.beginSheet(window) { [weak self] _ in self?.stop() }
        start()
    }

    func start() {
        guard signInTask == nil, !finished else { return }
        signInTask = Task { [weak self] in
            guard let self else { return }
            do {
                let request = try await model.prepareClaudeSignIn(existingProfileID: existingProfileID, label: accountLabel)
                self.request = request
                guard !Task.isCancelled, !finished else {
                    await model.cancelClaudeSignIn(id: request.id)
                    return
                }
                let listener = try ClaudeAuthorizationListener(request: request)
                self.listener = listener
                listener.onCallback = { [weak self] url in self?.complete(url) }
                listener.onFailure = { [weak self] message in self?.fail(message) }
                try await listener.start()
                guard !Task.isCancelled, !finished else { return }
                let duration = max(0, request.expiresAt.timeIntervalSinceNow)
                expiryTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(duration))
                    guard !Task.isCancelled else { return }
                    self?.fail("Sign-in expired. Choose Close, then try again.")
                }
                guard NSWorkspace.shared.open(request.authorizationURL) else {
                    fail("The browser could not be opened. Check your default browser, choose Close, then try again.")
                    return
                }
                status.stringValue = "Complete sign-in on Claude’s page in your browser. Waiting for confirmation…"
            } catch {
                guard !finished else { return }
                fail(error.localizedDescription)
            }
        }
    }

    private func complete(_ callbackURL: URL) {
        guard let request, !finished else { return }
        listener?.stop()
        listener = nil
        expiryTask?.cancel()
        status.stringValue = "Confirming the account and reading usage…"
        cancelButton.isEnabled = false
        signInTask = Task { [weak self] in
            guard let self else { return }
            do {
                let profile = try await model.completeClaudeSignIn(requestID: request.id, callbackURL: callbackURL)
                guard !finished else { return }
                finished = true
                self.request = nil
                // Success needs no confirmation: close the sheet and show the account, whose page states
                // whether usage was read.
                let parent = window?.sheetParent
                if let window, let parent { parent.endSheet(window); window.orderOut(nil) }
                NSApp.activate(ignoringOtherApps: true)
                parent?.makeKeyAndOrderFront(nil)
                onConnected?(profile.id)
            } catch {
                guard !finished else { return }
                fail(error.localizedDescription)
            }
        }
    }

    private func fail(_ message: String) {
        guard !finished else { return }
        finished = true
        listener?.stop()
        listener = nil
        expiryTask?.cancel()
        if let request {
            self.request = nil
            Task { [model] in await model.cancelClaudeSignIn(id: request.id) }
        }
        status.stringValue = message
        finish(title: "Close")
    }

    /// The single button becomes the Return default once there is nothing left to cancel.
    private func finish(title: String) {
        cancelButton.title = title
        cancelButton.keyEquivalent = "\r"
        cancelButton.isEnabled = true
        window?.makeFirstResponder(cancelButton)
    }

    func stop() {
        finished = true
        signInTask?.cancel()
        expiryTask?.cancel()
        listener?.stop()
        listener = nil
        if let request {
            self.request = nil
            Task { [model] in await model.cancelClaudeSignIn(id: request.id) }
        }
    }

    @objc private func cancel(_ sender: Any?) {
        stop()
        if let window, let parent = window.sheetParent {
            parent.endSheet(window)
            window.orderOut(sender)
        }
    }
    func windowWillClose(_ notification: Notification) { stop() }
}

/// Receives only the registered loopback redirect, without retaining request data.
@MainActor
private final class ClaudeAuthorizationListener {
    private let listener: NWListener
    private let expectedState: String
    private let redirectURL: URL
    private let networkQueue = DispatchQueue(label: "com.parkerrex.ai-usage-stats.claude-authorization")
    private var readyContinuation: CheckedContinuation<Void, Error>?
    private var startupTimeout: Task<Void, Never>?
    private var connections: [UUID: NWConnection] = [:]
    private var connectionTimeouts: [UUID: Task<Void, Never>] = [:]
    private var stopped = false
    private var accepted = false
    var onCallback: ((URL) -> Void)?
    var onFailure: ((String) -> Void)?

    init(request: ClaudeAuthorizationRequest) throws {
        guard request.redirectURL.absoluteString == "http://localhost:54545/callback",
              let state = URLComponents(url: request.authorizationURL, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "state" })?.value, !state.isEmpty else {
            throw UsageError.invalidConfiguration("Claude sign-in could not be prepared. Choose Close, then try again.")
        }
        expectedState = state
        redirectURL = request.redirectURL
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: 54545)
        parameters.allowLocalEndpointReuse = false
        listener = try NWListener(using: parameters)
    }

    func start() async throws {
        listener.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in self?.stateChanged(state) }
        }
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in
                guard let self else { connection.cancel(); return }
                self.receive(connection)
            }
        }
        try await withCheckedThrowingContinuation { continuation in
            readyContinuation = continuation
            listener.start(queue: networkQueue)
            startupTimeout = Task { [weak self] in
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled, let self, self.readyContinuation != nil else { return }
                self.readyContinuation?.resume(throwing: UsageError.providerFailure("The sign-in connection could not start. Finish or cancel the other sign-in, then try again."))
                self.readyContinuation = nil
                self.stop()
            }
        }
    }

    private func stateChanged(_ state: NWListener.State) {
        switch state {
        case .ready:
            startupTimeout?.cancel()
            readyContinuation?.resume()
            readyContinuation = nil
        case .failed:
            let message = "Claude sign-in could not receive the browser response. Port 54545 may be in use. Finish or cancel the other sign-in, then try again."
            if let continuation = readyContinuation {
                readyContinuation = nil
                continuation.resume(throwing: UsageError.providerFailure(message))
            } else if !stopped { onFailure?(message) }
            stop()
        default: break
        }
    }

    private func receive(_ connection: NWConnection) {
        guard !stopped, !accepted, connections.count < 8 else { connection.cancel(); return }
        let id = UUID()
        connections[id] = connection
        connection.start(queue: networkQueue)
        connectionTimeouts[id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            self?.closeConnection(id)
        }
        readHeaders(id, data: Data())
    }

    private func readHeaders(_ id: UUID, data: Data) {
        guard let connection = connections[id] else { return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8_192 - data.count) { [weak self] next, _, complete, error in
            Task { @MainActor in
                guard let self, self.connections[id] != nil else { return }
                var received = data
                if let next { received.append(next) }
                if received.range(of: Data("\r\n\r\n".utf8)) != nil {
                    self.processHeaders(id, data: received)
                } else if received.count >= 8_192 || complete || error != nil {
                    self.closeConnection(id)
                } else { self.readHeaders(id, data: received) }
            }
        }
    }

    private func processHeaders(_ id: UUID, data: Data) {
        guard let header = String(data: data, encoding: .utf8),
              let firstLine = header.components(separatedBy: "\r\n").first else {
            respond(id, status: "400 Bad Request", message: "Invalid request.")
            return
        }
        let fields = firstLine.split(separator: " ", omittingEmptySubsequences: false)
        guard fields.count == 3, fields[0] == "GET", fields[2] == "HTTP/1.1" || fields[2] == "HTTP/1.0",
              fields[1].hasPrefix("/"), !fields[1].hasPrefix("//"),
              let url = URL(string: "http://localhost:54545\(fields[1])"),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.path == redirectURL.path, components.fragment == nil,
              matchingState(in: components) else {
            respond(id, status: "400 Bad Request", message: "This response does not match the current sign-in. Return to Claude and try again.")
            return
        }
        guard !accepted else { closeConnection(id); return }
        accepted = true
        respond(id, status: "200 OK", message: "Sign-in response received. Return to Limits Left to check the connection.")
        onCallback?(url)
    }

    private func matchingState(in components: URLComponents) -> Bool {
        let items = components.queryItems ?? []
        let states = items.filter { $0.name == "state" }
        guard states.count <= 1 else { return false }
        if let state = states.first?.value { return state == expectedState }
        let codes = items.filter { $0.name == "code" }
        guard codes.count == 1, let code = codes.first?.value else { return false }
        let parts = code.split(separator: "#", omittingEmptySubsequences: false)
        return parts.count == 2 && parts[1] == expectedState
    }

    private func respond(_ id: UUID, status: String, message: String) {
        guard let connection = connections.removeValue(forKey: id) else { return }
        connectionTimeouts.removeValue(forKey: id)?.cancel()
        let body = Data(message.utf8)
        let header = "HTTP/1.1 \(status)\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: \(body.count)\r\nConnection: close\r\nCache-Control: no-store\r\nReferrer-Policy: no-referrer\r\n\r\n"
        connection.send(content: Data(header.utf8) + body, completion: .contentProcessed { _ in connection.cancel() })
        networkQueue.asyncAfter(deadline: .now() + 10) { connection.cancel() }
    }

    private func closeConnection(_ id: UUID) {
        connectionTimeouts.removeValue(forKey: id)?.cancel()
        connections.removeValue(forKey: id)?.cancel()
    }

    func stop() {
        stopped = true
        startupTimeout?.cancel()
        listener.cancel()
        readyContinuation?.resume(throwing: UsageError.providerFailure("Claude sign-in was cancelled."))
        readyContinuation = nil
        for id in Array(connections.keys) { closeConnection(id) }
    }
}
