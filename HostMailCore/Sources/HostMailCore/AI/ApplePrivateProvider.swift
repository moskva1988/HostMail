import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

public final class ApplePrivateProvider: AIProvider {
    public let kind: AIProviderKind = .apple

    public var isConfigured: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            return SystemLanguageModel.default.isAvailable
        }
        #endif
        return false
    }

    public init() {}

    public func draftReply(to message: String, tone: AITone) async throws -> String {
        try await generate(
            prompt: message,
            instructions: """
            Write a concise email reply in a \(tone.displayName.lowercased()) tone. \
            Return only the reply body text — no preamble, no subject line, no signature.
            """
        )
    }

    public func summarize(_ text: String) async throws -> String {
        try await generate(
            prompt: text,
            instructions: "Summarize the text in one or two short sentences. Return only the summary."
        )
    }

    public func categorize(_ text: String, categories: [String]) async throws -> String {
        let list = categories.joined(separator: ", ")
        return try await generate(
            prompt: text,
            instructions: """
            Pick exactly one category from this list that best matches the text: \(list). \
            Return only the category name, nothing else.
            """
        )
    }

    public func chat(_ messages: [AIMessage]) async throws -> String {
        let (instructions, prompt) = flattenChat(messages)
        return try await generate(prompt: prompt, instructions: instructions)
    }

    private func flattenChat(_ messages: [AIMessage]) -> (instructions: String, prompt: String) {
        var systemParts: [String] = []
        var conversationParts: [String] = []
        for message in messages {
            switch message.role {
            case .system:
                systemParts.append(message.content)
            case .user:
                conversationParts.append("User: \(message.content)")
            case .assistant:
                conversationParts.append("Assistant: \(message.content)")
            }
        }
        let instructions = systemParts.isEmpty
            ? "You are a helpful email assistant."
            : systemParts.joined(separator: "\n\n")
        let prompt = conversationParts.joined(separator: "\n\n")
        return (instructions, prompt)
    }

    private func generate(prompt: String, instructions: String) async throws -> String {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, macOS 26.0, *) else {
            throw AIError.unavailable(reason: "Apple Intelligence requires iOS 26 or macOS 26")
        }

        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            break
        case .unavailable(let reason):
            throw AIError.unavailable(reason: String(describing: reason))
        @unknown default:
            throw AIError.unavailable(reason: "Apple Intelligence state unknown")
        }

        do {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(to: prompt)
            return response.content
        } catch let error as AIError {
            throw error
        } catch {
            throw AIError.network(underlying: error)
        }
        #else
        throw AIError.unavailable(reason: "FoundationModels framework not available in this SDK")
        #endif
    }
}
