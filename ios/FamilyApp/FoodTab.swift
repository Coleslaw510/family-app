import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct FoodTabView: View {
    @EnvironmentObject private var app: AppModel
    @State private var bundle: FoodBundle?
    @State private var memberId = ""
    @State private var day = Date()
    @State private var settings = false
    @State private var editor: FoodDraft?
    @State private var showScan = false
    @State private var showPhoto = false
    @State private var showImport = false
    @State private var dinnerTitle = ""
    @State private var grocery = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Food")
                        .font(.system(size: 28, weight: .heavy))
                        .tracking(-0.6)
                    Spacer()
                    GearButton { settings = true }
                }
                Picker("Who", selection: $memberId) {
                    ForEach(app.members) { member in
                        Text(member.name).tag(member.id)
                    }
                }
                .pickerStyle(.segmented)
                HStack {
                    Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                    Spacer()
                    Text(Dates.longDay(day)).font(.system(size: 15, weight: .bold))
                    Spacer()
                    Button { shift(1) } label: { Image(systemName: "chevron.right") }
                }
                .foregroundStyle(Theme.text)
                if let bundle {
                    totals(bundle)
                    actions
                    favorites(bundle)
                    entries(bundle)
                    history(bundle)
                    dinner(bundle)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Theme.bg)
        .refreshable { await reload() }
        .task(id: "\(memberId)|\(Dates.isoDay(day))") { await reload() }
        .onAppear { if memberId.isEmpty { memberId = app.member?.id ?? "" } }
        .sheet(isPresented: $settings) { SettingsView() }
        .sheet(item: $editor) { draft in FoodEditor(draft: draft, day: Dates.isoDay(day)) { Task { await reload() } } }
        .sheet(isPresented: $showScan) { BarcodeMealSheet(day: Dates.isoDay(day)) { Task { await reload() } } }
        .sheet(isPresented: $showPhoto) { PhotoMealSheet(day: Dates.isoDay(day)) { Task { await reload() } } }
        .sheet(isPresented: $showImport) { GrindImportSheet { Task { await reload() } } }
    }

    private func totals(_ bundle: FoodBundle) -> some View {
        let left = bundle.goals.calories - bundle.totals.calories
        return Card {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(bundle.totals.calories) kcal")
                    .font(.system(size: 28, weight: .heavy))
                Text("\(left) left of \(bundle.goals.calories)")
                    .foregroundStyle(left >= 0 ? Theme.muted : Theme.bad)
                Text("Protein \(bundle.totals.protein) / \(bundle.goals.protein) g · Carbs \(bundle.totals.carbs) · Fat \(bundle.totals.fat)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.muted)
                Stepper("Water \(bundle.waterCups) of \(bundle.goals.water) cups", value: Binding(
                    get: { bundle.waterCups },
                    set: { newValue in Task { await setWater(newValue) } }
                ), in: 0...30)
                .disabled(memberId != app.member?.id)
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 8) {
            PrimaryButton(title: "Log food", system: "plus") { editor = FoodDraft() }
                .disabled(memberId != app.member?.id)
            OutlineButton(title: "Photo or description", system: "camera") { showPhoto = true }
                .disabled(memberId != app.member?.id)
            OutlineButton(title: "Scan barcode", system: "barcode.viewfinder") { showScan = true }
                .disabled(memberId != app.member?.id)
            OutlineButton(title: "Import Grind Szn JSON", system: "square.and.arrow.down") { showImport = true }
                .disabled(memberId != app.member?.id)
        }
    }

    private func favorites(_ bundle: FoodBundle) -> some View {
        Group {
            if !bundle.favorites.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Favorites").font(.system(size: 15, weight: .bold))
                        ForEach(bundle.favorites) { item in
                            Button { Task { await logFavorite(item) } } label: {
                                HStack {
                                    Image(systemName: "star.fill").foregroundStyle(Theme.warn)
                                    VStack(alignment: .leading) {
                                        Text(item.name).foregroundStyle(Theme.text)
                                        Text("\(item.calories) kcal · P \(item.protein)").font(.caption).foregroundStyle(Theme.muted)
                                    }
                                    Spacer()
                                    Image(systemName: "plus.circle.fill").foregroundStyle(Theme.accent)
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(memberId != app.member?.id)
                        }
                    }
                }
            }
        }
    }

    private func entries(_ bundle: FoodBundle) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("Today").font(.system(size: 15, weight: .bold))
                if bundle.entries.isEmpty {
                    Text("Nothing logged this day.").foregroundStyle(Theme.muted)
                }
                ForEach(bundle.entries) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name).font(.system(size: 15, weight: .bold))
                            Text("\(item.meal) · P \(item.protein) · C \(item.carbs) · F \(item.fat)")
                                .font(.caption)
                                .foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        Text("\(item.calories)")
                            .font(.system(size: 15, weight: .heavy))
                        if memberId == app.member?.id {
                            Button { editor = FoodDraft(item: item) } label: { Image(systemName: "pencil").foregroundStyle(Theme.muted) }
                                .buttonStyle(.plain)
                            Button { Task { await deleteEntry(item) } } label: { Image(systemName: "trash").foregroundStyle(Theme.soft) }
                                .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func history(_ bundle: FoodBundle) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                Text("History").font(.system(size: 15, weight: .bold))
                ForEach(bundle.history.prefix(14)) { day in
                    HStack {
                        Text(Dates.shortDay(day.day))
                        Spacer()
                        Text("\(day.calories) kcal · P \(day.protein) g")
                            .foregroundStyle(Theme.muted)
                    }
                    .font(.system(size: 13, weight: .medium))
                }
            }
        }
    }

    private func dinner(_ bundle: FoodBundle) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("Tonight's dinner").font(.system(size: 15, weight: .bold))
                Text("Shared with the household. Logging it can add the meal to one or both of you, and grocery lines go on the family list.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.muted)
                ForEach(bundle.dinners) { plan in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(plan.title).font(.system(size: 15, weight: .bold))
                        if let notes = plan.notes { Text(notes).foregroundStyle(Theme.muted) }
                        HStack {
                            Button("Log for me") { Task { await logDinner(plan, ids: [app.member?.id ?? ""]) } }
                            Button("Log for both") { Task { await logDinner(plan, ids: app.members.map(\.id)) } }
                        }
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.accent2)
                    }
                }
                LabeledInput(title: "Dinner", text: $dinnerTitle, autocap: .words)
                LabeledInput(title: "Grocery lines, comma separated", text: $grocery, autocap: .words)
                OutlineButton(title: "Save dinner plan", system: "fork.knife") { Task { await saveDinner() } }
            }
        }
    }

    private func shift(_ delta: Int) {
        day = Calendar.current.date(byAdding: .day, value: delta, to: day) ?? day
    }

    private func reload() async {
        guard !memberId.isEmpty else { return }
        let path = "/v1/food?day=\(Dates.isoDay(day))&member_id=\(memberId)"
        if let loaded: FoodBundle = try? await app.api.get(path) {
            bundle = loaded
            if Dates.isoDay(day) == Dates.isoDay(Date()), memberId == app.member?.id {
                app.food = loaded
            }
        }
    }

    private func setWater(_ cups: Int) async {
        do {
            let _: JSONAck = try await app.api.put("/v1/food/water", body: WaterBody(dayOn: Dates.isoDay(day), cups: cups))
            await reload()
        } catch { app.report(error) }
    }

    private func deleteEntry(_ item: FoodItem) async {
        do {
            let _: JSONAck = try await app.api.delete("/v1/food/entries/\(item.id)")
            await reload()
        } catch { app.report(error) }
    }

    private func logFavorite(_ item: FoodItem) async {
        let body = FoodBody(dayOn: Dates.isoDay(day), name: item.name, meal: item.meal, calories: item.calories, protein: item.protein, carbs: item.carbs, fat: item.fat, serving: item.serving)
        do {
            let _: JSONAck = try await app.api.post("/v1/food/entries", body: body)
            await reload()
        } catch { app.report(error) }
    }

    private func saveDinner() async {
        let title = dinnerTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        do {
            let created: CreatedId = try await app.api.post("/v1/dinners", body: DinnerBody(dayOn: Dates.isoDay(day), title: title, notes: nil))
            let items = grocery.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            if let id = created.id, !items.isEmpty {
                let _: JSONAck = try await app.api.post("/v1/dinners/\(id)/grocery", body: GroceryItemsBody(items: items))
            }
            dinnerTitle = ""
            grocery = ""
            await reload()
            await app.refreshAll(silent: true)
        } catch { app.report(error) }
    }

    private func logDinner(_ plan: DinnerPlan, ids: [String]) async {
        do {
            let _: JSONAck = try await app.api.post(
                "/v1/dinners/\(plan.id)/log",
                body: DinnerLogBody(memberIds: ids.filter { !$0.isEmpty }, calories: 0, protein: 0, carbs: 0, fat: 0)
            )
            await reload()
        } catch { app.report(error) }
    }
}

struct FoodDraft: Identifiable {
    var id = UUID().uuidString
    var entryId: String?
    var name = ""
    var meal = "Lunch"
    var calories = ""
    var protein = ""
    var carbs = ""
    var fat = ""
    var serving = ""
    var favorite = false
    init() {}
    init(item: FoodItem) {
        entryId = item.id
        name = item.name
        meal = item.meal
        calories = String(item.calories)
        protein = String(item.protein)
        carbs = String(item.carbs)
        fat = String(item.fat)
        serving = item.serving ?? ""
    }
    init(estimate: MealEstimate) {
        name = estimate.mealName
        calories = String(Int(estimate.calories.rounded()))
        protein = String(Int(estimate.proteinG.rounded()))
        carbs = String(Int(estimate.carbsG.rounded()))
        fat = String(Int(estimate.fatG.rounded()))
        serving = estimate.items.map { "\($0.name) \($0.estimatedPortion)" }.joined(separator: ", ")
    }
}

struct FoodEditor: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State var draft: FoodDraft
    var day: String
    var onSaved: () -> Void
    @State private var error: String?

    var body: some View {
        EditorChrome(title: draft.entryId == nil ? "Log food" : "Edit food", working: false, error: error, onSave: { Task { await save() } }) {
            LabeledInput(title: "Name", text: $draft.name, autocap: .words)
            Picker("Meal", selection: $draft.meal) {
                ForEach(["Breakfast", "Lunch", "Dinner", "Snack"], id: \.self) { Text($0) }
            }
            LabeledInput(title: "Calories", text: $draft.calories, keyboard: .numberPad, autocap: .never)
            LabeledInput(title: "Protein g", text: $draft.protein, keyboard: .numberPad, autocap: .never)
            LabeledInput(title: "Carbs g", text: $draft.carbs, keyboard: .numberPad, autocap: .never)
            LabeledInput(title: "Fat g", text: $draft.fat, keyboard: .numberPad, autocap: .never)
            LabeledInput(title: "Serving", text: $draft.serving)
            if draft.entryId == nil {
                Toggle("Save as a favorite", isOn: $draft.favorite)
            }
        }
    }

    private func save() async {
        guard let calories = Int(draft.calories) else { error = "Enter calories."; return }
        let body = FoodBody(
            dayOn: day,
            name: draft.name,
            meal: draft.meal,
            calories: calories,
            protein: Int(draft.protein) ?? 0,
            carbs: Int(draft.carbs) ?? 0,
            fat: Int(draft.fat) ?? 0,
            serving: draft.serving
        )
        do {
            if let entryId = draft.entryId {
                let _: JSONAck = try await app.api.patch("/v1/food/entries/\(entryId)", body: body)
            } else {
                let _: JSONAck = try await app.api.post("/v1/food/entries", body: body)
                if draft.favorite {
                    let _: JSONAck = try await app.api.post("/v1/food/favorites", body: body)
                }
            }
            onSaved()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct PhotoMealSheet: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    var day: String
    var onSaved: () -> Void
    @State private var note = ""
    @State private var picker: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var estimate: MealEstimate?
    @State private var working = false
    @State private var error: String?
    @State private var review: FoodDraft?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("A photo or a description. You review the estimate before it is saved. Photos are not stored.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.muted)
                    if let image {
                        Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 180).clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    PhotosPicker("Choose a photo", selection: $picker, matching: .images)
                    LabeledInput(title: "Description", text: $note)
                    PrimaryButton(title: working ? "Estimating…" : "Estimate") { Task { await estimateMeal() } }
                        .disabled(working)
                    if let estimate {
                        Text(estimate.mealName).font(.system(size: 16, weight: .bold))
                        Text("\(Int(estimate.calories.rounded())) kcal · P \(Int(estimate.proteinG.rounded())) · C \(Int(estimate.carbsG.rounded())) · F \(Int(estimate.fatG.rounded()))")
                            .foregroundStyle(Theme.muted)
                        ForEach(Array(estimate.items.enumerated()), id: \.offset) { _, item in
                            Text("\(item.name) · \(item.estimatedPortion)").font(.system(size: 13))
                        }
                        OutlineButton(title: "Review and save", system: "checkmark") { review = FoodDraft(estimate: estimate) }
                    }
                    if let error { Text(error).foregroundStyle(Theme.bad) }
                }
                .padding(16)
            }
            .background(Theme.bg)
            .navigationTitle("Estimate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .onChange(of: picker) { item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let ui = UIImage(data: data) {
                        image = ui
                    }
                }
            }
            .sheet(item: $review) { draft in
                FoodEditor(draft: draft, day: day) {
                    onSaved()
                    dismiss()
                }
            }
        }
    }

    private func estimateMeal() async {
        working = true
        defer { working = false }
        do {
            let jpeg = image.flatMap { compressed($0) }
            let result: MealEstimate
            if let jpeg {
                result = try await app.api.uploadForm(
                    "/v1/food/estimate",
                    fields: ["description": note],
                    fileField: "image",
                    filename: "meal.jpg",
                    data: jpeg,
                    mime: "image/jpeg"
                )
            } else {
                result = try await app.api.postForm("/v1/food/estimate", fields: ["description": note])
            }
            estimate = result
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func compressed(_ image: UIImage) -> Data? {
        let maxSide: CGFloat = 1280
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        let rendered = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        return rendered.jpegData(compressionQuality: 0.78)
    }
}

struct BarcodeMealSheet: View {
    @Environment(\.dismiss) private var dismiss
    var day: String
    var onSaved: () -> Void
    @State private var manual = ""
    @State private var product: ProductFacts?
    @State private var servings = 1.0
    @State private var error: String?
    @State private var review: FoodDraft?
    @State private var scanning = true

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                if scanning {
                    BarcodeCapture { code in
                        scanning = false
                        Task { await lookup(code) }
                    }
                    .frame(height: 280)
                }
                LabeledInput(title: "Or type the barcode", text: $manual, keyboard: .numberPad, autocap: .never)
                    .padding(.horizontal, 16)
                OutlineButton(title: "Look up", system: "magnifyingglass") { Task { await lookup(manual) } }
                    .padding(.horizontal, 16)
                if let product {
                    Text(product.name).font(.system(size: 16, weight: .bold)).padding(.horizontal, 16)
                    Text(product.servingLabel).foregroundStyle(Theme.muted).padding(.horizontal, 16)
                    Stepper("Servings \(servings, specifier: "%.1f")", value: $servings, in: 0.5...10, step: 0.5)
                        .padding(.horizontal, 16)
                    Text("Open Food Facts. Check the package before saving.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.soft)
                        .padding(.horizontal, 16)
                    PrimaryButton(title: "Review numbers") { review = draft(product) }
                        .padding(.horizontal, 16)
                }
                if let error { Text(error).foregroundStyle(Theme.bad).padding(.horizontal, 16) }
                Spacer()
            }
            .background(Theme.bg)
            .navigationTitle("Barcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .sheet(item: $review) { draft in
                FoodEditor(draft: draft, day: day) {
                    onSaved()
                    dismiss()
                }
            }
        }
    }

    private func lookup(_ code: String) async {
        do {
            product = try await OpenFoodFacts.lookup(code: code)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func draft(_ product: ProductFacts) -> FoodDraft {
        let base = product.perServing ?? product.per100 ?? NutrientAmounts(calories: 0, protein: 0, carbs: 0, fat: 0)
        let scaled = base.scaled(servings)
        var draft = FoodDraft()
        draft.name = product.name
        draft.calories = String(Int(scaled.calories.rounded()))
        draft.protein = String(Int(scaled.protein.rounded()))
        draft.carbs = String(Int(scaled.carbs.rounded()))
        draft.fat = String(Int(scaled.fat.rounded()))
        draft.serving = "\(servings) × \(product.servingLabel)"
        return draft
    }
}

struct GrindImportSheet: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    var onSaved: () -> Void
    @State private var picking = false
    @State private var message: String?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Imports foods, water, favorites, and goals from a Grind Szn JSON export (schema 1–4) onto you. Workouts, weight, and grades stay out.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.muted)
                OutlineButton(title: "Choose JSON", system: "doc") { picking = true }
                if let message { Text(message).foregroundStyle(Theme.good) }
                if let error { Text(error).foregroundStyle(Theme.bad) }
                Spacer()
            }
            .padding(16)
            .background(Theme.bg)
            .navigationTitle("Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .fileImporter(isPresented: $picking, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
                if case .success(let urls) = result, let url = urls.first {
                    Task { await load(url) }
                }
            }
        }
    }

    private func load(_ url: URL) async {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            error = "That file isn't JSON."
            return
        }
        do {
            let _: JSONAck = try await app.api.post("/v1/food/import", body: AnyJSON(object))
            message = "Imported."
            onSaved()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Sends a decoded JSON object without reshaping keys.
struct AnyJSON: Encodable {
    var value: Any
    init(_ value: Any) { self.value = value }
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let dict = value as? [String: Any] {
            try container.encode(JSONObject(dict))
        } else {
            throw EncodingError.invalidValue(value, .init(codingPath: [], debugDescription: "Expected an object"))
        }
    }
}

struct JSONObject: Encodable {
    var dict: [String: Any]
    init(_ dict: [String: Any]) { self.dict = dict }
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: JSONKey.self)
        for (key, value) in dict {
            let codingKey = JSONKey(key)
            switch value {
            case let text as String: try container.encode(text, forKey: codingKey)
            case let flag as Bool: try container.encode(flag, forKey: codingKey)
            case let number as NSNumber: try container.encode(number.doubleValue, forKey: codingKey)
            case let nested as [String: Any]: try container.encode(JSONObject(nested), forKey: codingKey)
            case let list as [Any]: try container.encode(JSONArray(list), forKey: codingKey)
            default: break
            }
        }
    }
}

struct JSONArray: Encodable {
    var values: [Any]
    init(_ values: [Any]) { self.values = values }
    func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        for value in values {
            switch value {
            case let text as String: try container.encode(text)
            case let flag as Bool: try container.encode(flag)
            case let number as NSNumber: try container.encode(number.doubleValue)
            case let nested as [String: Any]: try container.encode(JSONObject(nested))
            case let list as [Any]: try container.encode(JSONArray(list))
            default: break
            }
        }
    }
}

struct JSONKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(_ value: String) { stringValue = value }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}
