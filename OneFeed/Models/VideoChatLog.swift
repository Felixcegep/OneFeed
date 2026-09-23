import Foundation

struct VideoChatMessage: Codable, Identifiable, Equatable, Sendable {
    enum Role: String, Codable, Sendable {
        case user
        case model
    }

    var id: UUID
    var role: Role
    var text: String
    var createdAt: Date
}

enum VideoChatLog {
    static let limit = 40

    static func decode(_ data: Data?) -> [VideoChatMessage] {
        guard let data else { return [] }
        let iso8601 = JSONDecoder()
        iso8601.dateDecodingStrategy = .iso8601
        if let messages = try? iso8601.decode([VideoChatMessage].self, from: data) {
            return messages
        }
        return (try? JSONDecoder().decode([VideoChatMessage].self, from: data)) ?? []
    }

    static func encode(_ messages: [VideoChatMessage]) -> Data? {
        guard !messages.isEmpty else { return nil }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(messages)
    }

    static func trimmed(_ messages: [VideoChatMessage]) -> [VideoChatMessage] {
        guard messages.count > limit else { return messages }
        return Array(messages.suffix(limit))
    }
}
