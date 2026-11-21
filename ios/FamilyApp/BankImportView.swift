import SwiftUI
import UniformTypeIdentifiers

struct BankImportView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var picking = false
    @State private var preview: ImportPreview?
    @State private var dateCol = 0
    @State private var descriptionCol = 1
    @State private var amountCol = 2
    @State private var debitCol = -1
    @State private var creditCol = -1
    @State private var flip = false
    @State private var working = false
    @State private var error: String?
    @State private var result: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Upload a bank or card export. CSV and Excel (.xlsx) are read on the server. Columns are guessed, then you confirm them. Rows already in the family ledger are skipped.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.muted)
                    OutlineButton(title: "Choose CSV or Excel", system: "square.and.arrow.down") { picking = true }
                    if let preview {
                        Text("\(preview.filename) · \(preview.rowCount) rows")
                            .font(.system(size: 14, weight: .bold))
                        picker("Date", selection: $dateCol, columns: preview.columns, allowNone: false)
                        picker("Description", selection: $descriptionCol, columns: preview.columns, allowNone: false)
                        picker("Amount", selection: $amountCol, columns: preview.columns, allowNone: true)
                        picker("Debit", selection: $debitCol, columns: preview.columns, allowNone: true)
                        picker("Credit", selection: $creditCol, columns: preview.columns, allowNone: true)
                        Toggle("Flip signs (negative amounts are expenses)", isOn: $flip)
                        ForEach(Array(preview.sample.prefix(3).enumerated()), id: \.offset) { _, row in
                            Text(row.joined(separator: " · "))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Theme.muted)
                                .lineLimit(2)
                        }
                        PrimaryButton(title: working ? "Importing…" : "Import") { Task { await commit(preview) } }
                            .disabled(working)
                    }
                    if let result {
                        Text(result).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.good)
                    }
                    if let error {
                        Text(error).foregroundStyle(Theme.bad).font(.system(size: 13, weight: .semibold))
                    }
                }
                .padding(16)
            }
            .background(Theme.bg)
            .navigationTitle("Import bank file")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .fileImporter(isPresented: $picking, allowedContentTypes: types, allowsMultipleSelection: false) { result in
                if case .success(let urls) = result, let url = urls.first {
                    Task { await upload(url) }
                }
            }
        }
    }

    private var types: [UTType] {
        var list: [UTType] = [.commaSeparatedText, .plainText]
        if let csv = UTType(filenameExtension: "csv") { list.append(csv) }
        if let xlsx = UTType(filenameExtension: "xlsx") { list.append(xlsx) }
        return list
    }

    private func picker(_ title: String, selection: Binding<Int>, columns: [String], allowNone: Bool) -> some View {
        Picker(title, selection: selection) {
            if allowNone { Text("None").tag(-1) }
            ForEach(Array(columns.enumerated()), id: \.offset) { index, name in
                Text(name).tag(index)
            }
        }
    }

    private func upload(_ url: URL) async {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            error = "Couldn't read that file."
            return
        }
        let name = url.lastPathComponent
        let mime = name.lowercased().hasSuffix("xlsx")
            ? "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
            : "text/csv"
        do {
            let parsed: ImportPreview = try await app.api.upload("/v1/imports/parse", filename: name, data: data, mime: mime)
            preview = parsed
            dateCol = parsed.suggested.dateColumn
            descriptionCol = parsed.suggested.descriptionColumn
            amountCol = parsed.suggested.amountColumn ?? -1
            debitCol = parsed.suggested.debitColumn ?? -1
            creditCol = parsed.suggested.creditColumn ?? -1
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func commit(_ preview: ImportPreview) async {
        working = true
        defer { working = false }
        let body = ImportCommitBody(
            dateColumn: dateCol,
            descriptionColumn: descriptionCol,
            amountColumn: amountCol >= 0 ? amountCol : nil,
            debitColumn: debitCol >= 0 ? debitCol : nil,
            creditColumn: creditCol >= 0 ? creditCol : nil,
            flipSigns: flip,
            hasHeader: true
        )
        do {
            let done: ImportCommitResult = try await app.api.post("/v1/imports/\(preview.importId)/commit", body: body)
            result = "Imported \(done.imported). Skipped \(done.skipped) duplicates. Categorized \(done.categorized)."
            await app.refreshAll(silent: true)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
