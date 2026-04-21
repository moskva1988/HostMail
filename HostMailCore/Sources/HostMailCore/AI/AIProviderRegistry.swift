import Foundation

public final class AIProviderRegistry: @unchecked Sendable {
    public static let shared = AIProviderRegistry()

    public init() {}

    public func provider(for kind: AIProviderKind, apiKey: String? = nil) -> any AIProvider {
        switch kind {
        case .apple:
            ApplePrivateProvider()
        case .claude:
            ClaudeProvider(apiKey: apiKey)
        case .openai:
            OpenAIProvider(apiKey: apiKey)
        case .yandex:
            YandexProvider(apiKey: apiKey)
        case .gigachat:
            GigaChatProvider(apiKey: apiKey)
        }
    }

    public func defaultProvider() -> any AIProvider {
        provider(for: .apple)
    }
}
