import Foundation

public struct MessageSummary: Sendable, Hashable {
    public let uid: UInt32
    public let messageID: String?
    public let subject: String?
    public let from: String?
    public let to: String?
    public let cc: String?
    public let date: Date?
    public let flags: MessageFlags
    public let hasAttachments: Bool

    public init(
        uid: UInt32,
        messageID: String?,
        subject: String?,
        from: String?,
        to: String?,
        cc: String?,
        date: Date?,
        flags: MessageFlags,
        hasAttachments: Bool
    ) {
        self.uid = uid
        self.messageID = messageID
        self.subject = subject
        self.from = from
        self.to = to
        self.cc = cc
        self.date = date
        self.flags = flags
        self.hasAttachments = hasAttachments
    }
}

public struct IMAPFolderInfo: Sendable, Hashable {
    public let path: String
    public let flags: Int

    public init(path: String, flags: Int) {
        self.path = path
        self.flags = flags
    }
}

extension MessageFlags: Hashable {}
