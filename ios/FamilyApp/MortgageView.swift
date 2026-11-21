import Charts
import SwiftUI

struct MortgageView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var loan = ""
    @State private var rate = ""
    @State private var term = "360"
    @State private var start = Date()
    @State private var payment = ""
    @State private var address = ""
    @State private var extra: Double = 0
    @State private var value = ""
    @State private var valueDate = Date()
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let summary = app.mortgage?.summary, app.mortgage?.loanCents != nil {
                        summaryCard(summary)
                    }
                    Card {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Loan").font(.system(size: 16, weight: .bold))
                            LabeledInput(title: "Loan amount", text: $loan, keyboard: .decimalPad, autocap: .never)
                            LabeledInput(title: "Rate %", text: $rate, keyboard: .decimalPad, autocap: .never)
                            LabeledInput(title: "Term in months", text: $term, keyboard: .numberPad, autocap: .never)
                            DatePicker("Start", selection: $start, displayedComponents: .date)
                            LabeledInput(title: "Monthly payment", text: $payment, keyboard: .decimalPad, autocap: .never)
                            LabeledInput(title: "Home address", text: $address, autocap: .words)
                            Text("Extra payment $\(Int(extra)) / month")
                                .font(.system(size: 13, weight: .semibold))
                            Slider(value: $extra, in: 0...2000, step: 25)
                            if let preview = localPreview() {
                                Text("Payoff \(preview.payoff). Interest saved \(Money.format(preview.saved)).")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(Theme.muted)
                            }
                            PrimaryButton(title: "Save loan") { Task { await save() } }
                        }
                    }
                    Card {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Home value").font(.system(size: 16, weight: .bold))
                            if let points = app.mortgage?.values, points.count > 1 {
                                Chart(points) { point in
                                    LineMark(
                                        x: .value("Date", point.valuedOn),
                                        y: .value("Value", Double(point.valueCents) / 100)
                                    )
                                    .foregroundStyle(Theme.accent)
                                }
                                .frame(height: 140)
                                .chartYAxis(.hidden)
                            }
                            ForEach(app.mortgage?.values ?? []) { point in
                                HStack {
                                    Text(Dates.shortDay(point.valuedOn))
                                    Text(point.source).foregroundStyle(Theme.soft)
                                    Spacer()
                                    Text(Money.format(point.valueCents))
                                    if point.source == "manual" {
                                        Button { Task { await deleteValue(point) } } label: {
                                            Image(systemName: "trash").foregroundStyle(Theme.soft)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .font(.system(size: 13, weight: .medium))
                            }
                            LabeledInput(title: "Value", text: $value, keyboard: .decimalPad, autocap: .never)
                            DatePicker("As of", selection: $valueDate, displayedComponents: .date)
                            OutlineButton(title: "Add value", system: "plus") { Task { await addValue() } }
                            if app.mortgage?.rentcastActive == true {
                                Button("Refresh RentCast value") { Task { await rentcast() } }
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(Theme.accent2)
                            }
                        }
                    }
                    if let error {
                        Text(error).foregroundStyle(Theme.bad).font(.system(size: 13, weight: .semibold))
                    }
                }
                .padding(16)
            }
            .background(Theme.bg)
            .navigationTitle("Mortgage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .onAppear(perform: load)
        }
    }

    private func summaryCard(_ summary: MortgageSummary) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                Text("Remaining \(Money.format(summary.balanceCents ?? 0))")
                    .font(.system(size: 18, weight: .heavy))
                Text("Principal paid \(Money.format(summary.principalPaidCents ?? 0)) · Interest paid \(Money.format(summary.interestPaidCents ?? 0))")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.muted)
                if let payoff = summary.payoffDate {
                    Text("Payoff \(Dates.shortDay(payoff))")
                        .font(.system(size: 14, weight: .semibold))
                }
                if let equity = summary.equityCents {
                    Text("Equity \(Money.format(equity))")
                        .foregroundStyle(Theme.good)
                        .font(.system(size: 14, weight: .bold))
                }
                if let message = summary.error {
                    Text(message).foregroundStyle(Theme.bad)
                }
            }
        }
    }

    private func load() {
        guard let mortgage = app.mortgage, let loanCents = mortgage.loanCents else { return }
        loan = Money.plain(loanCents)
        rate = mortgage.annualRatePercent.map { String(format: "%.3f", $0) } ?? ""
        term = mortgage.termMonths.map(String.init) ?? "360"
        payment = Money.plain(mortgage.paymentCents ?? 0)
        extra = Double(mortgage.extraCents) / 100
        address = mortgage.address ?? ""
        if let startDate = mortgage.startDate, let date = Dates.parseDay(startDate) {
            start = date
        }
    }

    private func localPreview() -> (payoff: String, saved: Int)? {
        guard let loanCents = Money.cents(from: loan),
              let paymentCents = Money.cents(from: payment),
              let rateValue = Double(rate), loanCents > 0, paymentCents > 0 else { return nil }
        let months = Int(term) ?? 360
        let withExtra = MortgageMath.payoff(loan: loanCents, rate: rateValue, payment: paymentCents, extra: Int(extra * 100), start: start)
        let plain = MortgageMath.payoff(loan: loanCents, rate: rateValue, payment: paymentCents, extra: 0, start: start)
        guard let payoff = withExtra.date else { return nil }
        return (Dates.shortDay(payoff), max((plain.interest ?? 0) - (withExtra.interest ?? 0), 0))
    }

    private func save() async {
        guard let loanCents = Money.cents(from: loan),
              let paymentCents = Money.cents(from: payment),
              let rateValue = Double(rate),
              let months = Int(term) else {
            error = "Check the loan fields."
            return
        }
        do {
            let _: MortgageSnapshot = try await app.api.put(
                "/v1/mortgage",
                body: MortgageBody(
                    loanCents: loanCents,
                    annualRatePercent: rateValue,
                    termMonths: months,
                    startDate: Dates.isoDay(start),
                    paymentCents: paymentCents,
                    extraCents: Int(extra * 100),
                    address: address
                )
            )
            await app.refreshAll(silent: true)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func addValue() async {
        guard let cents = Money.cents(from: value), cents > 0 else { return }
        do {
            let _: JSONAck = try await app.api.post(
                "/v1/home-values",
                body: HomeValueBody(valuedOn: Dates.isoDay(valueDate), valueCents: cents)
            )
            value = ""
            await app.refreshAll(silent: true)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func deleteValue(_ point: HomeValuePoint) async {
        do {
            let _: JSONAck = try await app.api.delete("/v1/home-values/\(point.id)")
            await app.refreshAll(silent: true)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func rentcast() async {
        do {
            let _: JSONAck = try await app.api.post("/v1/mortgage/rentcast")
            await app.refreshAll(silent: true)
        } catch {
            self.error = nil
        }
    }
}

enum MortgageMath {
    static func payoff(loan: Int, rate: Double, payment: Int, extra: Int, start: Date) -> (date: String?, interest: Int?) {
        var balance = loan
        var interestPaid = 0
        var month = 0
        let monthly = rate / 100 / 12
        while balance > 0 && month < 1200 {
            let interest = Int((Double(balance) * monthly + 0.5).rounded(.down))
            let due = payment + extra
            if due <= interest { return (nil, nil) }
            let principal = min(balance, due - interest)
            interestPaid += interest
            balance -= principal
            month += 1
        }
        guard balance <= 0 else { return (nil, nil) }
        return (addMonths(start, month), interestPaid)
    }

    private static func addMonths(_ start: Date, _ count: Int) -> String {
        let date = Calendar.current.date(byAdding: .month, value: count, to: start) ?? start
        return Dates.isoDay(date)
    }
}

struct AskInsightView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var question = "Where should we ease up this month?"
    @State private var answer: String?
    @State private var working = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Gemini reads this month's category totals on the server. The key never leaves the server.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.muted)
                    LabeledInput(title: "Question", text: $question)
                    PrimaryButton(title: working ? "Asking…" : "Ask") { Task { await ask() } }
                        .disabled(working)
                    if let answer {
                        Text(answer).font(.system(size: 15, weight: .medium))
                    }
                    if let error {
                        Text(error).foregroundStyle(Theme.bad)
                    }
                }
                .padding(16)
            }
            .background(Theme.bg)
            .navigationTitle("Insights")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }

    private func ask() async {
        working = true
        defer { working = false }
        do {
            let result: AskResult = try await app.api.post(
                "/v1/budget/ask",
                body: AskBody(month: app.budgetMonth, question: question, today: Dates.isoDay(Date()))
            )
            answer = result.answer
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
