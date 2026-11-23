import SwiftUI

private enum CalendarSheet: Identifiable {
    case settings
    case feeds
    case event(FamilyEvent)

    var id: String {
        switch self {
        case .settings: return "settings"
        case .feeds: return "feeds"
        case .event(let event): return "event-\(event.id)-\(event.startsAt)-\(event.title)"
        }
    }
}

struct CalendarView: View {
    @EnvironmentObject private var app: AppModel
    @State private var visible = Date()
    @State private var selected = Date()
    @State private var sheet: CalendarSheet?

    private let colors = ["#4285F4", "#E67C73", "#33B679", "#7C3AED", "#EA580C"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Calendar")
                        .font(.system(size: 28, weight: .heavy))
                        .tracking(-0.6)
                    Spacer()
                    GearButton { sheet = .settings }
                    TintedIconButton(system: "dot.radiowaves.left.and.right", title: "Calendar feeds", tint: Theme.muted) { sheet = .feeds }
                }
                Card {
                    HStack(spacing: 8) {
                        Circle().fill(Color(hex: 0x4285F4)).frame(width: 8, height: 8)
                        Text("Google Calendar sync coming in 1.1")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.muted)
                    }
                }
                Card {
                    VStack(spacing: 10) {
                        HStack {
                            TintedIconButton(system: "chevron.left", title: "Previous month") { shift(-1) }
                            Spacer()
                            Text(Dates.prettyMonth(Dates.monthKey(visible)))
                                .font(.system(size: 16, weight: .bold))
                            Spacer()
                            TintedIconButton(system: "chevron.right", title: "Next month") { shift(1) }
                        }
                        .foregroundStyle(Theme.text)
                        weekdayHeader
                        let cells = grid(for: visible)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
                            ForEach(Array(cells.enumerated()), id: \.offset) { _, date in
                                dayCell(date)
                            }
                        }
                    }
                }
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(Dates.longDay(selected))
                                .font(.system(size: 15, weight: .bold))
                            Spacer()
                            TintedIconButton(system: "plus", title: "Add event") { sheet = .event(blankEvent()) }
                        }
                        let dayEvents = events(on: selected)
                        if dayEvents.isEmpty {
                            Text("Nothing this day.")
                                .foregroundStyle(Theme.muted)
                        }
                        ForEach(dayEvents) { event in
                            Button { if event.readOnly != true { sheet = .event(event) } } label: {
                                HStack(spacing: 8) {
                                    Circle().fill(Color(hexString: event.color)).frame(width: 8, height: 8)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(event.title).font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.text)
                                        Text(event.allDay ? "All day" : Dates.timeLabel(event.startsAt))
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(Theme.muted)
                                    }
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
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
                case .settings:
                    SettingsView()
                case .feeds:
                    CalendarFeedsView()
                case .event(let event):
                    EventEditor(existing: event)
                }
            }
        }
    }

    private var weekdayHeader: some View {
        let symbols = ["S", "M", "T", "W", "T", "F", "S"]
        return HStack {
            ForEach(Array(symbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.soft)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func dayCell(_ date: Date?) -> some View {
        Group {
            if let date {
                let dayEvents = events(on: date)
                let isSelected = Calendar.current.isDate(date, inSameDayAs: selected)
                let isToday = Calendar.current.isDateInToday(date)
                Button { selected = date } label: {
                    VStack(spacing: 3) {
                        Text("\(Calendar.current.component(.day, from: date))")
                            .font(.system(size: 13, weight: isToday ? .heavy : .medium))
                            .foregroundStyle(isSelected ? Color.white : Theme.text)
                            .frame(width: 28, height: 28)
                            .background(isSelected ? Theme.accent : Color.clear, in: Circle())
                        Circle()
                            .fill(dayEvents.first.map { Color(hexString: $0.color) } ?? Color.clear)
                            .frame(width: 5, height: 5)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            } else {
                Color.clear.frame(height: 36)
            }
        }
    }

    private func events(on day: Date) -> [FamilyEvent] {
        app.events.filter { event in
            guard let date = Dates.parseDateTime(event.startsAt) else { return false }
            return Calendar.current.isDate(date, inSameDayAs: day)
        }
    }

    private func grid(for month: Date) -> [Date?] {
        let cal = Calendar.current
        guard let start = cal.date(from: cal.dateComponents([.year, .month], from: month)),
              let range = cal.range(of: .day, in: .month, for: start) else { return [] }
        let weekday = cal.component(.weekday, from: start)
        var cells: [Date?] = Array(repeating: nil, count: max(weekday - 1, 0))
        for day in range {
            cells.append(cal.date(byAdding: .day, value: day - 1, to: start))
        }
        while cells.count % 7 != 0 { cells.append(nil) }
        return cells
    }

    private func shift(_ delta: Int) {
        if let next = Calendar.current.date(byAdding: .month, value: delta, to: visible) {
            visible = next
            selected = next
        }
    }

    private func blankEvent() -> FamilyEvent {
        FamilyEvent(
            id: "",
            title: "",
            startsAt: Dates.combine(day: selected, time: Calendar.current.date(bySettingHour: 18, minute: 30, second: 0, of: selected) ?? selected),
            endsAt: nil,
            allDay: false,
            location: nil,
            notes: nil,
            color: colors[0],
            createdBy: nil
        )
    }
}

struct EventEditor: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    var existing: FamilyEvent
    @State private var title = ""
    @State private var day = Date()
    @State private var time = Date()
    @State private var allDay = false
    @State private var location = ""
    @State private var notes = ""
    @State private var color = "#4285F4"
    @State private var error: String?
    private let colors = ["#4285F4", "#E67C73", "#33B679", "#7C3AED", "#EA580C"]

    var body: some View {
        EditorChrome(title: existing.id.isEmpty ? "New event" : "Edit event", working: false, error: error, onSave: { Task { await save() } }) {
            LabeledInput(title: "Title", text: $title, autocap: .sentences)
            Toggle("All day", isOn: $allDay)
            DatePicker("Day", selection: $day, displayedComponents: .date)
            if !allDay {
                DatePicker("Starts", selection: $time, displayedComponents: .hourAndMinute)
            }
            LabeledInput(title: "Place", text: $location, autocap: .words)
            LabeledInput(title: "Notes", text: $notes)
            HStack(spacing: 10) {
                ForEach(colors, id: \.self) { item in
                    Button { color = item } label: {
                        Circle()
                            .fill(Color(hexString: item))
                            .frame(width: 26, height: 26)
                            .overlay(Circle().stroke(Color.white, lineWidth: color == item ? 3 : 0))
                            .shadow(color: color == item ? Color(hexString: item).opacity(0.4) : .clear, radius: 3)
                    }
                    .buttonStyle(.plain)
                }
            }
            if !existing.id.isEmpty {
                Button("Delete event", role: .destructive) { Task { await remove() } }
            }
        }
        .onAppear {
            title = existing.title
            allDay = existing.allDay
            color = existing.color
            location = existing.location ?? ""
            notes = existing.notes ?? ""
            if let date = Dates.parseDateTime(existing.startsAt) {
                day = date
                time = date
            }
        }
    }

    private func save() async {
        let starts = allDay ? Dates.isoDay(day) : Dates.combine(day: day, time: time)
        let body = EventBody(
            title: title,
            startsAt: starts,
            endsAt: nil,
            allDay: allDay,
            location: location,
            notes: notes,
            color: color
        )
        do {
            if existing.id.isEmpty {
                let _: JSONAck = try await app.api.post("/v1/events", body: body)
            } else {
                let _: JSONAck = try await app.api.patch("/v1/events/\(existing.id)", body: body)
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
            let _: JSONAck = try await app.api.delete("/v1/events/\(existing.id)")
            await app.refreshAll(silent: true)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
