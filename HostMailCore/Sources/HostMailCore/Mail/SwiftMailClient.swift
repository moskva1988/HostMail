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

    // Uses raw RFC822 fetch (UID FETCH n BODY.PEEK[]) instead of
    // fetchMessages(using:) — avoids SwiftMail's BODYSTRUCTURE pre-parse,
    // which chokes on mail.ru's malformed size fields (scientific notation
    // like "1.86931e+06"). Ref: research handoff, MailKit #1840.
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
            for identifier in identifiers {
                let raw = try await server.fetchRawMessage(identifier: identifier)
                let uidValue = UInt32(truncatingIfNeeded: extractUIDValue(identifier))
                results.append(Self.makeSnapshot(uid: uidValue, raw: raw))
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

    #if canImport(SwiftMail)
    private func extractUIDValue(_ identifier: Any) -> UInt64 {
        // MessageIdentifier<UID> has `.value: UInt32` in SwiftMail's public API.
        // Use Mirror in case exact type differs slightly across versions.
        let mirror = Mirror(reflecting: identifier)
        for child in mirror.children where child.label == "value" {
            if let v = child.value as? UInt32 { return UInt64(v) }
            if let v = child.value as? UInt64 { return v }
            if let v = child.value as? Int { return UInt64(v) }
        }
        return 0
    }

    private static func makeSnapshot(uid: UInt32, raw: Data) -> SwiftMailSnapshot {
        let text = String(data: raw, encoding: .utf8)
            ?? String(data: raw, encoding: .isoLatin1)
            ?? ""

        let (headerText, bodyText) = splitHeaderBody(text)
        let headers = parseHeaders(headerText)

        let preview = bodyText
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return SwiftMailSnapshot(
            uid: uid,
            from: decodeMimeHeader(headers["from"]),
            subject: decodeMimeHeader(headers["subject"]),
            date: headers["date"].flatMap(parseRFC2822Date),
            preview: String(preview.prefix(160))
        )
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
            let first = s.first!
            if first == " " || first == "\t" {
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

    private static func decodeMimeHeader(_ raw: String?) -> String? {
        guard let raw = raw else { return nil }
        // Very rough RFC 2047 decode: =?charset?B?base64?= or =?charset?Q?quoted?=
        let pattern = #"=\?([^?]+)\?([BbQq])\?([^?]+)\?="#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return raw }
        let ns = raw as NSString
        let range = NSRange(location: 0, length: ns.length)
        var output = raw

        regex.enumerateMatches(in: raw, range: range) { match, _, _ in
            guard let m = match else { return }
            let full = ns.substring(with: m.range)
            let charset = ns.substring(with: m.range(at: 1))
            let encoding = ns.substring(with: m.range(at: 2)).uppercased()
            let payload = ns.substring(with: m.range(at: 3))

            var decoded: String?
            if encoding == "B", let data = Data(base64Encoded: payload) {
                decoded = String(data: data, encoding: stringEncoding(for: charset))
            } else if encoding == "Q" {
                let unquoted = payload
                    .replacingOccurrences(of: "_", with: " ")
                decoded = decodeQuotedPrintable(unquoted, charset: stringEncoding(for: charset))
            }
            if let decoded = decoded {
                output = output.replacingOccurrences(of: full, with: decoded)
            }
        }
        return output
    }

    private static func stringEncoding(for charset: String) -> String.Encoding {
        switch charset.lowercased() {
        case "utf-8", "utf8": return .utf8
        case "iso-8859-1", "latin1": return .isoLatin1
        case "windows-1251", "cp1251": return .windowsCP1251
        case "koi8-r": return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.KOI8_R.rawValue)))
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
            } else {
                if let utf = String(c).data(using: .utf8) {
                    data.append(utf)
                }
            }
            i = s.index(after: i)
        }
        return String(data: data, encoding: charset)
    }

    private static func parseRFC2822Date(_ str: String) -> Date? {
        let formats = [
            "EEE, d MMM yyyy HH:mm:ss Z",
            "d MMM yyyy HH:mm:ss Z",
            "EEE, d MMM yyyy HH:mm:ss zzz",
            "EEE, d MMM yyyy HH:mm Z"
        ]
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        for f in formats {
            df.dateFormat = f
            if let d = df.date(from: str) { return d }
        }
        return nil
    }
    #endif
}
