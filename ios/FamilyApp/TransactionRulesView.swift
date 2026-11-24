import SwiftUI

struct TransactionRulesView: View {
    @EnvironmentObject private var app: AppModel
    @State private var rules: [TransactionRule] = []
    @State private var editingRule: TransactionRule?
    @State private var addRule = false
    @State private var error: String?

    var body: some View {
        List {
            Section {
                Text("Match text in the merchant or description. More-specific patterns win. Use an inflow rule for irregular Venmo deposits; use transfer rules for movements between accounts.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Rules") {
                if rules.isEmpty {
                    Text("No custom rules yet. Unmatched deposits remain income by default.")
                        .foregroundStyle(.secondary)
                }
                ForEach(rules) { rule in
                    Button { editingRule = rule } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(rule.pattern)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(summary(rule))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button(role: .destructive) { Task { await delete(rule) } } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }

            if let error {
                Section { Text(error).font(.footnote).foregroundStyle(.red) }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Transaction rules")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { addRule = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add transaction rule")
            }
        }
        .task { await load() }
        .sheet(isPresented: $addRule) {
            TransactionRuleEditor(existing: nil) { await load() }
        }
        .sheet(item: $editingRule) { rule in
            TransactionRuleEditor(existing: rule) { await load() }
        }
    }

    private func summary(_ rule: TransactionRule) -> String {
        let direction = rule.flowDirection == "any" ? "Any direction" : rule.flowDirection.capitalized
        let category = rule.categoryName.map { " · \($0)" } ?? ""
        return "\(rule.kind.capitalized) · \(direction)\(category)"
    }

    private func load() async {
        do {
            let response: TransactionRuleList = try await app.api.get("/v1/transaction-rules")
            rules = response.rules
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func delete(_ rule: TransactionRule) async {
        do {
            let _: JSONAck = try await app.api.delete("/v1/transaction-rules/\(rule.id)")
            await load()
        } catch {
            error = error.localizedDescription
        }
    }
}

private struct TransactionRuleEditor: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    var existing: TransactionRule?
    var onSaved: () async -> Void

    @State private var pattern = ""
    @State private var kind = "expense"
    @State private var flowDirection = "any"
    @State private var categoryId = ""
    @State private var applyToExisting = false
    @State private var working = false
    @State private var error: String?

    private var categories: [CategorySpend] { app.budget?.categories ?? [] }

    var body: some View {
        NavigationStack {
            Form {
                Section("Match") {
                    TextField("Merchant contains…", text: $pattern)
                        .textInputAutocapitalization(.words)
                    Picker("Flow", selection: $flowDirection) {
                        Text("Any").tag("any")
                        Text("Money out").tag("outflow")
                        Text("Money in").tag("inflow")
                    }
                }
                Section("Classify as") {
                    Picker("Type", selection: $kind) {
                        Text("Expense").tag("expense")
                        Text("Income").tag("income")
                        Text("Transfer").tag("transfer")
                    }
                    if kind == "expense" {
                        Picker("Category", selection: $categoryId) {
                            Text("Choose a category").tag("")
                            ForEach(categories) { category in
                                Text(category.name).tag(category.id)
                            }
                        }
                    } else if kind == "transfer" {
                        Text("Transfers stay in the ledger but do not count as spending or income.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Income is not assigned an expense category. Irregular deposits do not need a planned income entry.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Section {
                    Toggle("Apply to existing transactions", isOn: $applyToExisting)
                    Text("Only transactions where this is the winning rule will change. Review the ledger afterward.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let error {
                    Section { Text(error).font(.footnote).foregroundStyle(.red) }
                }
            }
            .navigationTitle(existing == nil ? "New rule" : "Edit rule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(working ? "Saving…" : "Save") { Task { await save() } }
                        .disabled(working)
                }
            }
            .onAppear(perform: loadExisting)
        }
    }

    private func loadExisting() {
        guard let existing else { return }
        pattern = existing.pattern
        kind = existing.kind
        flowDirection = existing.flowDirection
        categoryId = existing.categoryId ?? ""
    }

    private func save() async {
        let cleanPattern = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanPattern.count >= 2 else { error = "Use at least two characters for a match."; return }
        guard kind != "expense" || !categoryId.isEmpty else { error = "Choose a category for expense rules."; return }
        working = true
        defer { working = false }
        let body = TransactionRuleBody(
            pattern: cleanPattern,
            kind: kind,
            flowDirection: flowDirection,
            categoryId: kind == "expense" ? categoryId : nil,
            applyToExisting: applyToExisting
        )
        do {
            if let existing {
                let patch = TransactionRulePatchBody(
                    pattern: body.pattern,
                    kind: body.kind,
                    flowDirection: body.flowDirection,
                    categoryId: body.categoryId,
                    applyToExisting: body.applyToExisting
                )
                let _: JSONAck = try await app.api.patch("/v1/transaction-rules/\(existing.id)", body: patch)
            } else {
                let _: JSONAck = try await app.api.post("/v1/transaction-rules", body: body)
            }
            await onSaved()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
