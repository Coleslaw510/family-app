import SwiftUI
import UniformTypeIdentifiers

struct EditorChrome<Content: View>: View {
    var title: String
    var saveTitle: String = "Save"
    var working: Bool
    var error: String?
    var onSave: () -> Void
    @ViewBuilder var content: Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    content
                    if let error {
                        Text(error)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.bad)
                    }
                }
                .padding(16)
            }
            .background(Theme.bg)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(working ? "Saving…" : saveTitle) { onSave() }
                        .disabled(working)
                }
            }
        }
    }
}

struct TransactionEditor: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    var existing: Txn?

    @State private var merchant = ""
    @State private var amount = ""
    @State private var kind = "expense"
    @State private var day = Date()
    @State private var categoryId = ""
    @State private var note = ""
    @State private var working = false
    @State private var error: String?

    var body: some View {
        EditorChrome(title: existing == nil ? "Add transaction" : "Edit transaction", working: working, error: error, onSave: { Task { await save() } }) {
            LabeledInput(title: "Merchant", text: $merchant, autocap: .words)
            LabeledInput(title: "Amount", text: $amount, keyboard: .decimalPad, autocap: .never)
            Picker("Type", selection: $kind) {
                Text("Expense").tag("expense")
                Text("Income").tag("income")
            }
            .pickerStyle(.segmented)
            DatePicker("Date", selection: $day, displayedComponents: .date)
            Picker("Category", selection: $categoryId) {
                Text("None").tag("")
                ForEach(app.budget?.categories ?? []) { category in
                    Text(category.name).tag(category.id)
                }
            }
            LabeledInput(title: "Note", text: $note)
            if existing != nil {
                Button("Delete transaction", role: .destructive) { Task { await remove() } }
                    .font(.system(size: 15, weight: .semibold))
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard let existing else { return }
        merchant = existing.merchant
        amount = Money.plain(existing.amountCents)
        kind = existing.kind
        day = Dates.parseDay(existing.occurredOn) ?? Date()
        categoryId = existing.categoryId ?? ""
        note = existing.note ?? ""
    }

    private func save() async {
        guard let cents = Money.cents(from: amount), cents >= 0 else {
            error = "Enter an amount."
            return
        }
        let trimmed = merchant.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { error = "Add a merchant."; return }
        working = true
        defer { working = false }
        let body = TxnBody(
            merchant: trimmed,
            amountCents: cents,
            kind: kind,
            occurredOn: Dates.isoDay(day),
            categoryId: categoryId,
            note: note.trimmingCharacters(in: .whitespaces)
        )
        do {
            if let existing {
                let _: Txn = try await app.api.patch("/v1/transactions/\(existing.id)", body: body)
            } else {
                let _: Txn = try await app.api.post("/v1/transactions", body: body)
            }
            Haptics.success()
            await app.refreshAll(silent: true)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func remove() async {
        guard let existing else { return }
        working = true
        defer { working = false }
        do {
            let _: JSONAck = try await app.api.delete("/v1/transactions/\(existing.id)")
            await app.refreshAll(silent: true)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct BudgetEditor: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var amounts: [String: String] = [:]
    @State private var setDefault = true
    @State private var newName = ""
    @State private var working = false
    @State private var error: String?

    var body: some View {
        EditorChrome(title: "Category budgets", working: working, error: error, onSave: { Task { await save() } }) {
            Text("Amounts are for \(Dates.prettyMonth(app.budgetMonth)).")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.muted)
            Toggle("Also use these as the usual monthly budgets", isOn: $setDefault)
                .font(.system(size: 14, weight: .medium))
            ForEach(app.budget?.categories ?? []) { category in
                LabeledInput(title: category.name, text: binding(category), keyboard: .decimalPad, autocap: .never)
            }
            LabeledInput(title: "New category", text: $newName, autocap: .words)
        }
        .onAppear {
            for category in app.budget?.categories ?? [] {
                if amounts[category.id] == nil {
                    amounts[category.id] = Money.plain(category.budgetCents)
                }
            }
        }
    }

    private func binding(_ category: CategorySpend) -> Binding<String> {
        Binding(
            get: { amounts[category.id] ?? Money.plain(category.budgetCents) },
            set: { amounts[category.id] = $0 }
        )
    }

    private func save() async {
        working = true
        defer { working = false }
        do {
            if !newName.trimmingCharacters(in: .whitespaces).isEmpty {
                let _: JSONAck = try await app.api.post(
                    "/v1/categories",
                    body: CategoryBody(name: newName, color: "#2563eb", icon: "tag.fill", defaultBudgetCents: 0)
                )
            }
            for category in app.budget?.categories ?? [] {
                let text = amounts[category.id] ?? "0"
                guard let cents = Money.cents(from: text), cents >= 0 else {
                    error = "Check the amount for \(category.name)."
                    return
                }
                let _: JSONAck = try await app.api.put(
                    "/v1/categories/\(category.id)/budget",
                    body: BudgetSetBody(month: app.budgetMonth, amountCents: cents, setDefault: setDefault)
                )
            }
            Haptics.success()
            await app.refreshAll(silent: true)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct IncomeEditor: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    var existing: IncomeEntry?

    @State private var label = "Paycheck"
    @State private var expected = ""
    @State private var received = ""
    @State private var expectedDay = Date()
    @State private var receivedDay = Date()
    @State private var hasReceived = false
    @State private var memberId = ""
    @State private var working = false
    @State private var error: String?

    var body: some View {
        EditorChrome(title: existing == nil ? "Expected income" : "Edit income", working: working, error: error, onSave: { Task { await save() } }) {
            LabeledInput(title: "Label", text: $label, autocap: .words)
            LabeledInput(title: "Expected", text: $expected, keyboard: .decimalPad, autocap: .never)
            LabeledInput(title: "Received so far", text: $received, keyboard: .decimalPad, autocap: .never)
            DatePicker("Expected on", selection: $expectedDay, displayedComponents: .date)
            Toggle("Mark a received date", isOn: $hasReceived)
            if hasReceived {
                DatePicker("Received on", selection: $receivedDay, displayedComponents: .date)
            }
            Picker("Who", selection: $memberId) {
                Text("Household").tag("")
                ForEach(app.members) { member in
                    Text(member.name).tag(member.id)
                }
            }
            if existing != nil {
                Button("Delete", role: .destructive) { Task { await remove() } }
            }
        }
        .onAppear {
            memberId = existing?.memberId ?? app.member?.id ?? ""
            if let existing {
                label = existing.label
                expected = Money.plain(existing.expectedCents)
                received = Money.plain(existing.receivedCents)
                if let day = existing.expectedOn.flatMap(Dates.parseDay) { expectedDay = day }
                if let day = existing.receivedOn.flatMap(Dates.parseDay) {
                    receivedDay = day
                    hasReceived = true
                }
            }
        }
    }

    private func save() async {
        guard let expectedCents = Money.cents(from: expected), expectedCents >= 0 else { error = "Enter the expected amount."; return }
        let receivedCents = Money.cents(from: received) ?? 0
        guard receivedCents >= 0 else { error = "Received amount looks off."; return }
        working = true
        defer { working = false }
        let body = IncomeBody(
            label: label.trimmingCharacters(in: .whitespaces),
            month: app.budgetMonth,
            expectedCents: expectedCents,
            receivedCents: receivedCents,
            expectedOn: Dates.isoDay(expectedDay),
            receivedOn: hasReceived ? Dates.isoDay(receivedDay) : nil,
            memberId: memberId.isEmpty ? nil : memberId
        )
        do {
            if let existing {
                let _: JSONAck = try await app.api.patch("/v1/income/\(existing.id)", body: body)
            } else {
                let _: JSONAck = try await app.api.post("/v1/income", body: body)
            }
            await app.refreshAll(silent: true)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func remove() async {
        guard let existing else { return }
        do {
            let _: JSONAck = try await app.api.delete("/v1/income/\(existing.id)")
            await app.refreshAll(silent: true)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct BillEditor: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    var existing: Bill?

    @State private var name = ""
    @State private var amount = ""
    @State private var due = Date()
    @State private var cadence = "monthly"
    @State private var categoryId = ""
    @State private var notes = ""
    @State private var working = false
    @State private var error: String?

    var body: some View {
        EditorChrome(title: existing == nil ? "Add bill" : "Edit bill", working: working, error: error, onSave: { Task { await save() } }) {
            LabeledInput(title: "Name", text: $name, autocap: .words)
            LabeledInput(title: "Amount", text: $amount, keyboard: .decimalPad, autocap: .never)
            DatePicker("Due", selection: $due, displayedComponents: .date)
            Picker("Repeats", selection: $cadence) {
                Text("Once").tag("once")
                Text("Monthly").tag("monthly")
                Text("Yearly").tag("yearly")
            }
            Picker("Category", selection: $categoryId) {
                Text("None").tag("")
                ForEach(app.budget?.categories ?? []) { category in
                    Text(category.name).tag(category.id)
                }
            }
            LabeledInput(title: "Notes", text: $notes)
            if existing != nil {
                Button("Mark paid") { Task { await markPaid() } }
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.good)
                Button("Delete bill", role: .destructive) { Task { await remove() } }
            }
        }
        .onAppear {
            if let existing {
                name = existing.name
                amount = Money.plain(existing.amountCents)
                due = Dates.parseDay(existing.dueOn) ?? Date()
                cadence = existing.cadence
                categoryId = existing.categoryId ?? ""
                notes = existing.notes ?? ""
            }
        }
    }

    private func bodyPayload(paid: Bool? = nil) -> BillPatchBody {
        BillPatchBody(
            name: name.trimmingCharacters(in: .whitespaces),
            amountCents: Money.cents(from: amount),
            dueOn: Dates.isoDay(due),
            categoryId: categoryId.isEmpty ? nil : categoryId,
            cadence: cadence,
            paid: paid,
            notes: notes
        )
    }

    private func save() async {
        guard let cents = Money.cents(from: amount), cents >= 0, !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            error = "Name and amount are required."
            return
        }
        working = true
        defer { working = false }
        do {
            if let existing {
                let _: JSONAck = try await app.api.patch("/v1/bills/\(existing.id)", body: bodyPayload())
            } else {
                let _: JSONAck = try await app.api.post(
                    "/v1/bills",
                    body: BillBody(name: name, amountCents: cents, dueOn: Dates.isoDay(due), categoryId: categoryId.isEmpty ? nil : categoryId, cadence: cadence, notes: notes)
                )
            }
            await app.refreshAll(silent: true)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func markPaid() async {
        guard let existing else { return }
        working = true
        defer { working = false }
        do {
            let _: JSONAck = try await app.api.patch("/v1/bills/\(existing.id)", body: BillPatchBody(paid: true))
            Haptics.success()
            await app.refreshAll(silent: true)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func remove() async {
        guard let existing else { return }
        do {
            let _: JSONAck = try await app.api.delete("/v1/bills/\(existing.id)")
            await app.refreshAll(silent: true)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct AccountEditor: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    var existing: Account?

    @State private var name = ""
    @State private var institution = ""
    @State private var balance = ""
    @State private var kind = "checking"
    @State private var working = false
    @State private var error: String?

    var body: some View {
        EditorChrome(title: existing == nil ? "Add account" : "Edit account", working: working, error: error, onSave: { Task { await save() } }) {
            LabeledInput(title: "Name", text: $name, autocap: .words)
            LabeledInput(title: "Institution", text: $institution, autocap: .words)
            LabeledInput(title: "Balance", text: $balance, keyboard: .decimalPad, autocap: .never)
            Picker("Kind", selection: $kind) {
                Text("Checking").tag("checking")
                Text("Savings").tag("savings")
                Text("Credit").tag("credit")
                Text("Other").tag("other")
            }
            Text("Credit cards can be negative. Connect SimpleFIN in Settings to sync transactions.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.muted)
            if existing != nil {
                Button("Delete account", role: .destructive) { Task { await remove() } }
            }
        }
        .onAppear {
            if let existing {
                name = existing.name
                institution = existing.institution ?? ""
                balance = Money.plain(existing.balanceCents)
                kind = existing.kind
            }
        }
    }

    private func save() async {
        guard let cents = Money.cents(from: balance) else { error = "Enter a balance."; return }
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { error = "Add a name."; return }
        working = true
        defer { working = false }
        let body = AccountBody(name: name, institution: institution, balanceCents: cents, kind: kind)
        do {
            if let existing {
                let _: JSONAck = try await app.api.patch("/v1/accounts/\(existing.id)", body: body)
            } else {
                let _: JSONAck = try await app.api.post("/v1/accounts", body: body)
            }
            await app.refreshAll(silent: true)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func remove() async {
        guard let existing else { return }
        do {
            let _: JSONAck = try await app.api.delete("/v1/accounts/\(existing.id)")
            await app.refreshAll(silent: true)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct ImportSheet: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var picking = false
    @State private var table: [[String]] = []
    @State private var dateCol = 0
    @State private var merchantCol = 1
    @State private var amountCol = 2
    @State private var categoryCol = -1
    @State private var flip = false
    @State private var working = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Use columns for date, merchant, amount, and an optional category. A header row is detected when it says date or amount.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.muted)
                    OutlineButton(title: table.isEmpty ? "Choose CSV" : "Choose a different file", system: "doc") { picking = true }
                    if !table.isEmpty {
                        columnPicker("Date", selection: $dateCol)
                        columnPicker("Merchant", selection: $merchantCol)
                        columnPicker("Amount", selection: $amountCol)
                        columnPicker("Category", selection: $categoryCol, allowNone: true)
                        Toggle("Flip signs (negative amounts are expenses)", isOn: $flip)
                            .font(.system(size: 14, weight: .medium))
                        Text("\(prepared.count) rows ready")
                            .font(.system(size: 13, weight: .bold))
                        ForEach(Array(prepared.prefix(3).enumerated()), id: \.offset) { _, row in
                            Text("\(row.date) · \(row.merchant) · \(Money.format(row.amountCents))")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Theme.muted)
                        }
                        if let error {
                            Text(error).foregroundStyle(Theme.bad).font(.system(size: 13, weight: .semibold))
                        }
                        PrimaryButton(title: working ? "Importing…" : "Import") { Task { await runImport() } }
                            .disabled(working || prepared.isEmpty)
                    }
                }
                .padding(16)
            }
            .background(Theme.bg)
            .navigationTitle("Import CSV")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .fileImporter(isPresented: $picking, allowedContentTypes: csvTypes, allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first { load(url) }
                case .failure(let failure):
                    error = failure.localizedDescription
                }
            }
        }
    }

    private var csvTypes: [UTType] {
        var types: [UTType] = [.commaSeparatedText, .plainText]
        if let csv = UTType(filenameExtension: "csv") { types.append(csv) }
        return types
    }

    private var headers: [String] {
        guard let first = table.first else { return [] }
        return first.enumerated().map { index, value in
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? "Column \(index + 1)" : trimmed
        }
    }

    private var hasHeader: Bool {
        let joined = headers.joined(separator: " ").lowercased()
        return joined.contains("date") || joined.contains("amount") || joined.contains("merchant")
    }

    private var dataRows: ArraySlice<[String]> {
        hasHeader ? table.dropFirst() : ArraySlice(table)
    }

    private var prepared: [ImportRowBody] {
        dataRows.compactMap { row in
            guard dateCol < row.count, merchantCol < row.count, amountCol < row.count else { return nil }
            guard let day = Dates.flexibleDay(row[dateCol]) else { return nil }
            let merchant = row[merchantCol].trimmingCharacters(in: .whitespaces)
            guard !merchant.isEmpty else { return nil }
            guard let parsed = parseAmount(row[amountCol]) else { return nil }
            let category: String? = {
                guard categoryCol >= 0, categoryCol < row.count else { return nil }
                let value = row[categoryCol].trimmingCharacters(in: .whitespaces)
                return value.isEmpty ? nil : value
            }()
            return ImportRowBody(date: day, merchant: merchant, amountCents: parsed.cents, category: category, kind: parsed.kind)
        }
    }

    private func columnPicker(_ title: String, selection: Binding<Int>, allowNone: Bool = false) -> some View {
        Picker(title, selection: selection) {
            if allowNone { Text("None").tag(-1) }
            ForEach(Array(headers.enumerated()), id: \.offset) { index, header in
                Text(header).tag(index)
            }
        }
    }

    private func load(_ url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? (try? String(contentsOf: url, encoding: .utf16))
        guard let text else {
            error = "Couldn't read that file."
            return
        }
        let rows = CSVParser.rows(text.replacingOccurrences(of: "\u{feff}", with: ""))
        guard rows.count > 1 || (rows.count == 1 && !looksLikeHeader(rows[0])) else {
            error = "That file doesn't have any rows."
            table = []
            return
        }
        table = rows
        guessColumns()
        error = nil
    }

    private func looksLikeHeader(_ row: [String]) -> Bool {
        row.joined(separator: " ").lowercased().contains("date")
    }

    private func guessColumns() {
        let labels = headers.map { $0.lowercased() }
        if let index = labels.firstIndex(where: { $0.contains("date") }) { dateCol = index }
        if let index = labels.firstIndex(where: { $0.contains("merchant") || $0.contains("description") || $0.contains("name") || $0.contains("payee") }) {
            merchantCol = index
        }
        if let index = labels.firstIndex(where: { $0.contains("amount") || $0.contains("debit") }) { amountCol = index }
        if let index = labels.firstIndex(where: { $0.contains("category") || $0.contains("type") }) {
            categoryCol = index
        } else {
            categoryCol = -1
        }
    }

    private func parseAmount(_ raw: String) -> (cents: Int, kind: String)? {
        var text = raw.trimmingCharacters(in: .whitespaces)
        var negative = false
        if text.hasPrefix("(") && text.hasSuffix(")") {
            negative = true
            text = String(text.dropFirst().dropLast())
        }
        text = text.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "").replacingOccurrences(of: " ", with: "")
        if text.hasPrefix("+") { text.removeFirst() }
        if text.hasPrefix("-") {
            negative = true
            text.removeFirst()
        }
        guard let value = Double(text) else { return nil }
        if flip { negative.toggle() }
        let cents = Int((value * 100).rounded())
        return (cents, negative ? "income" : "expense")
    }

    private func runImport() async {
        working = true
        defer { working = false }
        if await app.importRows(prepared) != nil {
            dismiss()
        } else {
            error = app.banner
        }
    }
}
