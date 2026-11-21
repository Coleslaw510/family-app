import SwiftUI

private enum MarriageSheet: Identifiable {
    case settings
    case dates
    case birthday
    case love
    case night(DateNight)

    var id: String {
        switch self {
        case .settings: return "settings"
        case .dates: return "dates"
        case .birthday: return "birthday"
        case .love: return "love"
        case .night(let date): return "night-\(date.id)-\(date.startsAt)"
        }
    }
}

struct MarriageView: View {
    @EnvironmentObject private var app: AppModel
    @State private var sheet: MarriageSheet?
    @State private var connection = 4
    @State private var appreciation = 4
    @State private var fun = 4
    @State private var checkinNote = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Marriage")
                        .font(.system(size: 28, weight: .heavy))
                        .tracking(-0.6)
                    Spacer()
                    GearButton { sheet = .settings }
                }
                anniversaryCard
                firstDateCard
                birthdaysCard
                flowersCard
                datesCard
                checkinCard
                notesCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Theme.bg)
        .refreshable { await app.refreshAll() }
        .sheet(item: $sheet) { item in
            Group {
                switch item {
                case .settings: SettingsView()
                case .dates: DatesEditor()
                case .birthday: BirthdayEditor()
                case .love: LoveNoteEditor()
                case .night(let date): DateNightEditor(existing: date)
                }
            }
        }
        .onAppear {
            if app.openLoveNote {
                sheet = .love
                app.openLoveNote = false
            }
        }
    }

    private var anniversaryCard: some View {
        let date = app.marriage?.anniversaryDate ?? app.family?.anniversaryDate
        let days = date.flatMap { Dates.nextAnnualDays(from: $0) }
        return Card {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    IconTile(system: "heart", colors: Theme.marriageGradient)
                    Text("Anniversary")
                        .font(.system(size: 15, weight: .bold))
                    Spacer()
                    Button("Edit") { sheet = .dates }
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.accent2)
                }
                if let days {
                    Text("\(days)")
                        .font(.system(size: 40, weight: .heavy))
                        .foregroundStyle(Theme.marriage)
                    Text("days until the next one")
                        .foregroundStyle(Theme.muted)
                    if let years = date.flatMap({ Dates.yearsSince($0) }) {
                        Text("\(years) years together")
                            .font(.system(size: 13, weight: .semibold))
                    }
                } else {
                    Text("Add the day you got married.")
                        .foregroundStyle(Theme.muted)
                }
            }
        }
    }

    private var firstDateCard: some View {
        let date = app.marriage?.firstDate ?? app.family?.firstDate
        let days = date.flatMap { Dates.nextAnnualDays(from: $0) }
        return Card {
            VStack(alignment: .leading, spacing: 4) {
                Kicker(text: "Date-aversary")
                Text(date == nil ? "Add the anniversary of your first date" : "\(days ?? 0) days")
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(Theme.text)
                if let date {
                    Text("First date \(Dates.shortDay(date))")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.muted)
                }
            }
        }
    }

    private var birthdaysCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    IconTile(system: "gift", colors: Theme.calendarGradient)
                    Text("Birthdays")
                        .font(.system(size: 15, weight: .bold))
                    Spacer()
                    Button { sheet = .birthday } label: {
                        Image(systemName: "plus").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.accent2)
                    }
                    .buttonStyle(.plain)
                }
                let birthdays = (app.marriage?.birthdays ?? []).sorted {
                    (Dates.daysUntilMonthDay(month: $0.month, day: $0.day) ?? 999) <
                    (Dates.daysUntilMonthDay(month: $1.month, day: $1.day) ?? 999)
                }
                if birthdays.isEmpty {
                    Text("Add both of you, and anyone else in the family.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.muted)
                }
                ForEach(birthdays) { birthday in
                    HStack {
                        Text(birthday.name).font(.system(size: 14, weight: .bold))
                        Spacer()
                        Text("\(Dates.daysUntilMonthDay(month: birthday.month, day: birthday.day) ?? 0) days")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.muted)
                        Button { Task { await deleteBirthday(birthday) } } label: {
                            Image(systemName: "trash").foregroundStyle(Theme.soft)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var flowersCard: some View {
        let flowers = app.marriage?.flowers
        let last = flowers?.logs.first
        let days = last.flatMap { Dates.daysSince($0.boughtOn) }
        let nudgeAfter = flowers?.nudgeAfterDays ?? 14
        let nudge = days == nil || (days ?? 0) >= nudgeAfter
        return Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    IconTile(system: "leaf", colors: Theme.incomeGradient)
                    Text("Flowers")
                        .font(.system(size: 15, weight: .bold))
                }
                if let days, let last {
                    Text("\(days) days since you bought flowers")
                        .font(.system(size: 16, weight: .bold))
                    Text(Dates.shortDay(last.boughtOn))
                        .foregroundStyle(Theme.muted)
                } else {
                    Text("You haven't logged flowers yet.")
                        .font(.system(size: 15, weight: .semibold))
                }
                if nudge {
                    Text(days == nil ? "A small bouquet is an easy win." : "It's been a while. A gentle nudge, only for you.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.insightText)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.insightBg, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                Text("Only you see this reminder.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.soft)
                PrimaryButton(title: "I bought flowers", system: "leaf") {
                    Task { await logFlowers() }
                }
            }
        }
    }

    private var datesCard: some View {
        let dates = app.marriage?.dates ?? []
        let today = Dates.isoDay(Date())
        let upcoming = dates.filter { $0.startsAt >= today }.sorted { $0.startsAt < $1.startsAt }
        let past = dates.filter { $0.startsAt < today }
        return Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    IconTile(system: "heart", colors: Theme.marriageGradient)
                    Text("Date nights")
                        .font(.system(size: 15, weight: .bold))
                    Spacer()
                    Button { sheet = .night(blankDate()) } label: {
                        Image(systemName: "plus").foregroundStyle(Theme.accent2)
                    }
                    .buttonStyle(.plain)
                }
                if let last = past.first {
                    Kicker(text: "Last date")
                    Text(last.title).font(.system(size: 14, weight: .bold))
                    Text(Dates.prettyDateTime(last.startsAt))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.muted)
                }
                if upcoming.isEmpty {
                    Text("Nothing planned yet.")
                        .foregroundStyle(Theme.muted)
                }
                ForEach(upcoming) { date in
                    Button { sheet = .night(date) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(date.title).font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.text)
                            Text(Dates.prettyDateTime(date.startsAt))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Theme.muted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var checkinCard: some View {
        let week = Dates.monday()
        let mine = app.marriage?.checkins.first { $0.weekStart == week && $0.memberId == app.member?.id }
        return Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    IconTile(system: "bubble.left.and.bubble.right", colors: Theme.marriageGradient)
                    Text("Weekly check-in")
                        .font(.system(size: 15, weight: .bold))
                }
                Text("Week of \(Dates.shortDay(week))")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.muted)
                RatingRow(title: "How connected did you feel?", value: $connection)
                RatingRow(title: "How appreciated did you feel?", value: $appreciation)
                RatingRow(title: "How much fun did we have?", value: $fun)
                LabeledInput(title: "Carry into next week", text: $checkinNote)
                PrimaryButton(title: mine == nil ? "Save check-in" : "Update check-in") {
                    Task { await saveCheckin(week: week) }
                }
                let weeks = Array(Set((app.marriage?.checkins ?? []).map(\.weekStart))).sorted(by: >)
                if !weeks.isEmpty {
                    Kicker(text: "Shared history")
                    ForEach(weeks.prefix(6), id: \.self) { weekStart in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(Dates.shortDay(weekStart))
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Theme.muted)
                            ForEach((app.marriage?.checkins ?? []).filter { $0.weekStart == weekStart }) { item in
                                Text("\(item.memberName): \(item.connection)/\(item.appreciation)/\(item.fun)" + (item.note.map { " · \($0)" } ?? ""))
                                    .font(.system(size: 13, weight: .medium))
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            if let mine {
                connection = mine.connection
                appreciation = mine.appreciation
                fun = mine.fun
                checkinNote = mine.note ?? ""
            }
        }
    }

    private var notesCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    IconTile(system: "square.and.pencil", colors: Theme.marriageGradient)
                    Text("Love notes")
                        .font(.system(size: 15, weight: .bold))
                    Spacer()
                    Button { sheet = .love } label: {
                        Image(systemName: "plus").foregroundStyle(Theme.accent2)
                    }
                    .buttonStyle(.plain)
                }
                if (app.marriage?.loveNotes ?? []).isEmpty {
                    Text("Leave something kind for them to find.")
                        .foregroundStyle(Theme.muted)
                }
                ForEach(app.marriage?.loveNotes ?? []) { note in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(note.authorName).font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.marriage)
                            Spacer()
                            if note.authorId == app.member?.id {
                                Button { Task { await deleteNote(note) } } label: {
                                    Image(systemName: "trash").foregroundStyle(Theme.soft)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        Text(note.body).font(.system(size: 15, weight: .medium))
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func blankDate() -> DateNight {
        DateNight(id: "", title: "", startsAt: Dates.combine(day: Date(), time: Date()), location: nil, notes: nil, createdBy: nil)
    }

    private func logFlowers() async {
        do {
            let _: MarriageBundle = try await app.api.post("/v1/flowers", body: FlowerBody(boughtOn: Dates.isoDay(Date()), note: nil))
            Haptics.success()
            await app.refreshAll(silent: true)
        } catch {
            app.banner = error.localizedDescription
        }
    }

    private func saveCheckin(week: String) async {
        do {
            let _: JSONAck = try await app.api.post(
                "/v1/checkins",
                body: CheckinBody(weekStart: week, connection: connection, appreciation: appreciation, fun: fun, note: checkinNote)
            )
            app.celebration = Celebration(title: "Check-in saved")
            Haptics.success()
            await app.refreshAll(silent: true)
        } catch {
            app.banner = error.localizedDescription
        }
    }

    private func deleteBirthday(_ birthday: Birthday) async {
        do {
            let _: JSONAck = try await app.api.delete("/v1/birthdays/\(birthday.id)")
            await app.refreshAll(silent: true)
        } catch {
            app.banner = error.localizedDescription
        }
    }

    private func deleteNote(_ note: LoveNote) async {
        do {
            let _: JSONAck = try await app.api.delete("/v1/love-notes/\(note.id)")
            await app.refreshAll(silent: true)
        } catch {
            app.banner = error.localizedDescription
        }
    }
}

struct RatingRow: View {
    var title: String
    @Binding var value: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 13, weight: .semibold))
            HStack(spacing: 8) {
                ForEach(1..<6, id: \.self) { score in
                    Button { value = score } label: {
                        Text("\(score)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(score <= value ? Color.white : Theme.muted)
                            .frame(width: 28, height: 28)
                            .background(score <= value ? Theme.marriage : Theme.line2, in: Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct DatesEditor: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var anniversary = Date()
    @State private var hasAnniversary = false
    @State private var first = Date()
    @State private var hasFirst = false
    @State private var nudge = 14.0
    @State private var error: String?

    var body: some View {
        EditorChrome(title: "Important days", working: false, error: error, onSave: { Task { await save() } }) {
            Toggle("Anniversary", isOn: $hasAnniversary)
            if hasAnniversary { DatePicker("Anniversary", selection: $anniversary, displayedComponents: .date) }
            Toggle("First date", isOn: $hasFirst)
            if hasFirst { DatePicker("First date", selection: $first, displayedComponents: .date) }
            Stepper("Flower nudge after \(Int(nudge)) days", value: $nudge, in: 1.0...90.0)
        }
        .onAppear {
            if let value = app.marriage?.anniversaryDate, let date = Dates.parseDay(value) {
                anniversary = date
                hasAnniversary = true
            }
            if let value = app.marriage?.firstDate, let date = Dates.parseDay(value) {
                first = date
                hasFirst = true
            }
            nudge = Double(app.marriage?.flowerNudgeDays ?? 14)
        }
    }

    private func save() async {
        let body = MarriageBody(
            anniversaryDate: hasAnniversary ? Dates.isoDay(anniversary) : "",
            firstDate: hasFirst ? Dates.isoDay(first) : "",
            flowerNudgeDays: Int(nudge)
        )
        do {
            let _: MarriageBundle = try await app.api.put("/v1/marriage", body: body)
            await app.refreshAll(silent: true)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct BirthdayEditor: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var day = Date()
    @State private var error: String?

    var body: some View {
        EditorChrome(title: "Birthday", working: false, error: error, onSave: { Task { await save() } }) {
            LabeledInput(title: "Name", text: $name, autocap: .words)
            DatePicker("Birthday", selection: $day, displayedComponents: .date)
            Text("The year is kept, and the countdown uses the month and day.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.muted)
        }
    }

    private func save() async {
        let cal = Calendar.current
        let body = BirthdayBody(
            name: name,
            month: cal.component(.month, from: day),
            day: cal.component(.day, from: day),
            year: cal.component(.year, from: day)
        )
        do {
            let _: JSONAck = try await app.api.post("/v1/birthdays", body: body)
            await app.refreshAll(silent: true)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct DateNightEditor: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    var existing: DateNight
    @State private var title = ""
    @State private var day = Date()
    @State private var time = Date()
    @State private var location = ""
    @State private var notes = ""
    @State private var error: String?

    var body: some View {
        EditorChrome(title: existing.id.isEmpty ? "Plan a date" : "Edit date", working: false, error: error, onSave: { Task { await save() } }) {
            LabeledInput(title: "What", text: $title, autocap: .sentences)
            DatePicker("Day", selection: $day, displayedComponents: .date)
            DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
            LabeledInput(title: "Where", text: $location, autocap: .words)
            LabeledInput(title: "Notes", text: $notes)
            if !existing.id.isEmpty {
                Button("Delete date", role: .destructive) { Task { await remove() } }
            }
        }
        .onAppear {
            title = existing.title
            if let date = Dates.parseDateTime(existing.startsAt) {
                day = date
                time = date
            }
            location = existing.location ?? ""
            notes = existing.notes ?? ""
        }
    }

    private func save() async {
        let body = DateBody(
            title: title,
            startsAt: Dates.combine(day: day, time: time),
            location: location,
            notes: notes
        )
        do {
            if existing.id.isEmpty {
                let _: JSONAck = try await app.api.post("/v1/dates", body: body)
            } else {
                let _: JSONAck = try await app.api.patch("/v1/dates/\(existing.id)", body: body)
            }
            await app.refreshAll(silent: true)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func remove() async {
        guard !existing.id.isEmpty else { return }
        do {
            let _: JSONAck = try await app.api.delete("/v1/dates/\(existing.id)")
            await app.refreshAll(silent: true)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct LoveNoteEditor: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var error: String?

    var body: some View {
        EditorChrome(title: "Love note", saveTitle: "Send", working: false, error: error, onSave: { Task { await save() } }) {
            LabeledInput(title: "Note", text: $text)
        }
    }

    private func save() async {
        do {
            let _: JSONAck = try await app.api.post("/v1/love-notes", body: LoveBody(body: text))
            Haptics.success()
            await app.refreshAll(silent: true)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
