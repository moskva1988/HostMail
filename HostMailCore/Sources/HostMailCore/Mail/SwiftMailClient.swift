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

public struct SwiftMailBody: Sendable, Hashable {
    public let plain: String?
    public let html: String?
    public let raw: String?

    public init(plain: String?, html: String?, raw: String? = nil) {
        self.plain = plain
        self.html = html
        self.raw = raw
    }
}

public enum MailFolderRole: String, Sendable, Codable {
    case inbox
    case drafts
    case sent
    case trash
    case junk
    case archive
    case other
}

public struct SwiftMailFolderInfo: Sendable, Hashable {
    public let path: String          // raw IMAP mailbox path, e.g. "INBOX/Personal"
    public let displayName: String   // last path component
    public let role: MailFolderRole

    public init(path: String, displayName: String, role: MailFolderRole) {
        self.path = path
        self.displayName = displayName
        self.role = role
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

    public func listFolders() async throws -> [SwiftMailFolderInfo] {
        #if canImport(SwiftMail)
        let server = IMAPServer(host: credentials.host, port: credentials.port)
        do {
            try await server.connect()
            try await server.login(username: credentials.username, password: credentials.password)
        } catch {
            throw SwiftMailError.underlying(error)
        }
        do {
            // Generic LIST "" "*" — every mailbox the account exposes,
            // including custom user folders that listSpecialUseMailboxes
            // misses on servers that don't tag folders with RFC 6154 flags
            // (mail.ru only flags INBOX, hides everything else).
            let allBoxes = try await server.listMailboxes()
            try? await server.disconnect()

            // Capture the role-bearing names once via the array's built-in
            // SPECIAL-USE accessors (they fall back to common English names
            // like "Sent" / "Drafts").
            let inboxName   = allBoxes.inbox?.name
            let sentName    = allBoxes.sent?.name
            let draftsName  = allBoxes.drafts?.name
            let trashName   = allBoxes.trash?.name
            let junkName    = allBoxes.junk?.name
            let archiveName = allBoxes.archive?.name

            var byPath: [String: SwiftMailFolderInfo] = [:]
            for box in allBoxes {
                guard box.isSelectable else { continue }   // skip Gmail [Gmail] root etc.
                let path = box.name                          // raw mUTF-7 — must keep for SELECT
                let decoded = Self.decodeModifiedUTF7(path)  // human-readable name
                let display = decoded.split(separator: "/").last.map(String.init) ?? decoded
                let role = roleFor(
                    rawName: path,
                    decodedName: decoded,
                    inbox: inboxName, sent: sentName, drafts: draftsName,
                    trash: trashName, junk: junkName, archive: archiveName
                )
                byPath[path] = SwiftMailFolderInfo(path: path, displayName: display, role: role)
            }
            if byPath["INBOX"] == nil {
                byPath["INBOX"] = SwiftMailFolderInfo(path: "INBOX", displayName: "INBOX", role: .inbox)
            }
            return Array(byPath.values).sorted { a, b in
                let pa = Self.rolePriority(a.role)
                let pb = Self.rolePriority(b.role)
                if pa != pb { return pa < pb }
                return a.displayName.localizedStandardCompare(b.displayName) == .orderedAscending
            }
        } catch {
            try? await server.disconnect()
            throw SwiftMailError.underlying(error)
        }
        #else
        throw SwiftMailError.unavailable
        #endif
    }

    private func roleFor(
        rawName: String,
        decodedName: String,
        inbox: String?, sent: String?, drafts: String?,
        trash: String?, junk: String?, archive: String?
    ) -> MailFolderRole {
        // English-aware match (uses raw IMAP names — SwiftMail's accessors
        // already returned them in raw form).
        if rawName == inbox   { return .inbox }
        if rawName == sent    { return .sent }
        if rawName == drafts  { return .drafts }
        if rawName == trash   { return .trash }
        if rawName == junk    { return .junk }
        if rawName == archive { return .archive }

        // Russian fallback against the decoded (mUTF-7 → UTF-8) name —
        // mail.ru / Yandex / etc. ship localized folder names that the
        // English heuristic misses. Names sourced from a real mail.ru
        // account screenshot — kept exact lowercased forms.
        switch decodedName.lowercased() {
        case "входящие":
            return .inbox
        case "отправлено", "отправленные", "отправленная почта", "отправленые":
            return .sent
        case "черновики":
            return .drafts
        case "удаленные элементы", "удалённые элементы", "корзина", "удалённые", "удаленные":
            return .trash
        case "спам", "нежелательная почта":
            return .junk
        case "архивировать", "архив":
            return .archive
        default:
            return .other
        }
    }

    /// Decodes IMAP modified UTF-7 (RFC 3501 §5.1.3) → Swift String.
    /// Used to surface human-readable folder names while keeping the raw
    /// mUTF-7 around for IMAP SELECT/STATUS calls.
    static func decodeModifiedUTF7(_ s: String) -> String {
        var result = ""
        var i = s.startIndex
        while i < s.endIndex {
            let c = s[i]
            if c != "&" {
                result.append(c)
                i = s.index(after: i)
                continue
            }
            let afterAmp = s.index(after: i)
            if afterAmp < s.endIndex, s[afterAmp] == "-" {
                // "&-" → literal "&"
                result.append("&")
                i = s.index(after: afterAmp)
                continue
            }
            guard let endIdx = s[afterAmp...].firstIndex(of: "-") else {
                result.append(contentsOf: s[i...])
                break
            }
            let encoded = String(s[afterAmp..<endIdx])
            // mUTF-7 uses ',' instead of '/' in its base64 alphabet
            let standard = encoded.replacingOccurrences(of: ",", with: "/")
            let pad = (4 - standard.count % 4) % 4
            let padded = standard + String(repeating: "=", count: pad)
            if let data = Data(base64Encoded: padded),
               let decoded = String(data: data, encoding: .utf16BigEndian) {
                result.append(decoded)
            }
            i = s.index(after: endIdx)
        }
        return result
    }

    public func createFolder(path: String) async throws {
        #if canImport(SwiftMail)
        let server = IMAPServer(host: credentials.host, port: credentials.port)
        do {
            try await server.connect()
            try await server.login(username: credentials.username, password: credentials.password)
        } catch {
            throw SwiftMailError.underlying(error)
        }
        do {
            try await server.createMailbox(path)
            try? await server.disconnect()
        } catch {
            try? await server.disconnect()
            throw SwiftMailError.underlying(error)
        }
        #else
        throw SwiftMailError.unavailable
        #endif
    }

    private static func rolePriority(_ role: MailFolderRole) -> Int {
        switch role {
        case .inbox: 0
        case .sent: 1
        case .drafts: 2
        case .archive: 3
        case .trash: 4
        case .junk: 5
        case .other: 6
        }
    }

    // Metadata-only bulk fetch via SwiftMail's fetchMessageInfos(sequenceRange:).
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

    // Fetches the full RFC822 of one message by IMAP UID and extracts
    // text/plain + text/html bodies via a minimal MIME parser. Used for lazy
    // "tap to read" — result is cached in Core Data so this only runs once
    // per message. UID is persistent across the mailbox lifetime, unlike
    // sequence numbers which shift on EXPUNGE — that distinction is critical:
    // passing a UID as a SequenceNumber asks the server for position N in the
    // current mailbox, which usually returns 0 bytes.
    public func fetchBody(uid: UInt32, folder: String = "INBOX") async throws -> SwiftMailBody {
        #if canImport(SwiftMail)
        let server = IMAPServer(host: credentials.host, port: credentials.port)
        do {
            try await server.connect()
            try await server.login(username: credentials.username, password: credentials.password)
        } catch {
            throw SwiftMailError.underlying(error)
        }

        do {
            _ = try await server.selectMailbox(folder)
            let raw = try await server.fetchRawMessage(identifier: UID(uid))
            try? await server.disconnect()
            return Self.extractBody(from: raw)
        } catch {
            try? await server.disconnect()
            throw SwiftMailError.underlying(error)
        }
        #else
        throw SwiftMailError.unavailable
        #endif
    }

    // MARK: - MIME helpers

    static func extractBody(from raw: Data) -> SwiftMailBody {
        let text = String(data: raw, encoding: .utf8)
            ?? String(data: raw, encoding: .isoLatin1)
            ?? ""
        let (headerText, bodyText) = splitHeaderBody(text)
        let headers = parseHeaders(headerText)
        let contentType = headers["content-type"] ?? "text/plain"
        let (mainType, params) = parseContentType(contentType)
        let cte = (headers["content-transfer-encoding"] ?? "").lowercased()
        let charset = params["charset"] ?? "utf-8"

        if mainType.hasPrefix("multipart/"), let boundary = params["boundary"] {
            let parsed = parseMultipart(bodyText, boundary: boundary)
            if parsed.plain == nil && parsed.html == nil {
                return SwiftMailBody(plain: nil, html: nil, raw: text)
            }
            return SwiftMailBody(plain: parsed.plain, html: parsed.html, raw: text)
        }
        let decoded = decodeContent(bodyText, transferEncoding: cte, charset: charset)
        if mainType == "text/html" {
            return SwiftMailBody(plain: nil, html: decoded, raw: text)
        }
        return SwiftMailBody(plain: decoded, html: nil, raw: text)
    }

    private static func splitHeaderBody(_ text: String) -> (header: String, body: String) {
        if let r = text.range(of: "\r\n\r\n") {
            return (String(text[..<r.lowerBound]), String(text[r.upperBound...]))
        }
        if let r = text.range(of: "\n\n") {
            return (String(text[..<r.lowerBound]), String(text[r.upperBound...]))
        }
        return (text, "")
    }

    private static func parseHeaders(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        var currentKey: String?
        var currentValue = ""
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false)
        for line in lines {
            let s = String(line)
            if s.isEmpty { continue }
            if s.first == " " || s.first == "\t" {
                currentValue += " " + s.trimmingCharacters(in: .whitespaces)
                continue
            }
            if let key = currentKey {
                result[key] = currentValue.trimmingCharacters(in: .whitespaces)
            }
            if let colonIdx = s.firstIndex(of: ":") {
                currentKey = String(s[..<colonIdx]).lowercased()
                currentValue = String(s[s.index(after: colonIdx)...])
            } else {
                currentKey = nil
                currentValue = ""
            }
        }
        if let key = currentKey {
            result[key] = currentValue.trimmingCharacters(in: .whitespaces)
        }
        return result
    }

    private static func parseContentType(_ value: String) -> (type: String, params: [String: String]) {
        let parts = value.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
        let type = (parts.first ?? "text/plain").lowercased()
        var params: [String: String] = [:]
        for part in parts.dropFirst() {
            if let eq = part.firstIndex(of: "=") {
                let k = String(part[..<eq]).trimmingCharacters(in: .whitespaces).lowercased()
                var v = String(part[part.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
                if v.hasPrefix("\"") && v.hasSuffix("\"") {
                    v = String(v.dropFirst().dropLast())
                }
                params[k] = v
            }
        }
        return (type, params)
    }

    private static func parseMultipart(_ body: String, boundary: String) -> SwiftMailBody {
        let delim = "--\(boundary)"
        let endDelim = "--\(boundary)--"
        var parts: [String] = []
        var current = ""
        let lines = body.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false)
        for line in lines {
            let s = String(line)
            // Trim trailing whitespace/CR — boundaries may have trailing space
            // or stray \r that escaped our earlier replacement.
            let trimmed = s.trimmingCharacters(in: .whitespaces)
            if trimmed == delim || trimmed == endDelim {
                if !current.isEmpty { parts.append(current); current = "" }
            } else {
                current += s + "\n"
            }
        }
        if !current.isEmpty { parts.append(current) }

        var plain: String?
        var html: String?

        for part in parts {
            let (headerText, bodyText) = splitHeaderBody(part)
            let headers = parseHeaders(headerText)
            let (type, params) = parseContentType(headers["content-type"] ?? "text/plain")
            let cte = (headers["content-transfer-encoding"] ?? "").lowercased()
            let charset = params["charset"] ?? "utf-8"

            if type.hasPrefix("multipart/"), let nested = params["boundary"] {
                let nestedBody = parseMultipart(bodyText, boundary: nested)
                plain = plain ?? nestedBody.plain
                html = html ?? nestedBody.html
            } else if type == "text/plain", plain == nil {
                plain = decodeContent(bodyText, transferEncoding: cte, charset: charset)
            } else if type == "text/html", html == nil {
                html = decodeContent(bodyText, transferEncoding: cte, charset: charset)
            }
        }
        return SwiftMailBody(plain: plain, html: html)
    }

    private static func decodeContent(_ raw: String, transferEncoding: String, charset: String) -> String {
        let encoding = stringEncoding(for: charset)
        switch transferEncoding {
        case "base64":
            let stripped = raw.replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: " ", with: "")
            if let data = Data(base64Encoded: stripped), let s = String(data: data, encoding: encoding) {
                return s
            }
            return raw
        case "quoted-printable":
            return decodeQuotedPrintable(raw, charset: encoding) ?? raw
        default:
            // 7bit, 8bit, binary, none — try to recode if charset isn't UTF-8
            if encoding == .utf8 { return raw }
            if let data = raw.data(using: .isoLatin1), let s = String(data: data, encoding: encoding) {
                return s
            }
            return raw
        }
    }

    private static func stringEncoding(for charset: String) -> String.Encoding {
        switch charset.lowercased() {
        case "utf-8", "utf8": return .utf8
        case "iso-8859-1", "latin1": return .isoLatin1
        case "windows-1251", "cp1251": return .windowsCP1251
        case "koi8-r":
            return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.KOI8_R.rawValue)))
        default: return .utf8
        }
    }

    private static func decodeQuotedPrintable(_ s: String, charset: String.Encoding) -> String? {
        var data = Data()
        var i = s.startIndex
        while i < s.endIndex {
            let c = s[i]
            if c == "=" {
                let next = s.index(after: i)
                if next < s.endIndex, s[next] == "\n" {
                    i = s.index(after: next); continue
                }
                if next < s.endIndex, s[next] == "\r" {
                    let nn = s.index(after: next)
                    if nn < s.endIndex, s[nn] == "\n" { i = s.index(after: nn); continue }
                    i = nn; continue
                }
                if next < s.endIndex, s.index(after: next) < s.endIndex {
                    let hex = String(s[next...s.index(after: next)])
                    if let byte = UInt8(hex, radix: 16) {
                        data.append(byte)
                        i = s.index(after: s.index(after: next))
                        continue
                    }
                }
            }
            if let ascii = c.asciiValue {
                data.append(ascii)
            } else if let utf = String(c).data(using: .utf8) {
                data.append(utf)
            }
            i = s.index(after: i)
        }
        return String(data: data, encoding: charset)
    }
}
