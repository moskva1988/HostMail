import Foundation

public enum AIProviderKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case apple
    case claude
    case openai
    case yandex
    case gigachat

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .apple: "Apple Intelligence"
        case .claude: "Claude"
        case .openai: "OpenAI"
        case .yandex: "Yandex Alice"
        case .gigachat: "GigaChat"
        }
    }

    public var requiresAPIKey: Bool {
        switch self {
        case .apple: false
        case .claude, .openai, .yandex, .gigachat: true
        }
    }
}
