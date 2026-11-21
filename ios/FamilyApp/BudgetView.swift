import Charts
import SwiftUI

enum BudgetSheet: Identifiable {
    case addTxn
    case editTxn(Txn)
    case budgets
    case addIncome
    case editIncome(IncomeEntry)
    case addBill
    case editBill(Bill)
    case addAccount
    case editAccount(Account)
    case importer
    case categories
    case mortgage
    case ask
    case settings

    var id: String {
        switch self {
        case .addTxn: return "add-txn"
        case .editTxn(let txn): return "txn-\(txn.id)"
        case .budgets: return "budgets"
        case .addIncome: return "add-income"
        case .editIncome(let item): return "income-\(item.id)"
        case .addBill: return "add-bill"
        case .editBill(let bill): return "bill-\(bill.id)"
        case .addAccount: return "add-account"
        case .editAccount(let account): return "acct-\(account.id)"
        case .importer: return "import"
        case .categories: return "categories"
        case .mortgage: return "mortgage"
        case .ask: return "ask"
        case .settings: return "settings"
        }
    }
}

struct BudgetView: View {
    @EnvironmentObject private var app: AppModel
    @State private var sheet: BudgetSheet?

    var body: some View {
        screen(app.budget)
    }

    @ViewBuilder
    private func screen(_ snapshot: BudgetSnapshot?) -> some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    header(snapshot)
                    if let snapshot {
                        hero(snapshot)
                        categories(snapshot)
                        insights(snapshot)
                        income(snapshot)
                        history(snapshot)
                baseline(snapshot)
                Button { sheet = .mortgage } label: {
                    Text("Mortgage and home value")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.accent2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.line, lineWidth: 1))
                }
                .buttonStyle(.plain)
                bills(snapshot)
                        transactions(snapshot)
                        accounts(snapshot)
                    } else {
                        Card {
                            Text("Pull to refresh once the server is reachable.")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Theme.muted)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 80)
            }
            .background(Theme.bg)
            .refreshable { await app.pullToRefresh() }

            Button {
                sheet = .addTxn
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(
                        LinearGradient(colors: [Color(hex: 0x3B82F6), Theme.navy], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .clipShape(Circle())
                    .shadow(color: Theme.navy.opacity(0.35), radius: 10, y: 6)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 18)
            .padding(.bottom, 16)
            .accessibilityLabel("Add transaction")
        }
        .sheet(item: $sheet) { item in
            sheetView(item)
        }
    }

    private func header(_ snapshot: BudgetSnapshot?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Budget")
                    .font(.system(size: 28, weight: .heavy))
                    .tracking(-0.7)
                Spacer()
                PacePill(pace: snapshot?.pace ?? "no_budget")
                GearButton { sheet = .settings }
            }
            HStack {
                Button { Task { await app.shiftMonth(-1) } } label: { chevron("chevron.left") }
                Text(Dates.prettyMonth(app.budgetMonth))
                    .font(.system(size: 15, weight: .bold))
                    .frame(maxWidth: .infinity)
                Button { Task { await app.shiftMonth(1) } } label: { chevron("chevron.right") }
            }
            SyncPill(text: Dates.synced(app.lastSynced))
        }
    }

    private func chevron(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(Theme.muted)
            .frame(width: 28, height: 28)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Theme.line, lineWidth: 1))
    }

    private func hero(_ snapshot: BudgetSnapshot) -> some View {
        let progress = snapshot.budgetCents > 0 ? Double(snapshot.spentCents) / Double(snapshot.budgetCents) : 0
        let over = snapshot.budgetCents > 0 && snapshot.spentCents > snapshot.budgetCents
        return Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    ZStack {
                        ProgressRing(progress: progress, color: over ? Theme.bad : Theme.accent, lineWidth: 8)
                        VStack(spacing: 1) {
                            Text("\(Int((min(progress, 9.99) * 100).rounded()))%")
                                .font(.system(size: 20, weight: .heavy))
                            Text("SPENT")
                                .font(.system(size: 9, weight: .bold))
                                .tracking(0.4)
                                .foregroundStyle(Theme.muted)
                        }
                    }
                    .frame(width: 92, height: 92)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(Money.format(snapshot.spentCents))
                            .font(.system(size: 26, weight: .heavy))
                            .tracking(-0.6)
                        Text("of \(Money.format(snapshot.budgetCents)) \(snapshot.monthLabel) budget")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.muted)
                        Text("\(Money.format(snapshot.remainingCents)) remaining")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(snapshot.remainingCents < 0 ? Theme.bad : Theme.good)
                    }
                    Spacer(minLength: 0)
                }
                HStack(alignment: .top) {
                    stat("Spent", Money.format(snapshot.spentCents), "\(snapshot.daysElapsed) days in", good: false)
                    stat("Remaining", Money.format(snapshot.remainingCents), "\(snapshot.daysLeft) days left", good: snapshot.remainingCents >= 0)
                    stat("Income", Money.format(snapshot.incomeReceivedCents), snapshot.incomeExpectedCents > 0 ? "of \(Money.format(snapshot.incomeExpectedCents))" : "logged", good: false)
                }
                .padding(.top, 4)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Safe to spend")
                            .font(.system(size: 12, weight: .semibold))
                        Text("\(snapshot.daysLeft) days left · upcoming bills included")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    Text("\(Money.format(snapshot.safePerDayCents)) / day")
                        .font(.system(size: 15, weight: .heavy))
                }
                .foregroundStyle(Theme.accent2)
                .padding(12)
                .background(Theme.safeBg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private func stat(_ label: String, _ value: String, _ sub: String, good: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(0.4)
                .foregroundStyle(Theme.muted)
            Text(value)
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(good ? Theme.good : Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(sub)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func categories(_ snapshot: BudgetSnapshot) -> some View {
        let slices = snapshot.categories
            .filter { $0.spentCents > 0 }
            .map { DonutSlice(id: $0.id, name: $0.name, value: Double($0.spentCents), color: Color(hexString: $0.color), label: Money.format($0.spentCents)) }
        return Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    IconTile(system: "chart.pie", colors: Theme.budgetGradient)
                    Text("Spending by category")
                        .font(.system(size: 15, weight: .bold))
                    Spacer()
                    Button { sheet = .categories } label: {
                        Label("Set budgets", systemImage: "square.and.pencil")
                            .font(.system(size: 11.5, weight: .bold))
                            .foregroundStyle(Theme.accent2)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Theme.safeBg, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                DonutChart(slices: slices, totalLabel: Money.format(snapshot.spentCents))
                    .frame(width: 150, height: 150)
                    .frame(maxWidth: .infinity)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                    ForEach(slices) { slice in
                        HStack(spacing: 6) {
                            Circle().fill(slice.color).frame(width: 8, height: 8)
                            Text(slice.name)
                                .lineLimit(1)
                                .foregroundStyle(Theme.muted)
                            Spacer(minLength: 2)
                            Text(slice.label)
                                .foregroundStyle(Theme.text)
                        }
                        .font(.system(size: 11, weight: .semibold))
                    }
                }
                Text("Tap a budget amount to edit it. Suggest budgets uses your earlier months.")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Theme.muted)
                ForEach(snapshot.categories) { category in
                    envelope(category)
                }
                if snapshot.uncategorizedCents > 0 {
                    Text("\(Money.format(snapshot.uncategorizedCents)) isn't in a category yet.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.muted)
                }
            }
        }
    }

    private func envelope(_ category: CategorySpend) -> some View {
        let over = category.budgetCents > 0 && category.spentCents > category.budgetCents
        let fraction: Double = {
            guard category.budgetCents > 0 else { return category.spentCents > 0 ? 1 : 0 }
            return min(Double(category.spentCents) / Double(category.budgetCents), 1)
        }()
        let rest: String = {
            if category.budgetCents == 0 { return "No budget" }
            let delta = category.budgetCents - category.spentCents
            return delta >= 0 ? "\(Money.format(delta)) left" : "\(Money.format(-delta)) over"
        }()
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 9) {
                IconTile(system: category.icon, colors: [Color(hexString: category.color), Color(hexString: category.color)], size: 30)
                Text(category.name)
                    .font(.system(size: 13.5, weight: .bold))
                Spacer()
                Text(Money.format(category.spentCents))
                    .font(.system(size: 13.5, weight: .heavy))
                    .foregroundStyle(over ? Theme.bad : Theme.text)
            }
            HStack {
                Button { sheet = .budgets } label: {
                    HStack(spacing: 4) {
                        Text("\(Money.format(category.budgetCents)) budget")
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Theme.panel2, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Theme.line, lineWidth: 1))
                }
                .buttonStyle(.plain)
                Spacer()
                Text(rest)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(over ? Theme.bad : Theme.muted)
            }
            .padding(.leading, 39)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.line2)
                    Capsule()
                        .fill(over ? Theme.bad : Color(hexString: category.color))
                        .frame(width: max(CGFloat(fraction > 0 ? 6 : 0), geo.size.width * CGFloat(fraction)))
                }
            }
            .frame(height: 7)
            .padding(.leading, 39)
        }
        .padding(.top, 8)
    }

    private func insights(_ snapshot: BudgetSnapshot) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    IconTile(system: "sparkles", colors: Theme.aiGradient)
                    Text("Insights")
                        .font(.system(size: 15, weight: .bold))
                }
                if snapshot.insights.isEmpty {
                    Text("Nothing to flag this month.")
                        .foregroundStyle(Theme.muted)
                }
                ForEach(Array(snapshot.insights.enumerated()), id: \.offset) { _, insight in
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: insight.level == "bad" ? "exclamationmark.triangle" : insight.level == "good" ? "checkmark" : "calendar")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(insightColor(insight.level))
                            .frame(width: 22, height: 22)
                            .background(insightBg(insight.level), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(insight.title).font(.system(size: 13, weight: .bold))
                            Text(insight.body).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.muted)
                        }
                    }
                }
                Text(snapshot.placeholders.ai)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.soft)
                Button { sheet = .ask } label: {
                    Text("Ask Gemini")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.accent2)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func income(_ snapshot: BudgetSnapshot) -> some View {
        let fraction = snapshot.incomeExpectedCents > 0 ? min(Double(snapshot.incomeReceivedCents) / Double(snapshot.incomeExpectedCents), 1) : 0
        return Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    IconTile(system: "banknote", colors: Theme.incomeGradient)
                    Text("Expected income")
                        .font(.system(size: 15, weight: .bold))
                    Spacer()
                    Button { sheet = .addIncome } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Theme.accent2)
                    }
                    .buttonStyle(.plain)
                }
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Money.format(snapshot.incomeReceivedCents))
                            .font(.system(size: 22, weight: .heavy))
                        Text(snapshot.incomeExpectedCents > 0 ? "received of \(Money.format(snapshot.incomeExpectedCents)) expected" : "No expected income yet")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    if snapshot.incomeExpectedCents > 0 {
                        Text("\(Int((fraction * 100).rounded()))%")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Theme.good)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Theme.goodBg, in: Capsule())
                    }
                }
                CapsuleBar(fraction: fraction, colors: [Color(hex: 0x34D399), Theme.good])
                ForEach(snapshot.incomeEntries) { entry in
                    Button { sheet = .editIncome(entry) } label: { incomeRow(entry) }
                        .buttonStyle(.plain)
                }
                HStack(spacing: 8) {
                    planBox("Planned vs actual", Money.format(snapshot.spentCents), "spent of \(Money.format(snapshot.budgetCents)) planned", good: false)
                    planBox("Projected leftover", snapshot.projectedLeftoverCents.map { Money.format($0) } ?? "—", "after expected income and budget", good: (snapshot.projectedLeftoverCents ?? 0) >= 0)
                }
            }
        }
    }

    private func incomeRow(_ entry: IncomeEntry) -> some View {
        let fraction = entry.expectedCents > 0 ? min(Double(entry.receivedCents) / Double(entry.expectedCents), 1) : 0
        let index = app.members.firstIndex { $0.id == entry.memberId } ?? 0
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Avatar(name: entry.memberName ?? entry.label, index: index, size: 24)
                Text(entry.label)
                    .font(.system(size: 13, weight: .bold))
                Spacer()
                Text(Money.format(entry.expectedCents))
                    .font(.system(size: 13, weight: .heavy))
            }
            CapsuleBar(fraction: fraction, colors: [Theme.accent, Theme.accent])
            HStack {
                Text(entry.receivedCents > 0 ? "Received \(Money.format(entry.receivedCents))" : "Nothing received yet")
                Spacer()
                if let expected = entry.expectedOn {
                    Text(Dates.shortDay(expected))
                }
            }
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(Theme.muted)
        }
        .padding(10)
        .background(Theme.panel2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func planBox(_ kicker: String, _ value: String, _ sub: String, good: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Kicker(text: kicker)
            Text(value)
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(good ? Theme.good : Theme.text)
            Text(sub)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Theme.panel2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func history(_ snapshot: BudgetSnapshot) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    IconTile(system: "chart.xyaxis.line", colors: Theme.calendarGradient)
                    Text("Historical spending")
                        .font(.system(size: 15, weight: .bold))
                }
                Text("\(snapshot.history.first?.month.prefix(4) ?? "") · vs \(Money.format(snapshot.historyBudgetCents)) budget")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.muted)
                Chart {
                    ForEach(Array(snapshot.history.enumerated()), id: \.element.id) { index, item in
                        BarMark(
                            x: .value("Month", index),
                            y: .value("Spent", Double(item.spentCents) / 100)
                        )
                        .foregroundStyle(barColor(item))
                    }
                    if snapshot.historyBudgetCents > 0 {
                        RuleMark(y: .value("Budget", Double(snapshot.historyBudgetCents) / 100))
                            .foregroundStyle(Theme.muted)
                    }
                }
                .chartYAxis(.hidden)
                .chartXAxis(.hidden)
                .frame(height: 140)
                HStack(spacing: 0) {
                    ForEach(snapshot.history) { item in
                        Text(item.shortLabel)
                            .frame(maxWidth: .infinity)
                    }
                }
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.soft)
                HStack(spacing: 10) {
                    legendSwatch(Color(hex: 0x93C5FD), "Under budget")
                    legendSwatch(Color(hex: 0xF59E0B), "Over budget")
                    legendSwatch(Theme.accent, "This month")
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.muted)
                if !snapshot.trends.isEmpty {
                    Kicker(text: "Category trends vs earlier average")
                        .padding(.top, 6)
                    ForEach(snapshot.trends) { trend in
                        HStack(spacing: 8) {
                            Text(trend.name)
                                .font(.system(size: 13, weight: .bold))
                                .frame(width: 88, alignment: .leading)
                                .lineLimit(1)
                            Chart(Array(trend.points.enumerated()), id: \.offset) { pair in
                                LineMark(
                                    x: .value("Month", pair.offset),
                                    y: .value("Spent", pair.element)
                                )
                                .foregroundStyle(Color(hexString: trend.color))
                            }
                            .chartXAxis(.hidden)
                            .chartYAxis(.hidden)
                            .frame(height: 22)
                            Text(trend.deltaLabel)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(trend.direction == "up" ? Theme.bad : trend.direction == "down" ? Theme.good : Theme.muted)
                                .frame(width: 110, alignment: .trailing)
                                .lineLimit(2)
                                .minimumScaleFactor(0.7)
                        }
                    }
                }
            }
        }
    }

    private func barColor(_ item: HistoryMonth) -> Color {
        if item.isCurrent { return Theme.accent }
        if item.budgetCents > 0 && item.spentCents > item.budgetCents { return Color(hex: 0xF59E0B) }
        return Color(hex: 0x93C5FD)
    }

    private func legendSwatch(_ color: Color, _ title: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8)
            Text(title)
        }
    }

    private func baseline(_ snapshot: BudgetSnapshot) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    IconTile(system: "square.and.arrow.down", colors: Theme.importGradient)
                    Text("2026 spending baseline")
                        .font(.system(size: 15, weight: .bold))
                }
                Text(snapshot.importCount > 0 ? "Baseline imported · \(snapshot.importCount) transactions" : "No CSV imported yet")
                    .font(.system(size: 13.5, weight: .bold))
                Text("Averages from this history are used to suggest each category budget.")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Theme.muted)
                HStack(spacing: 8) {
                    Button { sheet = .importer } label: {
                        Label("Import CSV", systemImage: "square.and.arrow.down")
                            .font(.system(size: 12.5, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.line, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    Button { Task { await app.suggestBudgets() } } label: {
                        Label("Suggest budgets", systemImage: "arrow.right")
                            .font(.system(size: 12.5, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func bills(_ snapshot: BudgetSnapshot) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    IconTile(system: "calendar", colors: Theme.billsGradient)
                    Text("Upcoming bills")
                        .font(.system(size: 15, weight: .bold))
                    Spacer()
                    if !snapshot.bills.isEmpty {
                        Text("\(snapshot.bills.count) due")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Theme.warn)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Theme.warnBg, in: Capsule())
                    }
                    Button { sheet = .addBill } label: {
                        Image(systemName: "plus").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.accent2)
                    }
                    .buttonStyle(.plain)
                }
                if snapshot.bills.isEmpty {
                    Text("No upcoming bills.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.muted)
                }
                ForEach(snapshot.bills) { bill in
                    Button { sheet = .editBill(bill) } label: {
                        HStack(spacing: 10) {
                            IconTile(system: "doc.text", colors: Theme.billsGradient, size: 32)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(bill.name).font(.system(size: 13.5, weight: .bold))
                                Text("\(bill.cadence.capitalized) · \(bill.categoryName ?? "Bills")")
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            Text(Dates.shortDay(bill.dueOn))
                                .font(.system(size: 10.5, weight: .bold))
                                .foregroundStyle(Theme.accent2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Theme.safeBg, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                            Text(Money.format(bill.amountCents, showCents: true))
                                .font(.system(size: 13.5, weight: .heavy))
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func transactions(_ snapshot: BudgetSnapshot) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    IconTile(system: "list.bullet", colors: Theme.budgetGradient)
                    Text("Transactions")
                        .font(.system(size: 15, weight: .bold))
                    Spacer()
                    Text(snapshot.monthLabel)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Theme.muted)
                }
                if snapshot.transactions.isEmpty {
                    Text("Nothing in this month yet. Use + to add one.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.muted)
                }
                ForEach(snapshot.transactions) { txn in
                    Button { sheet = .editTxn(txn) } label: { txnRow(txn) }
                        .buttonStyle(.plain)
                }
            }
        }
    }

    private func txnRow(_ txn: Txn) -> some View {
        let index = app.members.firstIndex { $0.id == txn.memberId } ?? 0
        let income = txn.kind == "income"
        return HStack(spacing: 10) {
            IconTile(system: txn.categoryIcon ?? (income ? "banknote" : "tag"), colors: [Color(hexString: txn.categoryColor ?? "#64748b"), Color(hexString: txn.categoryColor ?? "#64748b")], size: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(txn.merchant).font(.system(size: 13.5, weight: .bold)).lineLimit(1)
                Text("\(txn.categoryName ?? txn.kind.capitalized) · \(Dates.shortDay(txn.occurredOn))")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 4)
            if let name = txn.memberName {
                Avatar(name: name, index: index, size: 22)
            }
            Text((income ? "+" : "") + Money.format(txn.amountCents, showCents: true))
                .font(.system(size: 13.5, weight: .heavy))
                .foregroundStyle(income ? Theme.good : Theme.text)
        }
    }

    private func accounts(_ snapshot: BudgetSnapshot) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    IconTile(system: "building.columns", colors: Theme.familyGradient)
                    Text("Accounts")
                        .font(.system(size: 15, weight: .bold))
                    Spacer()
                    Button { sheet = .addAccount } label: {
                        Image(systemName: "plus").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.accent2)
                    }
                    .buttonStyle(.plain)
                }
                Text("SimpleFIN is not in this version. " + snapshot.placeholders.bankSync)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.soft)
                if snapshot.accounts.isEmpty {
                    Text("Add balances by hand until bank sync arrives.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.muted)
                }
                ForEach(snapshot.accounts) { account in
                    Button { sheet = .editAccount(account) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(account.name).font(.system(size: 13, weight: .bold))
                                Text(account.institution ?? account.kind.capitalized)
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            Text(Money.format(account.balanceCents, showCents: true))
                                .font(.system(size: 15, weight: .heavy))
                                .foregroundStyle(account.balanceCents < 0 ? Theme.bad : Theme.text)
                        }
                        .padding(10)
                        .background(Theme.panel2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func insightColor(_ level: String) -> Color {
        switch level {
        case "bad": return Theme.bad
        case "good": return Theme.good
        default: return Theme.warn
        }
    }

    private func insightBg(_ level: String) -> Color {
        switch level {
        case "bad": return Theme.badBg
        case "good": return Theme.goodBg
        default: return Theme.warnBg
        }
    }

    @ViewBuilder
    private func sheetView(_ item: BudgetSheet) -> some View {
        switch item {
        case .addTxn:
            TransactionEditor(existing: nil)
        case .editTxn(let txn):
            TransactionEditor(existing: txn)
        case .budgets:
            BudgetEditor()
        case .addIncome:
            IncomeEditor(existing: nil)
        case .editIncome(let entry):
            IncomeEditor(existing: entry)
        case .addBill:
            BillEditor(existing: nil)
        case .editBill(let bill):
            BillEditor(existing: bill)
        case .addAccount:
            AccountEditor(existing: nil)
        case .editAccount(let account):
            AccountEditor(existing: account)
        case .importer:
            BankImportView()
        case .categories:
            CategoryManagerView()
        case .mortgage:
            MortgageView()
        case .ask:
            AskInsightView()
        case .settings:
            SettingsView()
        }
    }
}

struct CapsuleBar: View {
    var fraction: Double
    var colors: [Color]

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.line2)
                Capsule()
                    .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(CGFloat(fraction > 0 ? 8 : 0), geo.size.width * CGFloat(min(max(fraction, 0), 1))))
            }
        }
        .frame(height: 8)
    }
}
