import CoreData
import SwiftUI

public struct MessageDetailView: View {
    @Environment(\.managedObjectContext) private var context
    @ObservedObject var message: Message

    @State private var htmlBody: String?
    @State private var plainBody: String = ""
    @State private var loading = false
    @State private var error: String?

    public init(message: Message) {
        self._message = ObservedObject(wrappedValue: message)
    }

    public var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                header
                    .padding(20)
            }
            .frame(maxHeight: 140)

            Divider()

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    @ViewBuilder
    private var content: some View {
        if loading {
            VStack(spacing: 8) {
                Spacer()
                ProgressView()
                Text("Loading message body…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else if let error = error {
            ScrollView {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(HostTheme.errorRed)
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else if let html = htmlBody, !html.isEmpty {
            HTMLBodyView(html: html)
        } else if !plainBody.isEmpty {
            ScrollView {
                Text(plainBody)
                    .font(.body)
                    .textSelection(.enabled)
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            VStack {
                Spacer()
                Text("(no body — tap Refresh)")
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
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
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func loadBody(force: Bool) async {
        if !force {
            if let cachedHTML = message.bodyHTML, !cachedHTML.isEmpty {
                htmlBody = cachedHTML
                if let cachedPlain = message.bodyPlain { plainBody = cachedPlain }
                return
            }
            if let cachedPlain = message.bodyPlain, !cachedPlain.isEmpty {
                plainBody = cachedPlain
                return
            }
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
                if let html = result.html, !html.isEmpty {
                    htmlBody = html
                    plainBody = result.plain ?? ""
                } else if let plain = result.plain, !plain.isEmpty {
                    htmlBody = nil
                    plainBody = plain
                } else if let raw = result.raw, !raw.isEmpty {
                    htmlBody = nil
                    plainBody = "(MIME parse failed — showing raw RFC822)\n\n" + String(raw.prefix(3000))
                } else {
                    htmlBody = nil
                    plainBody = ""
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
}
