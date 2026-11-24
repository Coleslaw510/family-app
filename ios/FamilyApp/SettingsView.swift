import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var familyName = ""
    @State private var server = ""
    @State private var code: String?
    @State private var showCode = false
    @State private var codePurpose = "Join code"
    @State private var integrations: IntegrationsStatus?
    @State private var simplefin: SimpleFINStatus?
    @State private var setupToken = ""
    @State private var simplefinBusy = false
    @State private var simplefinNotice: String?
    @State private var showDisconnectConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Profile") {
                    TextField("Your name", text: $name)
                        .textInputAutocapitalization(.words)
                    TextField("Family name", text: $familyName)
                        .textInputAutocapitalization(.words)
                    Button("Save names") {
                        Task { await app.saveProfile(name: name, familyName: familyName) }
                    }
                }

                Section {
                    TextField("Server URL", text: $server)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button {
                        app.updateServer(server)
                    } label: {
                        Label("Use this server", systemImage: "link")
                    }
                } header: {
                    Text("Server")
                } footer: {
                    Text("Changing the server signs you out. The app is built for \(AppConfig.defaultServer).")
                }

                Section {
                    Button {
                        Task {
                            if let fresh = await app.newJoinCode() {
                                code = fresh
                                codePurpose = "Join code"
                                showCode = true
                            }
                        }
                    } label: {
                        Label("Create new join code", systemImage: "person.badge.plus")
                    }
                } header: {
                    Text("Family")
                } footer: {
                    Text("Join codes expire in 24 hours and can be used once.")
                }

                Section {
                    Button {
                        Task {
                            if let fresh = await app.newBudgetPairingCode() {
                                code = fresh
                                codePurpose = "Budget app pairing code"
                                showCode = true
                            }
                        }
                    } label: {
                        Label("Generate pairing code", systemImage: "rectangle.portrait.and.arrow.forward")
                    }
                } header: {
                    Text("Budget app")
                } footer: {
                    Text("Generate a one-time code here, then enter it in the Budget app. It expires after 10 minutes and can only be used once.")
                }

                Section {
                    statusRow("Gemini", on: integrations?.geminiConfigured == true)
                    statusRow("RentCast", on: integrations?.rentcastActive == true)
                    if (integrations?.feeds ?? []).isEmpty {
                        LabeledContent("Calendar feeds", value: "None yet")
                    } else {
                        ForEach(integrations?.feeds ?? []) { feed in
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(Color(hexString: feed.color))
                                    .frame(width: 9, height: 9)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(feed.name)
                                    Text(feed.urlMasked)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 8)
                                Text("\(feed.eventCount)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Integrations")
                } footer: {
                    Text("Keys stay on the server. This screen only shows whether they are configured.")
                }

                Section {
                    HStack {
                        Text("Connection")
                        Spacer()
                        Text(simplefin?.connected == true ? "Connected" : "Not connected")
                            .foregroundStyle(simplefin?.connected == true ? Theme.good : Theme.muted)
                    }
                    if let lastSyncedAt = simplefin?.lastSyncedAt {
                        LabeledContent("Last synced", value: lastSyncedAt)
                    }
                    if let lastError = simplefin?.lastError {
                        Text(lastError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                    if simplefin?.connected == true {
                        Button {
                            Task { await syncSimpleFIN() }
                        } label: {
                            Label(simplefinBusy ? "Syncing…" : "Sync now", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .disabled(simplefinBusy)
                        Button("Disconnect SimpleFIN", role: .destructive) {
                            showDisconnectConfirmation = true
                        }
                        .disabled(simplefinBusy)
                    } else if simplefin?.encryptionConfigured == true {
                        SecureField("SimpleFIN Setup Token", text: $setupToken)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button {
                            Task { await connectSimpleFIN() }
                        } label: {
                            Label(simplefinBusy ? "Connecting…" : "Connect SimpleFIN", systemImage: "link")
                        }
                        .disabled(simplefinBusy || setupToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    } else {
                        Text("Server setup is required before connecting. Configure SIMPLEFIN_ENCRYPTION_KEY on the server.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if let simplefinNotice {
                        Text(simplefinNotice)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("SimpleFIN")
                } footer: {
                    Text("Enter the Setup Token here, not in chat. It is cleared after submission. The Access URL stays encrypted on the server and is never stored on this phone.")
                }

                Section {
                    Button("Log out", role: .destructive) {
                        app.signOut()
                        dismiss()
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .listStyle(.insetGrouped)
            .background(Theme.bg)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                name = app.member?.name ?? ""
                familyName = app.family?.name ?? ""
                server = app.serverURL
            }
            .task {
                integrations = try? await app.api.get("/v1/integrations")
                await loadSimpleFIN()
            }
            .alert(codePurpose, isPresented: $showCode) {
                Button("Copy") { if let code { Pasteboard.copy(code) } }
                Button("OK", role: .cancel) {}
            } message: {
                Text(codePurpose == "Join code"
                    ? "\(code ?? "")\nShare it once. It expires in a day."
                    : "\(code ?? "")\nEnter this code in the Budget app within 10 minutes. It can only be used once.")
            }
            .confirmationDialog("Disconnect SimpleFIN?", isPresented: $showDisconnectConfirmation, titleVisibility: .visible) {
                Button("Disconnect", role: .destructive) {
                    Task { await disconnectSimpleFIN() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The saved server credential will be deleted. Previously imported transactions will remain in your budget.")
            }
        }
    }

    private func statusRow(_ title: String, on: Bool) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(on ? "Configured" : "Not configured")
                .foregroundStyle(on ? Theme.good : Theme.muted)
        }
    }

    private func loadSimpleFIN() async {
        simplefin = try? await app.api.get("/v1/simplefin/status")
    }

    private func connectSimpleFIN() async {
        let token = setupToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }
        setupToken = ""
        simplefinBusy = true
        simplefinNotice = nil
        defer { simplefinBusy = false }
        do {
            let result: SimpleFINConnectResult = try await app.api.post(
                "/v1/simplefin/connect",
                body: SimpleFINConnectBody(setupToken: token)
            )
            simplefinNotice = result.message
            await loadSimpleFIN()
            await syncSimpleFIN()
        } catch {
            simplefinNotice = error.localizedDescription
        }
    }

    private func syncSimpleFIN() async {
        simplefinBusy = true
        simplefinNotice = nil
        defer { simplefinBusy = false }
        do {
            let result: SimpleFINSyncResult = try await app.api.post("/v1/simplefin/sync")
            simplefinNotice = "Imported \(result.imported) new transactions; skipped \(result.skipped) duplicates."
            await loadSimpleFIN()
            await app.refreshAll(silent: true)
        } catch {
            simplefinNotice = error.localizedDescription
            await loadSimpleFIN()
        }
    }

    private func disconnectSimpleFIN() async {
        simplefinBusy = true
        simplefinNotice = nil
        defer { simplefinBusy = false }
        do {
            let _: JSONAck = try await app.api.delete("/v1/simplefin/connection")
            simplefinNotice = "SimpleFIN disconnected. Existing transactions are unchanged."
            await loadSimpleFIN()
        } catch {
            simplefinNotice = error.localizedDescription
        }
    }
}
