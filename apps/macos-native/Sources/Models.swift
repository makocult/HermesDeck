import Foundation

struct LoginResponse: Decodable {
    let token: String
}

struct DeleteResponse: Decodable {
    let ok: Bool
}

struct Agent: Identifiable, Decodable, Hashable {
    let id: String
    let name: String
    let device_type: String
    let host_label: String?
    let status: String
    let capabilities: [String]
    let default_model: String?
    let default_provider: String?

    var httpGatewayURL: String? {
        capabilities.first { $0.hasPrefix("gateway_url:") }?.replacingOccurrences(of: "gateway_url:", with: "")
    }

    var isLocalHermes: Bool {
        capabilities.contains("local_hermes_gateway")
    }
}

struct Channel: Identifiable, Decodable, Hashable {
    let id: String
    let name: String
    let type: String
    let routing_mode: String
    let config: [String: String]?
    let members: [Agent]

    var icon: String {
        if let configured = config?["icon"], !configured.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return configured
        }
        if type == "direct" {
            return String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1)).uppercased()
        }
        return "#"
    }

    var avatarPath: String? {
        guard let path = config?["avatar_path"], !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return path
    }
}

struct MessageTarget: Decodable, Hashable {
    let agent_id: String
    let status: String
    let error: String?
}

struct Message: Identifiable, Decodable, Hashable {
    let id: String
    let channel_id: String
    let sender_type: String
    let sender_id: String
    let content_type: String
    let content: String
    let status: String
    let created_at: String
    let targets: [MessageTarget]
}

enum ClientEvent: Decodable {
    case messageCreated(channelId: String, message: Message)
    case messageUpdated(channelId: String, message: Message)
    case responseDelta(channelId: String, messageId: String, agentId: String, delta: String)
    case agentStatusChanged(agentId: String, status: String)
    case channelUpdated(Channel)
    case ignored

    private enum CodingKeys: String, CodingKey {
        case type
        case channel_id
        case message
        case message_id
        case agent_id
        case status
        case delta
        case channel
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "message.created":
            self = .messageCreated(
                channelId: try container.decode(String.self, forKey: .channel_id),
                message: try container.decode(Message.self, forKey: .message)
            )
        case "message.updated":
            self = .messageUpdated(
                channelId: try container.decode(String.self, forKey: .channel_id),
                message: try container.decode(Message.self, forKey: .message)
            )
        case "agent.response.delta":
            self = .responseDelta(
                channelId: try container.decode(String.self, forKey: .channel_id),
                messageId: try container.decode(String.self, forKey: .message_id),
                agentId: try container.decode(String.self, forKey: .agent_id),
                delta: try container.decode(String.self, forKey: .delta)
            )
        case "agent.status.changed":
            self = .agentStatusChanged(
                agentId: try container.decode(String.self, forKey: .agent_id),
                status: try container.decode(String.self, forKey: .status)
            )
        case "channel.updated":
            self = .channelUpdated(try container.decode(Channel.self, forKey: .channel))
        default:
            self = .ignored
        }
    }
}
