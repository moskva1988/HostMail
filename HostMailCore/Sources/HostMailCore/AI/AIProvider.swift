import Foundation

public protocol AIProvider: Sendable {
    var kind: AIProviderKind { get }
    var isConfigured: Bool { get }

    func draftReply(to message: String, tone: AITone) async throws -> String
    func summarize(_ text: String) async throws -> String
    func categorize(_ text: String, categories: [String]) async throws -> String
    func chat(_ messages: [AIMessage]) async throws -> String
}

public enum AITone: String, Codable, CaseIterable, Sendable {
    case neutral
    case formal
    case friendly
    case concise
    case apologetic

    public var displayName: String {
        switch self {
        case .neutral: "Neutral"
        case .formal: "Formal"
        case .friendly: "Friendly"
        case .concise: "Concise"
        case .apologetic: "Apologetic"
        }
    }
}

public enum AIRole: String, Codable, Sendable {
    case system
    case user
    case assistant
}

public struct AIMessage: Codable, Sendable, Hashable {
    public let role: AIRole
    public let content: String

    public init(role: AIRole, content: String) {
        self.role = role
        self.content = content
    }
}

public enum AIError: LocalizedError {
    case notConfigured(AIProviderKind)
    case missingAPIKey(AIProviderKind)
    case unavailable(reason: String)
    case invalidResponse
    case network(underlying: Error)
    case notImplemented

    public var errorDescription: String? {
        switch self {
        case .notConfigured(let kind):
            "AI provider \(kind.displayName) is not configured"
        case .missingAPIKey(let kind):
            "API key for \(kind.displayName) is missing"
        case .unavailable(let reason):
            "AI provider unavailable: \(reason)"
        case .invalidResponse:
            "Received an invalid response from the AI provider"
        case .network(let underlying):
            "Network error: \(underlying.localizedDescription)"
        case .notImplemented:
            "This capability is not yet implemented"
        }
    }
}
