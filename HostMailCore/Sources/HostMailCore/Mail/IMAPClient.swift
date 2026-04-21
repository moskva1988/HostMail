import Foundation
#if canImport(MailCore)
@preconcurrency import MailCore
#endif

public enum IMAPError: LocalizedError {
    case unavailable
    case operationCreationFailed
    case invalidResponse
    case network(underlying: Error)

    public var errorDescription: String? {
        switch self {
        case .unavailable:
            "MailCore2 is not available in this build"
        case .operationCreationFailed:
            "IMAP operation could not be created"
        case .invalidResponse:
            "IMAP server returned an invalid response"
        case .network(let underlying):
            "IMAP network error: \(underlying.localizedDescription)"
        }
    }
}

public actor IMAPClient {
    public struct Credentials: Sendable {
        public let host: String
        public let port: UInt32
        public let useSSL: Bool
        public let username: String
        public let password: String

        public init(host: String, port: UInt32, useSSL: Bool, username: String, password: String) {
            self.host = host
            self.port = port
            self.useSSL = useSSL
            self.username = username
            self.password = password
        }
    }

    #if canImport(MailCore)
    private let session: MCOIMAPSession
    #endif

    public init(credentials: Credentials) {
        #if canImport(MailCore)
        let s = MCOIMAPSession()
        s.hostname = credentials.host
        s.port = credentials.port
        s.username = credentials.username
        s.password = credentials.password
        s.connectionType = credentials.useSSL ? .TLS : .clear
        s.authType = .saslPlain
        self.session = s
        #endif
    }

    public func listFolders() async throws -> [IMAPFolderInfo] {
        #if canImport(MailCore)
        guard let op = session.fetchAllFoldersOperation() else {
            throw IMAPError.operationCreationFailed
        }
        return try await withCheckedThrowingContinuation { cont in
            op.start { error, folders in
                if let error = error {
                    cont.resume(throwing: IMAPError.network(underlying: error))
                    return
                }
                let infos: [IMAPFolderInfo] = (folders as? [MCOIMAPFolder])?.compactMap { f in
                    guard let path = f.path else { return nil }
                    return IMAPFolderInfo(path: path, flags: Int(f.flags.rawValue))
                } ?? []
                cont.resume(returning: infos)
            }
        }
        #else
        throw IMAPError.unavailable
        #endif
    }

    public func fetchRecentHeaders(folder: String, limit: Int = 50) async throws -> [MessageSummary] {
        #if canImport(MailCore)
        let info = try await folderInfo(folder: folder)
        let uidNext = info.uidNext
        guard uidNext > 1 else { return [] }

        let from = max(UInt32(1), uidNext > UInt32(limit) ? uidNext - UInt32(limit) : 1)
        let length = UInt64(uidNext - from)
        let range = MCORangeMake(UInt64(from), length)
        guard let uidSet = MCOIndexSet(range: range) else {
            throw IMAPError.operationCreationFailed
        }

        let kind: MCOIMAPMessagesRequestKind = [.headers, .flags, .structure]
        guard let op = session.fetchMessagesOperation(
            withFolder: folder,
            requestKind: kind,
            uids: uidSet
        ) else {
            throw IMAPError.operationCreationFailed
        }

        return try await withCheckedThrowingContinuation { cont in
            op.start { error, messages, _ in
                if let error = error {
                    cont.resume(throwing: IMAPError.network(underlying: error))
                    return
                }
                let summaries: [MessageSummary] = (messages as? [MCOIMAPMessage])?.map { m in
                    Self.makeSummary(from: m)
                } ?? []
                cont.resume(returning: summaries.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) })
            }
        }
        #else
        throw IMAPError.unavailable
        #endif
    }

    public func fetchBody(uid: UInt32, folder: String) async throws -> (plain: String?, html: String?) {
        #if canImport(MailCore)
        guard let op = session.fetchParsedMessageOperation(withFolder: folder, uid: uid) else {
            throw IMAPError.operationCreationFailed
        }
        return try await withCheckedThrowingContinuation { cont in
            op.start { error, parser in
                if let error = error {
                    cont.resume(throwing: IMAPError.network(underlying: error))
                    return
                }
                guard let parser = parser else {
                    cont.resume(throwing: IMAPError.invalidResponse)
                    return
                }
                cont.resume(returning: (
                    plain: parser.plainTextBodyRendering(),
                    html: parser.htmlBodyRendering()
                ))
            }
        }
        #else
        throw IMAPError.unavailable
        #endif
    }

    #if canImport(MailCore)
    private func folderInfo(folder: String) async throws -> MCOIMAPFolderInfo {
        guard let op = session.folderInfoOperation(folder) else {
            throw IMAPError.operationCreationFailed
        }
        return try await withCheckedThrowingContinuation { cont in
            op.start { error, info in
                if let error = error {
                    cont.resume(throwing: IMAPError.network(underlying: error))
                    return
                }
                guard let info = info else {
                    cont.resume(throwing: IMAPError.invalidResponse)
                    return
                }
                cont.resume(returning: info)
            }
        }
    }

    private static func makeSummary(from m: MCOIMAPMessage) -> MessageSummary {
        let header = m.header
        return MessageSummary(
            uid: m.uid,
            messageID: header?.messageID,
            subject: header?.subject,
            from: header?.from?.nonEncodedRFC822String,
            to: joinAddresses(header?.to as? [MCOAddress]),
            cc: joinAddresses(header?.cc as? [MCOAddress]),
            date: header?.date,
            flags: convertFlags(m.flags),
            hasAttachments: hasAttachments(part: m.mainPart)
        )
    }

    private static func joinAddresses(_ addrs: [MCOAddress]?) -> String? {
        guard let addrs = addrs, !addrs.isEmpty else { return nil }
        let joined = addrs.compactMap { $0.nonEncodedRFC822String }.joined(separator: ", ")
        return joined.isEmpty ? nil : joined
    }

    private static func convertFlags(_ flags: MCOMessageFlag) -> MessageFlags {
        var result: MessageFlags = []
        if flags.contains(.seen)     { result.insert(.seen) }
        if flags.contains(.answered) { result.insert(.answered) }
        if flags.contains(.flagged)  { result.insert(.flagged) }
        if flags.contains(.deleted)  { result.insert(.deleted) }
        if flags.contains(.draft)    { result.insert(.draft) }
        return result
    }

    private static func hasAttachments(part: MCOAbstractPart?) -> Bool {
        guard let part = part else { return false }
        if let attach = part as? MCOAttachment, !attach.isInlineAttachment {
            return true
        }
        if let multipart = part as? MCOAbstractMultipart {
            for sub in (multipart.parts as? [MCOAbstractPart]) ?? [] {
                if hasAttachments(part: sub) { return true }
            }
        }
        if let message = part as? MCOAbstractMessagePart {
            return hasAttachments(part: message.mainPart)
        }
        return false
    }
    #endif
}
