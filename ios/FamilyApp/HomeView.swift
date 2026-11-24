import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var app: AppModel
    @State private var settings = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                budgetSummary
                comingUp
                quickAccess
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 28)
        }
        .background(Theme.bg)
        .refreshable { await app.pullToRefresh() }
        .sheet(isPresented: $settings) { SettingsView() }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(Dates.greeting(name: app.member?.name ?? "there"))
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                HStack(spacing: 6) {
                    Text(app.family?.name ?? "Your family")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.muted)
                    Text("·").foregroundStyle(Theme.soft)
                    Text(Dates.synced(app.lastSynced))
                        .font(.caption)
                        .foregroundStyle(Theme.soft)
                }
                .lineLimit(1)
            }
            Spacer(minLength: 8)
            GearButton { settings = true }
        }
        .padding(.bottom, 2)
    }

    private var budgetSummary: some View {
        let budget = app.dashboard?.budget
        let spent = budget?.spentCents ?? 0
        let total = budget?.budgetCents ?? 0
        let remaining = budget?.remainingCents ?? 0
        let progress = total > 0 ? min(max(Double(spent) / Double(total), 0), 1) : 0
        let status = remaining >= 0
            ? "\(Money.format(remaining)) remaining"
            : "Over by \(Money.format(abs(remaining)))"

        return Button { app.tab = .budget } label: {
            Card(padding: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "chart.pie.fill")
                            .foregroundStyle(Theme.accent)
                        Text("Monthly budget")
                            .font(.headline)
                            .foregroundStyle(Theme.text)
                        Spacer()
                        Text("Open budget")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.accent2)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.soft)
                    }
                    if total > 0 {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(Money.format(spent))
                                .font(.title2.weight(.bold))
                                .tracking(-0.4)
                                .foregroundStyle(Theme.text)
                            Text("spent of \(Money.format(total))")
                                .font(.subheadline)
                                .foregroundStyle(Theme.muted)
                            Spacer(minLength: 4)
                        }
                        ProgressView(value: progress)
                            .tint(remaining < 0 ? Theme.bad : Theme.accent)
                        Text(status)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(remaining < 0 ? Theme.bad : Theme.good)
                    } else {
                        Text("Set up monthly budgets, review transactions, and fix categories.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.muted)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens your budget and transactions")
    }

    private var comingUp: some View {
        let nextEvent = app.dashboard?.events.first
        let chores = upcomingChores
        return Card(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Coming up")
                        .font(.headline)
                        .foregroundStyle(Theme.text)
                    Spacer()
                    Text(Dates.longDay(Date()))
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 4)

                HomeLinkRow(
                    symbol: "calendar",
                    tint: Theme.calendar,
                    title: "Calendar",
                    detail: nextEvent.map {
                        "\($0.title) · \($0.allDay ? "All day" : Dates.timeLabel($0.startsAt))"
                    } ?? "Nothing scheduled",
                    badge: nextEvent.map { Dates.whenChip($0.startsAt).label }
                ) { app.tab = .calendar }

                if !chores.isEmpty {
                    Divider().padding(.leading, 16)
                    Text("Chores due within 7 days")
                        .font(.headline)
                        .foregroundStyle(Theme.text)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 2)
                    ForEach(chores.prefix(4)) { chore in
                        UpcomingChoreRow(chore: chore) {
                            Task { await app.toggleChore(id: chore.id, done: true, expectedDueOn: chore.dueOn) }
                        } open: {
                            app.tab = .family
                        }
                    }
                    if chores.count > 4 {
                        Button("See all upcoming chores") { app.tab = .family }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.accent2)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                    }
                }
            }
        }
    }

    private var upcomingChores: [Chore] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let limit = calendar.date(byAdding: .day, value: 7, to: today) ?? today
        return (app.household?.chores ?? [])
            .filter { chore in
                guard !chore.done, let due = chore.dueOn, let date = Dates.parseDay(due) else { return false }
                return calendar.startOfDay(for: date) <= limit
            }
            .sorted { ($0.dueOn ?? "9999") < ($1.dueOn ?? "9999") }
    }

    private var quickAccess: some View {
        Card(padding: 0) {
            VStack(spacing: 0) {
                HStack {
                    Text("Your family")
                        .font(.headline)
                        .foregroundStyle(Theme.text)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 15)
                .padding(.bottom, 2)
                HomeLinkRow(
                    symbol: "person.2",
                    tint: Theme.family,
                    title: "Family board",
                    detail: "Chores, groceries, notes, and important dates"
                ) { app.tab = .family }
                Divider().padding(.leading, 58)
                HomeLinkRow(
                    symbol: "heart",
                    tint: Theme.marriage,
                    title: "Marriage",
                    detail: app.dashboard?.nextDate?.title ?? "Check in and plan time together"
                ) {
                    app.moreSection = .marriage
                    app.tab = .more
                }
                Divider().padding(.leading, 58)
                HomeLinkRow(
                    symbol: "fork.knife",
                    tint: Theme.good,
                    title: "Food",
                    detail: app.food.map { "\($0.entries.count) items logged today" } ?? "Meals and nutrition"
                ) {
                    app.moreSection = .food
                    app.tab = .more
                }
                Divider().padding(.leading, 58)
                HomeLinkRow(
                    symbol: "paperplane",
                    tint: Theme.vacation,
                    title: "Vacations",
                    detail: app.trips.first.map { $0.destination ?? $0.name } ?? "Trips, plans, and packing"
                ) {
                    app.moreSection = .vacations
                    app.tab = .more
                }
            }
        }
    }
}

private struct UpcomingChoreRow: View {
    var chore: Chore
    var complete: () -> Void
    var open: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: complete) {
                CheckBox(done: false, color: Theme.family)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button(action: open) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(chore.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.text)
                    HStack(spacing: 6) {
                        Text(chore.assigneeName ?? "Anyone")
                        if let due = chore.dueOn { Text("· \(dueLabel(due))") }
                        if let recurrence = chore.recurrence, recurrence != "none" {
                            Text("· \(recurrence.capitalized)")
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.soft)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func dueLabel(_ value: String) -> String {
        guard let days = Dates.daysUntil(value) else { return Dates.shortDay(value) }
        if days < 0 { return "Overdue" }
        if days == 0 { return "Today" }
        if days == 1 { return "Tomorrow" }
        return Dates.shortDay(value)
    }
}

private struct HomeLinkRow: View {
    var symbol: String
    var tint: Color
    var title: String
    var detail: String
    var badge: String? = nil
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.text)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                        .lineLimit(2)
                }
                Spacer(minLength: 4)
                if let badge {
                    Text(badge)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tint)
                        .lineLimit(1)
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.soft)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the \(title) section")
    }
}

struct CheckBox: View {
    var done: Bool
    var color: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(done ? color : Color(hex: 0xCBD5E1), lineWidth: 1.5)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(done ? color : Theme.surface)
                )
            if done {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 16, height: 16)
    }
}
