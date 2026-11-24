import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var app: AppModel
    @State private var settings = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                budgetSummary
                todaySummary
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
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
                    Text("·")
                        .foregroundStyle(Theme.soft)
                    Text(Dates.synced(app.lastSynced))
                        .font(.caption)
                        .foregroundStyle(Theme.soft)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)
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

        return Button {
            app.tab = .budget
        } label: {
            Card(padding: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "creditcard")
                            .foregroundStyle(Theme.accent)
                        Text("Monthly budget")
                            .font(.headline)
                            .foregroundStyle(Theme.text)
                        Spacer()
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
                        Text("No monthly budget yet")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.muted)
                        Text("Tap to set one up")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Monthly budget summary")
        .accessibilityHint("Opens the Budget tab")
    }

    private var todaySummary: some View {
        let dashboard = app.dashboard
        let nextEvent = dashboard?.events.first
        let choreSummary = dashboard?.chores
        let choresLeft = max((choreSummary?.total ?? 0) - (choreSummary?.done ?? 0), 0)
        let nextChore = choreSummary?.items.first(where: { !$0.done })
        let choreDetail: String
        if let nextChore {
            choreDetail = nextChore.title
        } else if (choreSummary?.total ?? 0) == 0 {
            choreDetail = "No chores yet"
        } else {
            choreDetail = "All caught up"
        }

        return Card(padding: 0) {
            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Today")
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
                ) {
                    app.tab = .calendar
                }

                Divider()
                    .padding(.leading, 58)

                HomeLinkRow(
                    symbol: "checklist",
                    tint: Theme.family,
                    title: "Family",
                    detail: choreDetail,
                    badge: choresLeft > 0 ? "\(choresLeft) left" : nil
                ) {
                    app.tab = .family
                }
            }
        }
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
                        .lineLimit(1)
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
        .accessibilityHint("Opens the \(title) tab")
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
