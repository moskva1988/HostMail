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

    public init(plain: String?, html: String?) {
        self.plain = plain
        self.html = html
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

    // Fetches the full RFC822 of one message and extracts text/plain + text/html
    // bodies via a minimal MIME parser. Used for lazy "tap to read" — result is
    // cached in Core Data so this only runs once per message.
    public func fetchBody(sequenceNumber: UInt32, folder: String = "INBOX") async throws -> SwiftMailBody {
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
            let raw = try await server.fetchRawMessage(identifier: SequenceNumber(sequenceNumber))
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
            return parseMultipart(bodyText, boundary: boundary)
        }
        let decoded = decodeContent(bodyText, transferEncoding: cte, charset: charset)
        if mainType == "text/html" {
            return SwiftMailBody(plain: nil, html: decoded)
        }
        return SwiftMailBody(plain: decoded, html: nil)
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
            if s == delim || s == endDelim {
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
