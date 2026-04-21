import CoreData
import SwiftUI

public struct RootView: View {
    @Environment(\.managedObjectContext) private var context
    @State private var storeStatus: String = "Loading store…"
    @State private var aiStatus: String = "Checking Apple Intelligence…"
    @State private var aiTestResult: String = ""
    @State private var aiTestRunning = false
    @State private var showIMAPTestSheet = false
    @State private var imapTestResult: String = ""

    public init() {}

    public var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "envelope.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text("HostMail")
                .font(.largeTitle.weight(.bold))
            Text("v\(HostMailCore.version) — skeleton")
                .foregroundStyle(.secondary)

            Divider().padding(.horizontal, 40)

            Label(storeStatus, systemImage: "externaldrive.badge.icloud")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Label(aiStatus, systemImage: "brain.head.profile")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button(action: runAITest) {
                HStack(spacing: 8) {
                    if aiTestRunning {
                        ProgressView().controlSize(.small)
                    }
                    Text("Test Apple Intelligence")
                }
                .frame(minWidth: 220)
            }
            .buttonStyle(.borderedProminent)
            .disabled(aiTestRunning)
            .padding(.top, 8)

            if !aiTestResult.isEmpty {
                Text(aiTestResult)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.top, 4)
            }

            Button {
                showIMAPTestSheet = true
            } label: {
                Text("Test IMAP Fetch").frame(minWidth: 220)
            }
            .buttonStyle(.bordered)

            if !imapTestResult.isEmpty {
                Text(imapTestResult)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
        }
        .padding()
        .frame(minWidth: 360, minHeight: 600)
        .task { await bootstrap() }
        .sheet(isPresented: $showIMAPTestSheet) {
            IMAPTestSheet(result: $imapTestResult)
        }
    }

    private func bootstrap() async {
        let request: NSFetchRequest<Account> = Account.fetchRequest()
        let count: Int = await context.perform {
            (try? context.count(for: request)) ?? 0
        }
        let mode = PersistenceController.shared.cloudKitEnabled ? "Core Data + CloudKit" : "Core Data (local-only — sign in to iCloud to sync)"
        storeStatus = "\(mode) — \(count) account(s)"

        let provider = ApplePrivateProvider()
        aiStatus = provider.isConfigured
            ? "Apple Intelligence: Ready"
            : "Apple Intelligence: Not available on this device"
    }

    private func runAITest() {
        aiTestRunning = true
        aiTestResult = ""
        Task {
            defer { aiTestRunning = false }
            let provider = ApplePrivateProvider()
            do {
                let result = try await provider.summarize(
                    "HostMail is a native iOS and macOS email client with built-in AI assistance. It uses Apple Intelligence by default and supports BYOK for Claude, OpenAI, Yandex Alice, and GigaChat."
                )
                aiTestResult = result
            } catch {
                aiTestResult = "Error: \(error.localizedDescription)"
            }
        }
    }
}

private struct IMAPTestSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var result: String

    @State private var email: String = ""
    @State private var password: String = ""
    @State private var host: String = "imap.gmail.com"
    @State private var port: String = "993"
    @State private var useSSL: Bool = true
    @State private var running = false
    @State private var output: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Test IMAP Fetch")
                .font(.title2.bold())
            Text("Credentials are used for this session only — not stored.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Group {
                TextField("Email / Username", text: $email)
                    .textContentType(.username)
                    .disableAutocorrection(true)
                #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                #endif
                SecureField("Password / App Password", text: $password)
                TextField("IMAP Host", text: $host)
                    .disableAutocorrection(true)
                HStack {
                    TextField("Port", text: $port)
                        .frame(maxWidth: 100)
                    Toggle("SSL", isOn: $useSSL)
                }
            }
            .textFieldStyle(.roundedBorder)

            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                Spacer()
                Button(action: run) {
                    HStack(spacing: 6) {
                        if running { ProgressView().controlSize(.small) }
                        Text("Connect & Fetch 20")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(running || email.isEmpty || password.isEmpty || host.isEmpty)
            }

            if !output.isEmpty {
                ScrollView {
                    Text(output)
                        .font(.caption.monospaced())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 200)
            }
        }
        .padding(20)
        .frame(minWidth: 420)
    }

    private func run() {
        running = true
        output = ""
        let creds = IMAPClient.Credentials(
            host: host,
            port: UInt32(port) ?? 993,
            useSSL: useSSL,
            username: email,
            password: password
        )
        Task {
            defer { running = false }
            do {
                let coordinator = MailSyncCoordinator(container: PersistenceController.shared.container)
                let res = try await coordinator.syncRecent(
                    credentials: creds,
                    accountEmail: email,
                    accountDisplayName: nil,
                    folder: "INBOX",
                    limit: 20
                )
                let summary = "\(res.folderPath): +\(res.newMessages) new, ~\(res.updatedMessages) updated, total fetched \(res.totalInFolder)"
                output = summary
                result = summary
            } catch {
                output = "Error: \(error.localizedDescription)"
                result = output
            }
        }
    }
}

#Preview {
    RootView()
        .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
}
