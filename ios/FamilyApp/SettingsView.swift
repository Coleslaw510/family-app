import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var familyName = ""
    @State private var server = ""
    @State private var code: String?
    @State private var showCode = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    LabeledInput(title: "Your name", text: $name, autocap: .words)
                    LabeledInput(title: "Family name", text: $familyName, autocap: .words)
                    PrimaryButton(title: "Save names") {
                        Task { await app.saveProfile(name: name, familyName: familyName) }
                    }
                    LabeledInput(title: "Server", text: $server, keyboard: .URL, autocap: .never)
                    Text("Changing the server signs you out. The app is built for \(AppConfig.defaultServer).")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.muted)
                    OutlineButton(title: "Use this server", system: "link") {
                        app.updateServer(server)
                    }
                    OutlineButton(title: "New join code", system: "person.badge.plus") {
                        Task {
                            if let fresh = await app.newJoinCode() {
                                code = fresh
                                showCode = true
                            }
                        }
                    }
                    Text("Join codes expire in 24 hours and can be used once.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.muted)
                    Button("Log out") { app.signOut(); dismiss() }
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.bad)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .padding(16)
            }
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
            .alert("Join code", isPresented: $showCode) {
                Button("Copy") { if let code { Pasteboard.copy(code) } }
                Button("OK", role: .cancel) {}
            } message: {
                Text("\(code ?? "")\nShare it once. It expires in a day.")
            }
        }
    }
}
