import SwiftUI

private enum FamilySheet: Identifiable {
    case settings, chore, grocery, note, date
    var id: String {
        switch self {
        case .settings: return "settings"
        case .chore: return "chore"
        case .grocery: return "grocery"
        case .note: return "note"
        case .date: return "date"
        }
    }
}

struct FamilyBoardView: View {
    @EnvironmentObject private var app: AppModel
    @State private var section = 0
    @State private var sheet: FamilySheet?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Family")
                        .font(.system(size: 28, weight: .heavy))
                        .tracking(-0.6)
                    Spacer()
                    GearButton { sheet = .settings }
                }
                Picker("Section", selection: $section) {
                    Text("Chores").tag(0)
                    Text("Grocery").tag(1)
                    Text("Notes").tag(2)
                    Text("Dates").tag(3)
                }
                .pickerStyle(.segmented)
                switch section {
                case 1: grocery
                case 2: notes
                case 3: dates
                default: chores
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Theme.bg)
        .refreshable { await app.pullToRefresh() }
        .sheet(item: $sheet) { item in
            Group {
                switch item {
                case .settings: SettingsView()
                case .chore: ChoreEditor()
                case .grocery: QuickNoteEditor(kind: "grocery", title: "Grocery item")
                case .note: QuickNoteEditor(kind: "note", title: "Shared note")
                case .date: ImportantDateEditor()
                }
            }
        }
    }

    private var chores: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                header("Chores", "checklist", Theme.familyGradient) { sheet = .chore }
                let items = app.household?.chores ?? []
                if items.isEmpty {
                    Text("Add a chore and who it's for.")
                        .foregroundStyle(Theme.muted)
                }
                ForEach(items) { chore in
                    HStack(spacing: 8) {
                        Button { Task { await app.toggleChore(id: chore.id, done: !chore.done) } } label: {
                            CheckBox(done: chore.done, color: Theme.family)
                        }
                        .buttonStyle(.plain)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(chore.title)
                                .font(.system(size: 14, weight: .semibold))
                                .strikethrough(chore.done)
                            Text(chore.assigneeName ?? "Anyone")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        Button { Task { await delete("/v1/chores/\(chore.id)") } } label: {
                            Image(systemName: "trash").foregroundStyle(Theme.soft)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var grocery: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                header("Grocery list", "cart", Theme.incomeGradient) { sheet = .grocery }
                let items = (app.household?.notes ?? []).filter { $0.kind == "grocery" }
                if items.isEmpty { Text("The list is empty.").foregroundStyle(Theme.muted) }
                ForEach(items) { item in
                    HStack {
                        Button { Task { await app.toggleGrocery(id: item.id, done: !item.done) } } label: {
                            CheckBox(done: item.done, color: Theme.family)
                        }
                        .buttonStyle(.plain)
                        Text(item.body)
                            .strikethrough(item.done)
                            .foregroundStyle(item.done ? Theme.muted : Theme.text)
                        Spacer()
                        Button { Task { await delete("/v1/notes/\(item.id)") } } label: {
                            Image(systemName: "trash").foregroundStyle(Theme.soft)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var notes: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                header("Shared notes", "note.text", Theme.budgetGradient) { sheet = .note }
                let items = (app.household?.notes ?? []).filter { $0.kind == "note" }
                if items.isEmpty { Text("Leave a note the whole house can see.").foregroundStyle(Theme.muted) }
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(item.body).font(.system(size: 15, weight: .medium))
                            Spacer()
                            Button { Task { await delete("/v1/notes/\(item.id)") } } label: {
                                Image(systemName: "trash").foregroundStyle(Theme.soft)
                            }
                            .buttonStyle(.plain)
                        }
                        Text(item.authorName ?? "")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.muted)
                    }
                }
            }
        }
    }

    private var dates: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                header("Important dates", "calendar", Theme.calendarGradient) { sheet = .date }
                let items = app.household?.importantDates ?? []
                if items.isEmpty { Text("Passports, school events, visits.").foregroundStyle(Theme.muted) }
                ForEach(items) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title).font(.system(size: 14, weight: .bold))
                            Text(Dates.shortDay(item.dateOn) + (item.repeatsYearly ? " · yearly" : ""))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        Button { Task { await delete("/v1/important-dates/\(item.id)") } } label: {
                            Image(systemName: "trash").foregroundStyle(Theme.soft)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func header(_ title: String, _ icon: String, _ colors: [Color], add: @escaping () -> Void) -> some View {
        HStack {
            IconTile(system: icon, colors: colors)
            Text(title).font(.system(size: 15, weight: .bold))
            Spacer()
            TintedIconButton(system: "plus", title: "Add \(title)", action: add)
        }
    }

    private func delete(_ path: String) async {
        do {
            let _: JSONAck = try await app.api.delete(path)
            await app.refreshAll(silent: true)
        } catch {
            app.report(error)
        }
    }
}

struct ChoreEditor: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var assignee = ""
    @State private var error: String?

    var body: some View {
        EditorChrome(title: "Chore", working: false, error: error, onSave: { Task { await save() } }) {
            LabeledInput(title: "What", text: $title, autocap: .sentences)
            Picker("Who", selection: $assignee) {
                Text("Anyone").tag("")
                ForEach(app.members) { member in
                    Text(member.name).tag(member.id)
                }
            }
        }
    }

    private func save() async {
        do {
            let _: JSONAck = try await app.api.post(
                "/v1/chores",
                body: ChoreBody(title: title, assigneeId: assignee.isEmpty ? nil : assignee, dueOn: nil)
            )
            await app.refreshAll(silent: true)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct QuickNoteEditor: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    var kind: String
    var title: String
    @State private var text = ""
    @State private var error: String?

    var body: some View {
        EditorChrome(title: title, working: false, error: error, onSave: { Task { await save() } }) {
            LabeledInput(title: title, text: $text, autocap: .sentences)
        }
    }

    private func save() async {
        do {
            let _: JSONAck = try await app.api.post("/v1/notes", body: NoteBody(body: text, kind: kind))
            await app.refreshAll(silent: true)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct ImportantDateEditor: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var day = Date()
    @State private var yearly = false
    @State private var notes = ""
    @State private var error: String?

    var body: some View {
        EditorChrome(title: "Important date", working: false, error: error, onSave: { Task { await save() } }) {
            LabeledInput(title: "What", text: $title, autocap: .words)
            DatePicker("Date", selection: $day, displayedComponents: .date)
            Toggle("Repeats every year", isOn: $yearly)
            LabeledInput(title: "Notes", text: $notes)
        }
    }

    private func save() async {
        do {
            let _: JSONAck = try await app.api.post(
                "/v1/important-dates",
                body: ImportantBody(title: title, dateOn: Dates.isoDay(day), repeatsYearly: yearly, notes: notes)
            )
            await app.refreshAll(silent: true)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
