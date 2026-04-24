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

    // Metadata-only bulk fetch via SwiftMail's fetchMessageInfos(sequenceRange:).
    // One IMAP FETCH command requesting ENVELOPE+FLAGS+INTERNALDATE+UID+SIZE
    // — no body, no BODY.PEEK[]. Handler tolerates mail.ru's malformed
    // BODYSTRUCTURE (leaves parts == []), so this works where the previous
    // raw-fetch path timed out on multi-MB messages.
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
            let total = UInt32(status.messageCount)
            guard total > 0 else {
                try? await server.disconnect()
                return []
            }

            let effectiveLimit = min(UInt32(limit), total)
            let firstSeq = SequenceNumber(total - effectiveLimit + 1)
            let lastSeq = SequenceNumber(total)
            let infos = try await server.fetchMessageInfos(sequenceRange: firstSeq...lastSeq)

            try? await server.disconnect()

            let snapshots = infos.map { info -> SwiftMailSnapshot in
                let uidValue = info.uid?.value ?? info.sequenceNumber.value
                return SwiftMailSnapshot(
                    uid: uidValue,
                    from: info.from,
                    subject: info.subject,
                    date: info.date ?? info.internalDate,
                    preview: nil
                )
            }
            return snapshots.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        } catch {
            try? await server.disconnect()
            throw SwiftMailError.underlying(error)
        }
        #else
        throw SwiftMailError.unavailable
        #endif
    }
}
