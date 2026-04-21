import Foundation

public final class ClaudeProvider: AIProvider {
    public let kind: AIProviderKind = .claude

    private let apiKey: String?

    public var isConfigured: Bool { apiKey != nil }

    public init(apiKey: String? = nil) {
        self.apiKey = apiKey
    }

    public func draftReply(to message: String, tone: AITone) async throws -> String {
        guard apiKey != nil else { throw AIError.missingAPIKey(kind) }
        throw AIError.notImplemented
    }

    public func summarize(_ text: String) async throws -> String {
        guard apiKey != nil else { throw AIError.missingAPIKey(kind) }
        throw AIError.notImplemented
    }

    public func categorize(_ text: String, categories: [String]) async throws -> String {
        guard apiKey != nil else { throw AIError.missingAPIKey(kind) }
        throw AIError.notImplemented
    }

    public func chat(_ messages: [AIMessage]) async throws -> String {
        guard apiKey != nil else { throw AIError.missingAPIKey(kind) }
        throw AIError.notImplemented
    }
}
