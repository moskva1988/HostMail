import CoreData
import SwiftUI

public struct MessageDetailView: View {
    @Environment(\.managedObjectContext) private var context
    @ObservedObject var message: Message

    @State private var body_: String = ""
    @State private var loading = false
    @State private var error: String?

    public init(message: Message) {
        self._message = ObservedObject(wrappedValue: message)
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                Divider()
                if loading {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Loading message body…")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)
                } else if let error = error {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(HostTheme.errorRed)
                } else if !body_.isEmpty {
                    Text(body_)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("(no body — tap Refresh)")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
        }
        .navigationTitle(message.subject ?? "(no subject)")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await loadBody(force: true) }
                } label: {
                    if loading {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(loading)
            }
        }
        .task { await loadBody(force: false) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(message.subject ?? "(no subject)")
                .font(.title3.weight(.semibold))
            HStack(spacing: 6) {
                Text("From:")
                    .foregroundStyle(.secondary)
                Text(message.from ?? "(unknown)")
                    .lineLimit(1)
            }
            .font(.callout)
            if let date = message.date {
                HStack(spacing: 6) {
                    Text("Date:")
                        .foregroundStyle(.secondary)
                    Text(date.formatted(date: .complete, time: .shortened))
                }
                .font(.caption)
            }
        }
    }

    private func loadBody(force: Bool) async {
        if !force, let cached = message.bodyPlain, !cached.isEmpty {
            body_ = cached
            return
        }
        if !force, let html = message.bodyHTML, !html.isEmpty, body_.isEmpty {
            body_ = stripHTML(html)
            return
        }

        guard let account = message.folder?.account,
              let email = account.emailAddress,
              let host = account.imapHost else {
            error = "Missing account info — re-sync the inbox first."
            return
        }
        guard let password = try? KeychainStore().loadPassword(for: email) else {
            error = "Password not in Keychain. Open the sync sheet, enter password, enable Save."
            return
        }
        guard let folder = message.folder?.path else {
            error = "Message has no folder reference."
            return
        }

        let creds = SwiftMailClient.Credentials(
            host: host,
            port: Int(account.imapPort > 0 ? account.imapPort : 993),
            username: account.username ?? email,
            password: password
        )
        let uid = UInt32(message.uid)
        let messageID = message.objectID

        loading = true
        defer { loading = false }
        do {
            let client = SwiftMailClient(credentials: creds)
            let result = try await client.fetchBody(uid: uid, folder: folder)

            await MainActor.run {
                if let plain = result.plain, !plain.isEmpty {
                    body_ = plain
                } else if let html = result.html, !html.isEmpty {
                    body_ = stripHTML(html)
                } else if let raw = result.raw, !raw.isEmpty {
                    // Parser couldn't extract a readable part — surface raw RFC822
                    // (truncated) so the user gets *something* and we can debug
                    // by eye what the server actually returned.
                    let snippet = String(raw.prefix(3000))
                    body_ = "(MIME parse failed — showing raw RFC822 below)\n\n" + snippet
                } else {
                    body_ = "(empty body)"
                }
            }

            // Cache to Core Data on background context to avoid main thread save.
            let container = PersistenceController.shared.container
            let bg = container.newBackgroundContext()
            bg.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                bg.perform {
                    if let bgMsg = try? bg.existingObject(with: messageID) as? Message {
                        bgMsg.bodyPlain = result.plain
                        bgMsg.bodyHTML = result.html
                        try? bg.save()
                    }
                    cont.resume()
                }
            }
        } catch {
            await MainActor.run {
                self.error = "Fetch failed: \(error.localizedDescription)"
            }
        }
    }

    // Strips HTML tags into a plain-text approximation. Not bulletproof but
    // good enough for read-only preview while we don't have a WebKit-based
    // HTML view yet.
    private func stripHTML(_ html: String) -> String {
        var s = html
        s = s.replacingOccurrences(of: "<br[^>]*>", with: "\n", options: .regularExpression)
        s = s.replacingOccurrences(of: "</p>", with: "\n\n", options: .regularExpression)
        s = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "&nbsp;", with: " ")
        s = s.replacingOccurrences(of: "&amp;", with: "&")
        s = s.replacingOccurrences(of: "&lt;", with: "<")
        s = s.replacingOccurrences(of: "&gt;", with: ">")
        s = s.replacingOccurrences(of: "&quot;", with: "\"")
        s = s.replacingOccurrences(of: "&#39;", with: "'")
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
