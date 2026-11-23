import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var familyName = ""
    @State private var server = ""
    @State private var code: String?
    @State private var showCode = false
    @State private var integrations: IntegrationsStatus?

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
            }
            .alert("Join code", isPresented: $showCode) {
                Button("Copy") { if let code { Pasteboard.copy(code) } }
                Button("OK", role: .cancel) {}
            } message: {
                Text("\(code ?? "")\nShare it once. It expires in a day.")
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
}
