import SwiftUI

struct CategoryTransactionsView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    var category: CategorySpend
    var month: String

    @State private var transactions: [Txn] = []
    @State private var editing: Txn?
    @State private var error: String?
    @State private var loading = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        IconTile(
                            system: category.icon,
                            colors: [Color(hexString: category.color), Color(hexString: category.color)],
                            size: 40
                        )
                        VStack(alignment: .leading, spacing: 3) {
                            Text(category.name)
                                .font(.headline)
                            Text(Dates.prettyMonth(month))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(Money.format(transactions.reduce(0) { $0 + $1.amountCents }))
                            .font(.headline)
                    }
                    .padding(.vertical, 4)
                }

                Section("Transactions") {
                    if loading && transactions.isEmpty {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else if transactions.isEmpty {
                        Text(error ?? "No transactions in this category this month.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(transactions) { transaction in
                            Button { editing = transaction } label: {
                                transactionRow(transaction)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Category activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .refreshable { await load() }
            .task { await load() }
            .sheet(item: $editing, onDismiss: { Task { await load() } }) { transaction in
                TransactionEditor(existing: transaction)
            }
        }
    }

    private func transactionRow(_ transaction: Txn) -> some View {
        HStack(spacing: 12) {
            Image(systemName: transaction.kind == "income" ? "arrow.down.left" : "arrow.up.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(transaction.kind == "income" ? Theme.good : Theme.accent2)
                .frame(width: 36, height: 36)
                .background(Theme.panel2, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(transaction.merchant)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.text)
                Text(Dates.shortDay(transaction.occurredOn) + (transaction.note.map { " · \($0)" } ?? ""))
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Text(Money.format(transaction.amountCents, showCents: true))
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.text)
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            let result: TransactionList = try await app.api.get(
                "/v1/transactions?month=\(month)&category_id=\(category.id)&limit=1000"
            )
            transactions = result.transactions.filter { $0.categoryId == category.id }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
