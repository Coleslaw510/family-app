import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var app: AppModel
    @State private var server: String = ""
    @State private var name = ""
    @State private var familyName = ""
    @State private var code = ""
    @State private var mode: Mode = .choose
    @State private var joinCode = ""
    @State private var working = false
    @State private var error: String?

    private enum Mode {
        case choose
        case create
        case join
        case reveal
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Family App")
                        .font(.system(size: 32, weight: .heavy))
                        .tracking(-0.7)
                        .foregroundStyle(Theme.text)
                    Text("A private place for the two of you. Budget, dates, chores, and the next trip.")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 24)

                if mode == .reveal {
                    reveal
                } else {
                    form
                }
                if let error {
                    Text(error)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.bad)
                }
            }
            .padding(20)
        }
        .background(Theme.bg)
        .onAppear {
            if server.isEmpty { server = app.serverURL }
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 14) {
            Card {
                VStack(alignment: .leading, spacing: 14) {
                    LabeledInput(title: "Server", text: $server, keyboard: .URL, autocap: .never)
                    LabeledInput(title: "Your name", text: $name, autocap: .words)
                    if mode == .create {
                        LabeledInput(title: "Family name", text: $familyName, autocap: .words)
                    }
                    if mode == .join {
                        LabeledInput(title: "Join code", text: $code, autocap: .characters)
                    }
                }
            }
            if mode == .choose {
                PrimaryButton(title: "Create family", system: "plus") { beginCreate() }
                OutlineButton(title: "Join with a code", system: "person.badge.plus") { mode = .join }
            } else if mode == .create {
                PrimaryButton(title: working ? "Creating…" : "Create family") { Task { await create() } }
                    .disabled(working)
                Button("Back") { mode = .choose; error = nil }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.muted)
            } else {
                PrimaryButton(title: working ? "Joining…" : "Join family") { Task { await join() } }
                    .disabled(working)
                Button("Back") { mode = .choose; error = nil }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.muted)
            }
            Text("The join code is single-use and expires in a day. Only people with a code can see your family.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.soft)
        }
    }

    private var reveal: some View {
        VStack(alignment: .leading, spacing: 14) {
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    Kicker(text: "Join code")
                    Text(joinCode)
                        .font(.system(size: 40, weight: .heavy))
                        .tracking(4)
                        .foregroundStyle(Theme.navy)
                        .textSelection(.enabled)
                    Text("Share this once with your partner. It expires in 24 hours and works a single time.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.muted)
                }
            }
            OutlineButton(title: "Copy code", system: "doc.on.doc") {
                Pasteboard.copy(joinCode)
                error = nil
            }
            PrimaryButton(title: "Continue") {
                Task { await app.finishOnboarding() }
            }
        }
    }

    private func beginCreate() {
        error = nil
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            error = "Add your name first."
            return
        }
        if familyName.trimmingCharacters(in: .whitespaces).isEmpty {
            familyName = "\(trimmed.split(separator: " ").first.map(String.init) ?? trimmed)'s family"
        }
        mode = .create
    }

    private func create() async {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { error = "Add your name."; return }
        working = true
        defer { working = false }
        app.serverURL = server
        do {
            joinCode = try await app.createFamily(name: trimmed, familyName: familyName.trimmingCharacters(in: .whitespaces))
            Haptics.success()
            mode = .reveal
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func join() async {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let join = code.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { error = "Add your name."; return }
        guard join.count >= 4 else { error = "Enter the join code."; return }
        working = true
        defer { working = false }
        app.serverURL = server
        do {
            try await app.join(name: trimmed, code: join)
            Haptics.success()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
