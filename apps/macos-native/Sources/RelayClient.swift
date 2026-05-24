import Foundation

final class RelayClient: @unchecked Sendable {
    let baseURL: URL
    let wsURL: URL
    private let jsonDecoder = JSONDecoder()

    init(baseURL: URL = URL(string: "http://127.0.0.1:8787")!) {
        self.baseURL = baseURL
        self.wsURL = URL(string: baseURL.absoluteString.replacingOccurrences(of: "http", with: "ws") + "/ws/client")!
    }

    func login(email: String, password: String) async throws -> LoginResponse {
        return try await request(
            path: "/api/auth/login",
            method: "POST",
            token: nil,
            body: ["email": email, "password": password]
        )
    }

    func agents(token: String) async throws -> [Agent] {
        try await request(path: "/api/agents", method: "GET", token: token)
    }

    func channels(token: String) async throws -> [Channel] {
        try await request(path: "/api/channels", method: "GET", token: token)
    }

    func messages(token: String, channelId: String, limit: Int = 80, before: String? = nil) async throws -> [Message] {
        var path = "/api/channels/\(channelId)/messages?limit=\(limit)"
        if let before {
            path += "&before=\(before.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? before)"
        }
        return try await request(path: path, method: "GET", token: token)
    }

    func createChannel(token: String, name: String, members: [String], routingMode: String) async throws -> Channel {
        return try await request(
            path: "/api/channels",
            method: "POST",
            token: token,
            body: ["name": name, "members": members, "routing_mode": routingMode]
        )
    }

    func createAgent(
        token: String,
        id: String,
        name: String,
        hostLabel: String,
        deviceType: String,
        capabilities: [String],
        defaultModel: String?,
        defaultProvider: String?,
        directConfig: [String: String] = [:]
    ) async throws -> Agent {
        var body: [String: Any] = [
            "id": id,
            "name": name,
            "device_type": deviceType,
            "host_label": hostLabel,
            "capabilities": capabilities
        ]
        if !directConfig.isEmpty {
            body["direct_config"] = directConfig
        }
        if let defaultModel {
            body["default_model"] = defaultModel
        }
        if let defaultProvider {
            body["default_provider"] = defaultProvider
        }
        return try await request(
            path: "/api/agents",
            method: "POST",
            token: token,
            body: body
        )
    }

    func deleteAgent(token: String, agentId: String) async throws {
        let _: DeleteResponse = try await request(
            path: "/api/agents/\(agentId)",
            method: "DELETE",
            token: token
        )
    }

    func updateChannel(
        token: String,
        channelId: String,
        name: String,
        routingMode: String,
        members: [String],
        icon: String,
        avatarPath: String? = nil
    ) async throws -> Channel {
        var config = ["icon": icon]
        if let avatarPath {
            config["avatar_path"] = avatarPath
        }
        return try await request(
            path: "/api/channels/\(channelId)",
            method: "PATCH",
            token: token,
            body: [
                "name": name,
                "routing_mode": routingMode,
                "members": members,
                "config": config
            ]
        )
    }

    func sendMessage(token: String, channelId: String, content: String, targetAgents: [String]?) async throws -> Message {
        var body: [String: Any] = ["content": content, "content_type": "markdown"]
        if let targetAgents {
            body["target_agents"] = targetAgents
        }
        return try await request(
            path: "/api/channels/\(channelId)/messages",
            method: "POST",
            token: token,
            body: body
        )
    }

    func archiveChannel(token: String, channelId: String) async throws {
        let _: Channel = try await request(
            path: "/api/channels/\(channelId)",
            method: "PATCH",
            token: token,
            body: ["archived": true]
        )
    }

    private func request<T: Decodable>(
        path: String,
        method: String,
        token: String?,
        body: [String: Any]? = nil
    ) async throws -> T {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try jsonDecoder.decode(T.self, from: data)
    }
}
