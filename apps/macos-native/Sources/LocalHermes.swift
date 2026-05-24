import Foundation
import Security
import Darwin

private let localHermesDisplayPort = 8642

struct LocalHermesProbe: Equatable {
    var isProcessRunning: Bool
    var isReachable: Bool
    var connectionKind: String
    var host: String
    var port: Int
    var endpoint: String
    var model: String
    var capabilities: [String]
    var statusText: String
}

@MainActor
final class LocalHermesManager: ObservableObject {
    @Published var probe = LocalHermesProbe(
        isProcessRunning: false,
        isReachable: false,
        connectionKind: "tui_gateway",
        host: "127.0.0.1",
        port: localHermesDisplayPort,
        endpoint: "stdio://tui_gateway.entry",
        model: "hermes",
        capabilities: ["local_hermes_gateway", "tui_gateway"],
        statusText: "Not tested"
    )

    private var connector: LocalHermesConnector?

    func discover() async {
        let install = findHermesInstall()
        let running = await isGatewayProcessRunning()
        let result = await testTuiGateway()
        probe = LocalHermesProbe(
            isProcessRunning: running,
            isReachable: result.ok,
            connectionKind: "tui_gateway",
            host: "127.0.0.1",
            port: localHermesDisplayPort,
            endpoint: "stdio://tui_gateway.entry",
            model: result.model ?? "hermes",
            capabilities: [
                "local_hermes_gateway",
                "tui_gateway",
                "gateway_endpoint:stdio://tui_gateway.entry",
                "hermes_root:\(install.root.path)",
                "hermes_python:\(install.python.path)"
            ],
            statusText: result.ok
                ? "Connected through Hermes TUI Gateway"
                : tuiGatewayUnavailableStatus(running: running, error: result.error)
        )
    }

    func test(host: String, port: Int?) async -> Bool {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedHost == "127.0.0.1",
           port == localHermesDisplayPort,
           probe.connectionKind == "tui_gateway" {
            let result = await testTuiGateway()
            probe.statusText = result.ok
                ? "Connected through Hermes TUI Gateway"
                : tuiGatewayUnavailableStatus(running: await isGatewayProcessRunning(), error: result.error)
            probe.isReachable = result.ok
            return result.ok
        }
        if !trimmedHost.isEmpty, let port, port > 0 {
            return await testHTTPGateway(baseURL: "http://\(trimmedHost):\(port)")
        }
        let result = await testTuiGateway()
        probe.statusText = result.ok
            ? "Connected through Hermes TUI Gateway"
            : tuiGatewayUnavailableStatus(running: await isGatewayProcessRunning(), error: result.error)
        return result.ok
    }

    func discoverSlashCommands() async -> [SlashCommand] {
        await withCheckedContinuation { continuation in
            let gateway = HermesTuiGatewayProcess()
            gateway.start { ready in
                guard ready else {
                    gateway.stop()
                    continuation.resume(returning: SlashCommand.fallbacks)
                    return
                }
                gateway.request(method: "commands.catalog", params: [:]) { response in
                    let commands = parseSlashCommandResponse(response)
                    gateway.stop()
                    continuation.resume(returning: commands.isEmpty ? SlashCommand.fallbacks : commands)
                }
            }
        }
    }

    func startConnectorIfNeeded(store: DeckStore) {
        if connector == nil {
            connector = LocalHermesConnector(store: store)
            connector?.connect()
        } else {
            connector?.sendHelloForLocalAgents()
        }
    }

    func saveAPIKey(_ apiKey: String, for agentId: String) {
        LocalSecretStore.save(apiKey, account: agentId)
    }

    func deleteAPIKey(for agentId: String) {
        LocalSecretStore.delete(account: agentId)
    }

    private func tuiGatewayUnavailableStatus(running: Bool, error: String?) -> String {
        if !running {
            return "Hermes Gateway process is not running"
        }
        return error ?? "Hermes TUI Gateway is not reachable"
    }

    private func findHermesInstall() -> (root: URL, python: URL) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let root = home.appending(path: ".hermes/hermes-agent", directoryHint: .isDirectory)
        let venvPython = root.appending(path: "venv/bin/python")
        if FileManager.default.isExecutableFile(atPath: venvPython.path) {
            return (root, venvPython)
        }
        return (root, URL(fileURLWithPath: "/usr/bin/python3"))
    }

    private func testTuiGateway() async -> (ok: Bool, model: String?, error: String?) {
        await withCheckedContinuation { continuation in
            let gateway = HermesTuiGatewayProcess()
            gateway.start { ready in
                guard ready else {
                    gateway.stop()
                    continuation.resume(returning: (false, nil, gateway.lastError ?? "Hermes TUI Gateway did not start"))
                    return
                }
                gateway.request(method: "setup.status", params: [:]) { setup in
                    if setup == nil {
                        let error = gateway.lastError ?? "Hermes setup status is unavailable"
                        gateway.stop()
                        continuation.resume(returning: (false, nil, error))
                        return
                    }
                    gateway.request(method: "config.get", params: ["key": "provider"]) { provider in
                        let model = ((provider?["model"] as? String)?.isEmpty == false)
                            ? provider?["model"] as? String
                            : "hermes"
                        gateway.stop()
                        continuation.resume(returning: (true, model, nil))
                    }
                }
            }
        }
    }

    private func testHTTPGateway(baseURL: String) async -> Bool {
        for suffix in ["/health", "/v1/models"] {
            guard let url = URL(string: baseURL.trimmedSlash + suffix) else { continue }
            var request = URLRequest(url: url)
            request.timeoutInterval = 2
            if let (_, response) = try? await URLSession.shared.data(for: request),
               let http = response as? HTTPURLResponse,
               (200..<500).contains(http.statusCode) {
                probe.statusText = "Connected to Hermes HTTP endpoint"
                return true
            }
        }
        probe.statusText = "Cannot reach Hermes at \(baseURL)"
        return false
    }

    private func isGatewayProcessRunning() async -> Bool {
        let stateURL = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".hermes/gateway_state.json")
        guard let data = try? Data(contentsOf: stateURL),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              payload["gateway_state"] as? String == "running",
              let pid = payload["pid"] as? Int32 else {
            return false
        }
        return kill(pid, 0) == 0
    }
}

@MainActor
final class LocalHermesConnector {
    private weak var store: DeckStore?
    private var task: URLSessionWebSocketTask?
    private var heartbeat: Timer?
    private var helloRetry: Timer?
    private var runners: [String: HermesTuiRunner] = [:]

    init(store: DeckStore) {
        self.store = store
    }

    func connect() {
        guard let store else { return }
        let agentURL = URL(string: store.client.baseURL.absoluteString.replacingOccurrences(of: "http", with: "ws") + "/ws/agent")!
        var request = URLRequest(url: agentURL)
        request.setValue("Bearer dev-agent-secret", forHTTPHeaderField: "authorization")
        let task = URLSession.shared.webSocketTask(with: request)
        self.task = task
        task.resume()
        scheduleHelloRetry()
        heartbeat?.invalidate()
        heartbeat = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.sendHeartbeatForLocalAgents()
            }
        }
        receive()
    }

    func sendHelloForLocalAgents() {
        guard let store else { return }
        for agent in store.agents where agent.isLocalHermes {
            send(["type": "agent.hello", "agent_id": agent.id])
        }
    }

    private func scheduleHelloRetry() {
        helloRetry?.invalidate()
        sendHelloForLocalAgents()
        helloRetry = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self else { return }
                self.sendHelloForLocalAgents()
                if self.store?.agents.contains(where: { $0.isLocalHermes && $0.status == "online" }) == true {
                    self.helloRetry?.invalidate()
                    self.helloRetry = nil
                }
            }
        }
    }

    private func sendHeartbeatForLocalAgents() {
        guard let store else { return }
        for agent in store.agents where agent.isLocalHermes {
            send(["type": "agent.heartbeat", "agent_id": agent.id])
        }
    }

    private func receive() {
        task?.receive { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                if case let .success(.string(text)) = result {
                    Task {
                        await self.handle(text)
                    }
                } else if case .failure = result {
                    self.connect()
                    return
                }
                self.receive()
            }
        }
    }

    private func handle(_ text: String) async {
        guard let data = text.data(using: .utf8),
              let event = try? JSONDecoder().decode(DispatchEvent.self, from: data),
              event.type == "message.dispatch" else { return }
        await runHermes(event)
    }

    private func runHermes(_ event: DispatchEvent) async {
        let agent = store?.agents.first { $0.id == event.agent_id }
        if let url = agent?.httpGatewayURL, !url.isEmpty {
            await runHTTPHermes(event, baseURL: url)
            return
        }
        let runner = runners[event.agent_id] ?? HermesTuiRunner()
        runners[event.agent_id] = runner
        do {
            let content = try await runner.submit(
                event.content,
                onDelta: { [weak self] delta in
                    self?.send([
                        "type": "agent.response.delta",
                        "channel_id": event.channel_id,
                        "request_message_id": event.message_id,
                        "response_message_id": event.response_message_id,
                        "agent_id": event.agent_id,
                        "delta": delta
                    ])
                },
                onActivity: { [weak self] activity in
                    self?.send([
                        "type": "agent.activity",
                        "channel_id": event.channel_id,
                        "request_message_id": event.message_id,
                        "response_message_id": event.response_message_id,
                        "agent_id": event.agent_id,
                        "activity_kind": activity.kind,
                        "phase": activity.phase,
                        "text": activity.text,
                        "tool_name": activity.toolName ?? ""
                    ])
                }
            )
            send([
                "type": "agent.response.completed",
                "channel_id": event.channel_id,
                "request_message_id": event.message_id,
                "response_message_id": event.response_message_id,
                "agent_id": event.agent_id,
                "content": content
            ])
        } catch {
            sendError(event, error.localizedDescription)
        }
    }

    private func runHTTPHermes(_ event: DispatchEvent, baseURL: String) async {
        guard let url = URL(string: baseURL.trimmedSlash + "/v1/chat/completions") else {
            sendError(event, "Invalid Hermes HTTP endpoint")
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.timeoutInterval = 180
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "model": "hermes",
            "stream": false,
            "messages": [["role": "user", "content": event.content]]
        ])
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                sendError(event, String(data: data, encoding: .utf8) ?? "Hermes HTTP endpoint returned an error")
                return
            }
            let content = extractHTTPContent(from: data)
            send([
                "type": "agent.response.delta",
                "channel_id": event.channel_id,
                "request_message_id": event.message_id,
                "response_message_id": event.response_message_id,
                "agent_id": event.agent_id,
                "delta": content
            ])
            send([
                "type": "agent.response.completed",
                "channel_id": event.channel_id,
                "request_message_id": event.message_id,
                "response_message_id": event.response_message_id,
                "agent_id": event.agent_id,
                "content": content
            ])
        } catch {
            sendError(event, "Cannot reach Hermes HTTP endpoint at \(baseURL)")
        }
    }

    private func extractHTTPContent(from data: Data) -> String {
        guard let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = payload["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any] else {
            return String(data: data, encoding: .utf8) ?? ""
        }
        if let content = message["content"] as? String {
            return content
        }
        if let parts = message["content"] as? [[String: Any]] {
            return parts.compactMap { $0["text"] as? String }.joined()
        }
        return ""
    }

    private func sendError(_ event: DispatchEvent, _ error: String) {
        send([
            "type": "agent.error",
            "channel_id": event.channel_id,
            "request_message_id": event.message_id,
            "agent_id": event.agent_id,
            "error": error
        ])
    }

    private func send(_ payload: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8) else { return }
        task?.send(.string(text)) { _ in }
    }
}

@MainActor
final class HermesTuiRunner: @unchecked Sendable {
    private var gateway: HermesTuiGatewayProcess?
    private var sessionId: String?
    private var finalContinuation: CheckedContinuation<String, Error>?
    private var collected = ""
    private var onDelta: ((String) -> Void)?
    private var onActivity: ((HermesActivity) -> Void)?

    func submit(_ text: String, onDelta: @escaping (String) -> Void, onActivity: @escaping (HermesActivity) -> Void) async throws -> String {
        try await ensureReady()
        guard let gateway, let sessionId else {
            throw LocalHermesError("Hermes TUI Gateway is not ready")
        }
        self.collected = ""
        self.onDelta = onDelta
        self.onActivity = onActivity
        return try await withCheckedThrowingContinuation { continuation in
            self.finalContinuation = continuation
            gateway.request(method: "prompt.submit", params: ["session_id": sessionId, "text": text]) { response in
                guard response != nil else {
                    self.finish(error: self.gateway?.lastError ?? "Hermes did not accept the message")
                    return
                }
            }
        }
    }

    private func ensureReady() async throws {
        if gateway != nil, sessionId != nil {
            return
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let gateway = HermesTuiGatewayProcess()
            self.gateway = gateway
            gateway.onEvent = { [weak self] event in
                self?.handle(event)
            }
            gateway.start { ready in
                guard ready else {
                    let error = gateway.lastError ?? "Hermes TUI Gateway did not start"
                    gateway.stop()
                    Task { @MainActor in
                        self.gateway = nil
                        continuation.resume(throwing: LocalHermesError(error))
                    }
                    return
                }
                gateway.request(method: "session.create", params: ["cols": 100]) { response in
                    guard let sid = response?["session_id"] as? String else {
                        let error = gateway.lastError ?? "Hermes session could not be created"
                        gateway.stop()
                        Task { @MainActor in
                            self.gateway = nil
                            continuation.resume(throwing: LocalHermesError(error))
                        }
                        return
                    }
                    Task { @MainActor in
                        self.sessionId = sid
                        continuation.resume()
                    }
                }
            }
        }
    }

    private func handle(_ event: [String: Any]) {
        guard let type = event["type"] as? String else { return }
        if type == "message.delta",
           let payload = event["payload"] as? [String: Any],
           let text = payload["text"] as? String,
           !text.isEmpty {
            collected += text
            onDelta?(text)
        } else if type == "message.start" {
            onActivity?(HermesActivity(kind: "typing", phase: "started", text: "输入中...", toolName: nil))
        } else if type == "status.update",
                  let payload = event["payload"] as? [String: Any],
                  let text = payload["text"] as? String,
                  !text.isEmpty {
            onActivity?(HermesActivity(kind: "status", phase: "progress", text: text, toolName: nil))
        } else if type == "thinking.delta",
                  let payload = event["payload"] as? [String: Any],
                  let text = payload["text"] as? String,
                  !text.isEmpty {
            onActivity?(HermesActivity(kind: "status", phase: "progress", text: text, toolName: nil))
        } else if type == "tool.start",
                  let payload = event["payload"] as? [String: Any] {
            let name = payload["name"] as? String ?? "tool"
            let context = payload["context"] as? String ?? ""
            onActivity?(HermesActivity(kind: "tool", phase: "started", text: context.isEmpty ? "调用工具 \(name)" : context, toolName: name))
        } else if type == "tool.progress",
                  let payload = event["payload"] as? [String: Any] {
            let name = payload["name"] as? String ?? "tool"
            let preview = payload["preview"] as? String ?? "工具运行中"
            onActivity?(HermesActivity(kind: "tool", phase: "progress", text: preview, toolName: name))
        } else if type == "tool.complete",
                  let payload = event["payload"] as? [String: Any] {
            let name = payload["name"] as? String ?? "tool"
            let summary = payload["summary"] as? String ?? "工具调用完成"
            onActivity?(HermesActivity(kind: "tool", phase: "completed", text: summary, toolName: name))
        } else if type == "message.complete",
                  let payload = event["payload"] as? [String: Any] {
            let text = (payload["text"] as? String) ?? collected
            onActivity?(HermesActivity(kind: "typing", phase: "cleared", text: "", toolName: nil))
            finish(value: text)
        } else if type == "error",
                  let payload = event["payload"] as? [String: Any] {
            onActivity?(HermesActivity(kind: "typing", phase: "cleared", text: "", toolName: nil))
            finish(error: payload["message"] as? String ?? "Hermes returned an error")
        }
    }

    private func finish(value: String) {
        let continuation = finalContinuation
        finalContinuation = nil
        onDelta = nil
        onActivity = nil
        continuation?.resume(returning: value)
    }

    private func finish(error: String) {
        let continuation = finalContinuation
        finalContinuation = nil
        onDelta = nil
        onActivity = nil
        continuation?.resume(throwing: LocalHermesError(error))
    }
}

struct HermesActivity {
    let kind: String
    let phase: String
    let text: String
    let toolName: String?
}

private func parseSlashCommandResponse(_ response: [String: Any]?) -> [SlashCommand] {
    guard let response else { return [] }
    if let categories = response["categories"] as? [[String: Any]] {
        return categories.flatMap { category in
            let categoryName = category["name"] as? String ?? "Hermes"
            let pairs = category["pairs"] as? [[Any]] ?? []
            return pairs.compactMap { pair -> SlashCommand? in
                guard let rawName = pair.first as? String else { return nil }
                let description = pair.dropFirst().first as? String ?? ""
                return SlashCommand(name: rawName, description: description, category: categoryName)
            }
        }
    }
    let pairs = response["pairs"] as? [[Any]] ?? []
    return pairs.compactMap { pair in
        guard let rawName = pair.first as? String else { return nil }
        return SlashCommand(name: rawName, description: pair.dropFirst().first as? String ?? "", category: "Hermes")
    }
}

final class HermesTuiGatewayProcess: @unchecked Sendable {
    var onEvent: (([String: Any]) -> Void)?
    private(set) var lastError: String?

    private let process = Process()
    private let stdin = Pipe()
    private let stdout = Pipe()
    private let stderr = Pipe()
    private var pending: [String: ([String: Any]?) -> Void] = [:]
    private var pendingTimeouts: [String: DispatchWorkItem] = [:]
    private var readyHandler: (((Bool) -> Void))?
    private var readyTimeout: DispatchWorkItem?
    private var nextId = 0
    private var isRunning = false
    private var stdoutBuffer = ""

    func start(_ completion: @escaping @Sendable (Bool) -> Void) {
        let install = findInstall()
        readyHandler = completion
        let readyTimeout = DispatchWorkItem { [weak self] in
            guard let self, self.readyHandler != nil else { return }
            self.lastError = self.lastError ?? "Hermes TUI Gateway startup timed out"
            self.finishReady(false)
        }
        self.readyTimeout = readyTimeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 12, execute: readyTimeout)

        process.executableURL = install.python
        process.arguments = ["-m", "tui_gateway.entry"]
        process.currentDirectoryURL = install.root
        var env = ProcessInfo.processInfo.environment
        env["PYTHONPATH"] = install.root.path
        env["HERMES_PYTHON_SRC_ROOT"] = install.root.path
        process.environment = env
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.readStdout(handle.availableData, ready: completion)
        }
        stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let text = String(data: handle.availableData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let text, !text.isEmpty {
                self?.lastError = text
            }
        }
        process.terminationHandler = { [weak self] _ in
            self?.isRunning = false
        }
        do {
            try process.run()
            isRunning = true
        } catch {
            lastError = error.localizedDescription
            finishReady(false)
        }
    }

    func request(method: String, params: [String: Any], timeout: TimeInterval = 12, completion: @escaping ([String: Any]?) -> Void) {
        guard isRunning else {
            completion(nil)
            return
        }
        nextId += 1
        let id = "deck-\(nextId)"
        pending[id] = completion
        let timeoutItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let callback = self.pending.removeValue(forKey: id)
            self.pendingTimeouts.removeValue(forKey: id)
            self.lastError = "Hermes request timed out: \(method)"
            callback?(nil)
        }
        pendingTimeouts[id] = timeoutItem
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: timeoutItem)
        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "method": method,
            "params": params
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              var line = String(data: data, encoding: .utf8) else {
            pending.removeValue(forKey: id)
            pendingTimeouts.removeValue(forKey: id)?.cancel()
            completion(nil)
            return
        }
        line.append("\n")
        stdin.fileHandleForWriting.write(Data(line.utf8))
    }

    func stop() {
        stdout.fileHandleForReading.readabilityHandler = nil
        stderr.fileHandleForReading.readabilityHandler = nil
        readyTimeout?.cancel()
        for timeout in pendingTimeouts.values {
            timeout.cancel()
        }
        pendingTimeouts.removeAll()
        pending.removeAll()
        if process.isRunning {
            process.terminate()
        }
        isRunning = false
    }

    private func readStdout(_ data: Data, ready: @escaping @Sendable (Bool) -> Void) {
        guard !data.isEmpty,
              let text = String(data: data, encoding: .utf8) else { return }
        stdoutBuffer += text
        while let newline = stdoutBuffer.firstIndex(of: "\n") {
            let rawLine = String(stdoutBuffer[..<newline])
            stdoutBuffer.removeSubrange(...newline)
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty,
                  let payload = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { continue }
            if let id = payload["id"] as? String {
                let completion = pending.removeValue(forKey: id)
                pendingTimeouts.removeValue(forKey: id)?.cancel()
                completion?(payload["result"] as? [String: Any])
                continue
            }
            if payload["method"] as? String == "event",
               let params = payload["params"] as? [String: Any] {
                if params["type"] as? String == "gateway.ready" {
                    finishReady(true)
                }
                onEvent?(params)
            }
        }
    }

    private func finishReady(_ ok: Bool) {
        let handler = readyHandler
        readyHandler = nil
        readyTimeout?.cancel()
        readyTimeout = nil
        handler?(ok)
    }

    private func findInstall() -> (root: URL, python: URL) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let root = home.appending(path: ".hermes/hermes-agent", directoryHint: .isDirectory)
        let venvPython = root.appending(path: "venv/bin/python")
        if FileManager.default.isExecutableFile(atPath: venvPython.path) {
            return (root, venvPython)
        }
        return (root, URL(fileURLWithPath: "/usr/bin/python3"))
    }
}

struct LocalHermesError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? {
        message
    }
}

private struct DispatchEvent: Decodable {
    let type: String
    let channel_id: String
    let message_id: String
    let response_message_id: String
    let agent_id: String
    let content: String
}

enum LocalSecretStore {
    private static let service = "HermesDeckLocalHermesAPIKey"

    static func save(_ value: String, account: String) {
        delete(account: account)
        guard !value.isEmpty, let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

private extension String {
    var trimmedSlash: String {
        trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "/+$", with: "", options: .regularExpression)
    }
}
