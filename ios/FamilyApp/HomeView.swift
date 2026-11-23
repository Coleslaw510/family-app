import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var app: AppModel
    @State private var settings = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                header
                budgetCard
                HStack(alignment: .top, spacing: 8) {
                    marriageCard
                    familyCard
                }
                calendarCard
                vacationCard
                mortgageHomeCard
                foodHomeCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 16)
        }
        .background(Theme.bg)
        .refreshable { await app.pullToRefresh() }
        .sheet(isPresented: $settings) { SettingsView() }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text(Dates.greeting(name: app.member?.name ?? "there"))
                    .font(.system(size: 22, weight: .bold))
                    .tracking(-0.5)
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                HStack(spacing: 8) {
                    Text(app.family?.name ?? "Your family")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.muted)
                    SyncPill(text: Dates.synced(app.lastSynced))
                }
            }
            Spacer(minLength: 8)
            Button { settings = true } label: {
                HStack(spacing: -10) {
                    ForEach(Array(app.members.prefix(3).enumerated()), id: \.element.id) { index, member in
                        Avatar(name: member.name, index: index)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
        .padding(.bottom, 2)
    }

    private var budgetCard: some View {
        let budget = app.dashboard?.budget
        let spent = budget?.spentCents ?? 0
        let total = budget?.budgetCents ?? 0
        let progress = total > 0 ? Double(spent) / Double(total) : 0
        let over = total > 0 && spent > total
        return Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    IconTile(system: "creditcard", colors: Theme.budgetGradient)
                    Text("Budget")
                        .font(.system(size: 15, weight: .bold))
                    Spacer()
                    PacePill(pace: budget?.pace ?? "no_budget")
                }
                HStack(spacing: 12) {
                    ZStack {
                        ProgressRing(progress: progress, color: over ? Theme.bad : Theme.accent)
                        VStack(spacing: 1) {
                            Text("\(Int((min(progress, 9.99) * 100).rounded()))%")
                                .font(.system(size: 16, weight: .heavy))
                                .tracking(-0.4)
                            Text("SPENT")
                                .font(.system(size: 9, weight: .bold))
                                .tracking(0.4)
                                .foregroundStyle(Theme.muted)
                        }
                    }
                    .frame(width: 74, height: 74)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Money.format(spent))
                            .font(.system(size: 20, weight: .heavy))
                            .tracking(-0.5)
                        Text(total > 0 ? "of \(Money.format(total)) \(budget?.monthLabel ?? "") budget" : "No budget set yet")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(Theme.muted)
                            .lineLimit(2)
                        Text(total > 0 ? "\(Money.format(max(budget?.remainingCents ?? 0, 0))) remaining" : "Tap Budget to set envelopes")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(total > 0 && (budget?.remainingCents ?? 0) < 0 ? Theme.bad : Theme.good)
                    }
                    Spacer(minLength: 0)
                }
                if let recent = budget?.recent, !recent.isEmpty {
                    Divider().overlay(Theme.line2)
                    HStack(spacing: 0) {
                        ForEach(Array(recent.prefix(3).enumerated()), id: \.element.id) { index, txn in
                            if index > 0 {
                                Rectangle().fill(Theme.line).frame(width: 1, height: 11).padding(.horizontal, 8)
                            }
                            HStack(spacing: 4) {
                                Text(txn.categoryName ?? txn.merchant)
                                    .foregroundStyle(Theme.muted)
                                    .lineLimit(1)
                                Text(Money.format(txn.amountCents))
                                    .foregroundStyle(Theme.text)
                            }
                            .font(.system(size: 12, weight: .semibold))
                        }
                        Spacer(minLength: 0)
                    }
                }
                if let insight = budget?.insight {
                    HStack(alignment: .top, spacing: 7) {
                        IconTile(system: "sparkles", colors: Theme.aiGradient, size: 18)
                        Text(insight.title)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(Theme.insightText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.insightBg, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .stroke(Theme.insightLine, lineWidth: 1)
                    )
                }
            }
        }
        .onTapGesture { app.tab = .budget }
        .accessibilityAction(named: Text("Open Budget")) { app.tab = .budget }
    }

    private var marriageCard: some View {
        let next = app.dashboard?.nextDate
        let anniversary = app.family?.anniversaryDate
        let days = anniversary.flatMap { Dates.nextAnnualDays(from: $0) }
        return Card(padding: 11) {
            VStack(alignment: .leading, spacing: 6) {
                Button { app.tab = .marriage } label: {
                    HStack(spacing: 6) {
                        IconTile(system: "heart", colors: Theme.marriageGradient)
                        Text("Marriage")
                            .font(.system(size: 15, weight: .bold))
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
                Kicker(text: next == nil ? "Date night" : "Next date night")
                Text(next?.title ?? "Plan a date")
                    .font(.system(size: 13.5, weight: .bold))
                    .lineLimit(2)
                Text(next.map { Dates.prettyDateTime($0.startsAt) } ?? "Nothing on the calendar")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(2)
                HStack {
                    Kicker(text: "Anniversary")
                    Spacer()
                    Text(days.map { "\($0) days" } ?? "Add")
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(Theme.marriage)
                }
                .padding(.top, 4)
                .overlay(alignment: .top) { Rectangle().fill(Theme.line2).frame(height: 1) }
                Button {
                    app.openLoveNote = true
                    app.tab = .marriage
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.pencil")
                        Text("Leave a love note")
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.noteText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Theme.noteBg, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Theme.noteLine, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var familyCard: some View {
        let chores = app.dashboard?.chores
        return Card(padding: 11) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Button { app.tab = .family } label: {
                        HStack(spacing: 6) {
                            IconTile(system: "person.2", colors: Theme.familyGradient)
                            Text("Family")
                                .font(.system(size: 15, weight: .bold))
                        }
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Text("\(chores?.done ?? 0) of \(chores?.total ?? 0)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.good)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Theme.goodBg, in: Capsule())
                }
                if let items = chores?.items, !items.isEmpty {
                    ForEach(items) { item in
                        Button {
                            Task { await app.toggleChore(id: item.id, done: !item.done) }
                        } label: {
                            HStack(spacing: 7) {
                                CheckBox(done: item.done, color: Theme.family)
                                Text(item.title)
                                    .font(.system(size: 12.5, weight: .medium))
                                    .foregroundStyle(item.done ? Theme.muted : Theme.text)
                                    .strikethrough(item.done, color: Color(hex: 0xCBD5E1))
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    Text("No chores yet")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Theme.muted)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var calendarCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    IconTile(system: "calendar", colors: Theme.calendarGradient)
                    Text("Calendar")
                        .font(.system(size: 15, weight: .bold))
                    Spacer()
                    HStack(spacing: 5) {
                        Circle().fill(Color(hex: 0x4285F4)).frame(width: 7, height: 7)
                        Text("Events + feeds")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.muted)
                    }
                }
                let events = Array((app.dashboard?.events ?? []).prefix(3))
                if events.isEmpty {
                    Text("Nothing coming up")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.muted)
                } else {
                    ForEach(events) { event in
                        eventRow(event)
                    }
                }
            }
        }
        .onTapGesture { app.tab = .calendar }
        .accessibilityAction(named: Text("Open Calendar")) { app.tab = .calendar }
    }

    private func eventRow(_ event: FamilyEvent) -> some View {
        let when = Dates.whenChip(event.startsAt)
        return HStack(spacing: 10) {
            Circle()
                .fill(Color(hexString: event.color))
                .frame(width: 8, height: 8)
                .shadow(color: Color(hexString: event.color).opacity(0.25), radius: 2)
            Text(when.label.uppercased())
                .font(.system(size: 10, weight: .heavy))
                .tracking(0.4)
                .foregroundStyle(when.isToday ? Theme.accent2 : Theme.muted)
                .frame(width: 46, alignment: .leading)
            Text(event.title)
                .font(.system(size: 13.5, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(event.allDay ? "All day" : Dates.timeLabel(event.startsAt))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.muted)
        }
    }

    private var vacationCard: some View {
        let trip = app.dashboard?.trip
        let saved = trip?.savingsCents ?? 0
        let goal = trip?.goalCents ?? 0
        let fraction = goal > 0 ? min(Double(saved) / Double(goal), 1) : 0
        let days = trip?.daysUntil ?? 0
        return Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    IconTile(system: "paperplane", colors: Theme.vacationGradient)
                    Text("Vacations")
                        .font(.system(size: 15, weight: .bold))
                }
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Kicker(text: trip == nil ? "Trips" : "Next trip")
                        Text(trip?.name ?? "Plan a getaway")
                            .font(.system(size: 13.5, weight: .bold))
                    }
                    Spacer()
                    if trip != nil {
                        VStack(alignment: .trailing, spacing: 0) {
                            Text("\(days)")
                                .font(.system(size: 20, weight: .heavy))
                                .tracking(-0.5)
                                .foregroundStyle(Theme.vacation)
                            Text("DAYS")
                                .font(.system(size: 10, weight: .bold))
                                .tracking(0.4)
                                .foregroundStyle(Theme.muted)
                        }
                    }
                }
                if trip != nil {
                    VStack(alignment: .leading, spacing: 6) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Theme.line2)
                                Capsule()
                                    .fill(LinearGradient(colors: [Color(hex: 0xFB923C), Theme.vacation], startPoint: .leading, endPoint: .trailing))
                                    .frame(width: max(CGFloat(8), geo.size.width * CGFloat(fraction)))
                            }
                        }
                        .frame(height: 8)
                        HStack(spacing: 4) {
                            Text("Trip savings")
                            Spacer()
                            Text(Money.format(saved))
                                .font(.system(size: 11.5, weight: .heavy))
                                .foregroundStyle(Theme.text)
                            Text("of \(Money.format(goal))")
                        }
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Theme.muted)
                    }
                }
            }
        }
        .onTapGesture { app.tab = .vacations }
        .accessibilityAction(named: Text("Open Vacations")) { app.tab = .vacations }
    }

    private var mortgageHomeCard: some View {
        let summary = app.mortgage?.summary
        return Card {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    IconTile(system: "house", colors: Theme.billsGradient)
                    Text("Home")
                        .font(.system(size: 15, weight: .bold))
                }
                if let balance = summary?.balanceCents, app.mortgage?.loanCents != nil {
                    Text(Money.format(balance))
                        .font(.system(size: 20, weight: .heavy))
                    Text(summary?.payoffDate.map { "Payoff \(Dates.shortDay($0))" } ?? "Mortgage")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.muted)
                    if let equity = summary?.equityCents {
                        Text("Equity \(Money.format(equity))")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.good)
                    }
                } else {
                    Text("Add your mortgage in Budget")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.muted)
                }
            }
        }
        .onTapGesture { app.tab = .budget }
        .accessibilityAction(named: Text("Open Budget")) { app.tab = .budget }
    }

    private var foodHomeCard: some View {
        let totals = app.food?.totals
        let goals = app.food?.goals
        let left = (goals?.calories ?? 0) - (totals?.calories ?? 0)
        return Card {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    IconTile(system: "fork.knife", colors: Theme.incomeGradient)
                    Text("Food")
                        .font(.system(size: 15, weight: .bold))
                }
                if let goals, let totals {
                    Text("\(left) kcal left")
                        .font(.system(size: 20, weight: .heavy))
                        .foregroundStyle(left >= 0 ? Theme.text : Theme.bad)
                    Text("Protein \(totals.protein) of \(goals.protein) g")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                } else {
                    Text("Today's calories and protein")
                        .foregroundStyle(Theme.muted)
                }
            }
        }
        .onTapGesture { app.tab = .food }
        .accessibilityAction(named: Text("Open Food")) { app.tab = .food }
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
