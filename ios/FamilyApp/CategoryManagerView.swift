import SwiftUI

struct CategoryManagerView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var editing: CategorySpend?
    @State private var creating = false
    @State private var pending: CategorySpend?

    private var categories: [CategorySpend] { app.budget?.categories ?? [] }

    var body: some View {
        NavigationStack {
            List {
                Section("Categories") {
                    ForEach(categories) { category in
                        Button { editing = category } label: {
                            HStack {
                                Circle().fill(Color(hexString: category.color)).frame(width: 12, height: 12)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(category.name).foregroundStyle(Theme.text)
                                    Text("\(Money.format(category.budgetCents)) / month")
                                        .font(.caption)
                                        .foregroundStyle(Theme.muted)
                                }
                                Spacer()
                                Image(systemName: "line.3.horizontal")
                                    .foregroundStyle(Theme.soft)
                            }
                        }
                        .swipeActions {
                            Button(role: .destructive) { pending = category } label: { Text("Delete") }
                        }
                    }
                    .onMove(perform: move)
                }
                Section("Transaction classification") {
                    NavigationLink {
                        TransactionRulesView()
                    } label: {
                        Label("Edit transaction rules", systemImage: "line.3.horizontal.decrease.circle")
                    }
                    Text("Classify expenses, irregular income, and transfers. Rules can also fix existing transactions.")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                }
            }
            .navigationTitle("Categories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button { creating = true } label: { Image(systemName: "plus") }
                }
            }
            .environment(\.editMode, .constant(.active))
            .sheet(isPresented: $creating) { CategoryEditor(existing: nil) }
            .sheet(item: $editing) { category in CategoryEditor(existing: category) }
            .confirmationDialog(
                "Delete \(pending?.name ?? "category")?",
                isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
                titleVisibility: .visible
            ) {
                Button("Move spending to Uncategorized", role: .destructive) {
                    if let pending { Task { await remove(pending, reassign: "uncategorized") } }
                }
                ForEach(categories.filter { $0.id != pending?.id }) { category in
                    Button("Move spending to \(category.name)") {
                        if let pending { Task { await remove(pending, reassign: category.id) } }
                    }
                }
                Button("Cancel", role: .cancel) { pending = nil }
            } message: {
                Text("Choose where this category's transactions go.")
            }
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        var ids = categories.map(\.id)
        ids.move(fromOffsets: source, toOffset: destination)
        Task {
            do {
                let _: JSONAck = try await app.api.put("/v1/categories/order", body: OrderBody(ids: ids))
                await app.refreshAll(silent: true)
            } catch {
                app.report(error)
            }
        }
    }

    private func remove(_ category: CategorySpend, reassign: String) async {
        pending = nil
        do {
            let _: JSONAck = try await app.api.delete("/v1/categories/\(category.id)?reassign_to=\(reassign)")
            await app.refreshAll(silent: true)
        } catch {
            app.report(error)
        }
    }

}

struct CategoryEditor: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    var existing: CategorySpend?
    @State private var name = ""
    @State private var color = "#0d9488"
    @State private var icon = "tag.fill"
    @State private var budget = ""
    @State private var error: String?
    private let colors = ["#0d9488", "#e11d48", "#d97706", "#475569", "#7c3aed", "#be185d", "#4f46e5", "#ea580c", "#2563eb"]
    private let icons = ["cart.fill", "fork.knife", "fuelpump.fill", "house.fill", "person.2.fill", "heart.fill", "tag.fill", "paperplane.fill", "creditcard.fill", "bolt.fill"]

    var body: some View {
        EditorChrome(title: existing == nil ? "New category" : "Edit category", working: false, error: error, onSave: { Task { await save() } }) {
            LabeledInput(title: "Name", text: $name, autocap: .words)
            LabeledInput(title: "Monthly budget", text: $budget, keyboard: .decimalPad, autocap: .never)
            HStack(spacing: 8) {
                ForEach(colors, id: \.self) { item in
                    Button { color = item } label: {
                        Circle().fill(Color(hexString: item)).frame(width: 26, height: 26)
                            .overlay(Circle().stroke(Color.white, lineWidth: color == item ? 3 : 0))
                    }
                    .buttonStyle(.plain)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(icons, id: \.self) { item in
                        Button { icon = item } label: {
                            Image(systemName: item)
                                .frame(width: 36, height: 36)
                                .background(icon == item ? Theme.safeBg : Theme.panel2, in: RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .onAppear {
            if let existing {
                name = existing.name
                color = existing.color
                icon = existing.icon
                budget = Money.plain(existing.defaultBudgetCents)
            }
        }
    }

    private func save() async {
        let cents = Money.cents(from: budget.isEmpty ? "0" : budget) ?? -1
        guard cents >= 0, !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            error = "Name and budget are required."
            return
        }
        do {
            if let existing {
                let _: CreatedId = try await app.api.patch(
                    "/v1/categories/\(existing.id)",
                    body: CategoryBody(name: name, color: color, icon: icon, defaultBudgetCents: cents)
                )
            } else {
                let created: CreatedId = try await app.api.post(
                    "/v1/categories",
                    body: CategoryBody(name: name, color: color, icon: icon, defaultBudgetCents: cents)
                )
                let _: JSONAck = try await app.api.put(
                    "/v1/categories/\(created.id ?? "")/budget",
                    body: BudgetSetBody(month: app.budgetMonth, amountCents: cents, setDefault: true)
                )
            }
            await app.refreshAll(silent: true)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
