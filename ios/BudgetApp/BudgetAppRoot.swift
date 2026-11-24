import SwiftUI

@main
struct BudgetAppEntry: App {
    @StateObject private var app = AppModel(
        keychainService: "com.colemcclintock.budgetapp",
        budgetOnly: true
    )

    var body: some Scene {
        WindowGroup {
            BudgetAppRootView()
                .environmentObject(app)
                .tint(Theme.accent)
        }
    }
}

private struct BudgetAppRootView: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            switch app.phase {
            case .loading:
                ProgressView().tint(Theme.accent)
            case .signedOut:
                BudgetPairingView()
            case .ready:
                BudgetView()
                    .overlay(alignment: .top) {
                        if let banner = app.banner {
                            BannerToast(text: banner) { app.banner = nil }
                                .padding(.top, 4)
                        }
                    }
            }
        }
        .task { await app.bootstrap() }
    }
}

private struct BudgetPairingView: View {
    @EnvironmentObject private var app: AppModel
    @State private var code = ""
    @State private var working = false
    @State private var error: String?

    private var normalizedCode: String {
        code.uppercased().filter { $0.isLetter || $0.isNumber }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("Your budget, in its own app", systemImage: "creditcard")
                        .font(.headline)
                    Text("The Budget app uses the same family server as Family App. Your budget data stays on that server.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Section("Pair this app") {
                    Text("In Family App, open Settings → Budget app → Generate pairing code. Enter the one-time code here within 10 minutes.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    TextField("12-character pairing code", text: $code)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.system(.title3, design: .monospaced).weight(.semibold))
                        .onChange(of: code) { newValue in
                            code = String(newValue.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(12))
                        }
                    Button {
                        Task { await pair() }
                    } label: {
                        HStack {
                            Spacer()
                            if working { ProgressView().padding(.trailing, 8) }
                            Text(working ? "Pairing…" : "Pair Budget app")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .disabled(working || normalizedCode.count != 12)
                }
                if let error {
                    Section { Text(error).font(.footnote).foregroundStyle(.red) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle("Budget")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    private func pair() async {
        working = true
        error = nil
        defer { working = false }
        do {
            try await app.pairBudgetApp(code: normalizedCode)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
