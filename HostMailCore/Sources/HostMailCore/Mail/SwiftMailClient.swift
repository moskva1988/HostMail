import Foundation
#if canImport(SwiftMail)
@preconcurrency import SwiftMail
#endif

public enum SwiftMailError: LocalizedError {
    case unavailable
    case underlying(Error)

    public var errorDescription: String? {
        switch self {
        case .unavailable:
            "SwiftMail is not available in this build"
        case .underlying(let e):
            e.localizedDescription
        }
    }
}

public struct SwiftMailSnapshot: Sendable, Hashable {
    public let uid: UInt32
    public let from: String?
    public let subject: String?
    public let date: Date?
    public let preview: String?

    public init(uid: UInt32, from: String?, subject: String?, date: Date?, preview: String?) {
        self.uid = uid
        self.from = from
        self.subject = subject
        self.date = date
        self.preview = preview
    }
}

public actor SwiftMailClient {
    public struct Credentials: Sendable {
        public let host: String
        public let port: Int
        public let username: String
        public let password: String

        public init(host: String, port: Int, username: String, password: String) {
            self.host = host
            self.port = port
            self.username = username
            self.password = password
        }
    }

    private let credentials: Credentials

    public init(credentials: Credentials) {
        self.credentials = credentials
    }

    public func fetchRecent(folder: String = "INBOX", limit: Int = 10) async throws -> [SwiftMailSnapshot] {
        #if canImport(SwiftMail)
        let server = IMAPServer(host: credentials.host, port: credentials.port)
        do {
            try await server.connect()
            try await server.login(username: credentials.username, password: credentials.password)
        } catch {
            throw SwiftMailError.underlying(error)
        }

        do {
            let status = try await server.selectMailbox(folder)
            guard let identifiers = status.latest(limit) else {
                try? await server.disconnect()
                return []
            }

            var results: [SwiftMailSnapshot] = []
            for try await message in server.fetchMessages(using: identifiers) {
                let preview = message.textBody.map { String($0.prefix(160)) }
                results.append(SwiftMailSnapshot(
                    uid: message.uid?.value ?? 0,
                    from: message.from,
                    subject: message.subject,
                    date: message.date,
                    preview: preview
                ))
            }
            try? await server.disconnect()
            return results.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        } catch {
            try? await server.disconnect()
            throw SwiftMailError.underlying(error)
        }
        #else
        throw SwiftMailError.unavailable
        #endif
    }
}
