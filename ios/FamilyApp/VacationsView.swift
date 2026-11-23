import SwiftUI

private enum VacationSheet: Identifiable {
    case settings
    case create
    var id: String { self == .settings ? "settings" : "create" }
}

struct VacationsView: View {
    @EnvironmentObject private var app: AppModel
    @State private var sheet: VacationSheet?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Vacations")
                            .font(.system(size: 28, weight: .heavy))
                            .tracking(-0.6)
                        Spacer()
                        GearButton { sheet = .settings }
                    }
                    if app.trips.isEmpty {
                        Card {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("No trips yet")
                                    .font(.system(size: 16, weight: .bold))
                                Text("Add dates, a savings goal, a packing list, and the plan.")
                                    .foregroundStyle(Theme.muted)
                                PrimaryButton(title: "Plan a trip", system: "paperplane") { sheet = .create }
                            }
                        }
                    }
                    ForEach(Array(sorted.enumerated()), id: \.element.id) { index, trip in
                        NavigationLink {
                            TripDetailView(tripId: trip.id)
                        } label: {
                            tripCard(trip, featured: index == 0)
                        }
                        .buttonStyle(.plain)
                    }
                    if !app.trips.isEmpty {
                        OutlineButton(title: "Add another trip", system: "plus") { sheet = .create }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(Theme.bg)
            .refreshable { await app.pullToRefresh() }
            .toolbar(.hidden, for: .navigationBar)
        }
        .sheet(item: $sheet) { item in
            Group {
                switch item {
                case .settings: SettingsView()
                case .create: TripEditor(existing: nil)
                }
            }
        }
    }

    private var sorted: [Trip] {
        app.trips.sorted { $0.startDate < $1.startDate }
    }

    private func tripCard(_ trip: Trip, featured: Bool) -> some View {
        let days = Dates.daysUntil(trip.startDate) ?? 0
        let shown = max(days, 0)
        let fraction = trip.goalCents > 0 ? min(Double(trip.savingsCents) / Double(trip.goalCents), 1) : 0
        return Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    IconTile(system: "paperplane", colors: Theme.vacationGradient)
                    VStack(alignment: .leading, spacing: 1) {
                        Kicker(text: featured ? "Next trip" : "Trip")
                        Text(trip.name).font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.text)
                    }
                    Spacer()
                    if featured {
                        SparkleCountdown(days: shown)
                    } else {
                        VStack(alignment: .trailing) {
                            Text("\(shown)")
                                .font(.system(size: 20, weight: .heavy))
                                .foregroundStyle(Theme.vacation)
                            Text("DAYS")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Theme.muted)
                        }
                    }
                }
                Text("\(Dates.shortDay(trip.startDate)) – \(Dates.shortDay(trip.endDate))")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.muted)
                CapsuleBar(fraction: fraction, colors: [Color(hex: 0xFB923C), Theme.vacation])
                HStack {
                    Text("Trip savings")
                    Spacer()
                    Text(Money.format(trip.savingsCents))
                        .foregroundStyle(Theme.text)
                        .fontWeight(.heavy)
                    Text("of \(Money.format(trip.goalCents))")
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.muted)
            }
        }
    }
}

struct TripDetailView: View {
    @EnvironmentObject private var app: AppModel
    var tripId: String
    @State private var editing = false
    @State private var packingTitle = ""
    @State private var stopTitle = ""
    @State private var stopBody = ""
    @State private var addingPack = false
    @State private var addingStop = false
    @Environment(\.dismiss) private var dismiss

    private var trip: Trip? { app.trips.first { $0.id == tripId } }

    var body: some View {
        ScrollView {
            if let trip {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(trip.name).font(.system(size: 26, weight: .heavy))
                            Text(trip.destination ?? "No destination yet")
                                .foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        SparkleCountdown(days: max(Dates.daysUntil(trip.startDate) ?? 0, 0))
                    }
                    Text("\(Dates.shortDay(trip.startDate)) – \(Dates.shortDay(trip.endDate))")
                        .font(.system(size: 14, weight: .semibold))
                    CapsuleBar(
                        fraction: trip.goalCents > 0 ? min(Double(trip.savingsCents) / Double(trip.goalCents), 1) : 0,
                        colors: [Color(hex: 0xFB923C), Theme.vacation]
                    )
                    Text("\(Money.format(trip.savingsCents)) saved of \(Money.format(trip.goalCents))")
                        .foregroundStyle(Theme.muted)
                    if let notes = trip.notes, !notes.isEmpty {
                        Text(notes).font(.system(size: 15, weight: .medium))
                    }
                    OutlineButton(title: "Edit trip", system: "square.and.pencil") { editing = true }
                    packing(trip)
                    itinerary(trip)
                    Button("Delete trip", role: .destructive) { Task { await deleteTrip() } }
                        .foregroundStyle(Theme.bad)
                }
                .padding(16)
            } else {
                Text("This trip is gone.")
                    .padding()
            }
        }
        .background(Theme.bg)
        .navigationTitle("Trip")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .sheet(isPresented: $editing) {
            if let trip { TripEditor(existing: trip) }
        }
        .alert("Packing item", isPresented: $addingPack) {
            TextField("Sweaters", text: $packingTitle)
            Button("Add") { Task { await addPacking() } }
            Button("Cancel", role: .cancel) { packingTitle = "" }
        }
        .alert("Itinerary", isPresented: $addingStop) {
            TextField("Title", text: $stopTitle)
            TextField("Notes", text: $stopBody)
            Button("Add") { Task { await addStop() } }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func packing(_ trip: Trip) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Packing").font(.system(size: 15, weight: .bold))
                    Spacer()
                    TintedIconButton(system: "plus", title: "Add packing item") { addingPack = true }
                }
                if trip.packing.isEmpty { Text("Nothing to pack yet.").foregroundStyle(Theme.muted) }
                ForEach(trip.packing) { item in
                    HStack {
                        Button { Task { await app.togglePacking(id: item.id, done: !item.done) } } label: {
                            CheckBox(done: item.done, color: Theme.vacation)
                        }
                        .buttonStyle(.plain)
                        Text(item.title).strikethrough(item.done)
                        Spacer()
                        Button { Task { await delete("/v1/packing/\(item.id)") } } label: {
                            Image(systemName: "trash").foregroundStyle(Theme.soft)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func itinerary(_ trip: Trip) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Itinerary").font(.system(size: 15, weight: .bold))
                    Spacer()
                    TintedIconButton(system: "plus", title: "Add itinerary item") { addingStop = true }
                }
                if trip.itinerary.isEmpty { Text("Add the shape of the days.").foregroundStyle(Theme.muted) }
                ForEach(trip.itinerary) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(item.title).font(.system(size: 14, weight: .bold))
                            Spacer()
                            Button { Task { await delete("/v1/itinerary/\(item.id)") } } label: {
                                Image(systemName: "trash").foregroundStyle(Theme.soft)
                            }
                            .buttonStyle(.plain)
                        }
                        if let day = item.dayOn { Text(Dates.shortDay(day)).font(.system(size: 12)).foregroundStyle(Theme.muted) }
                        if let body = item.body { Text(body).font(.system(size: 13)).foregroundStyle(Theme.muted) }
                    }
                }
            }
        }
    }

    private func addPacking() async {
        let title = packingTitle.trimmingCharacters(in: .whitespaces)
        packingTitle = ""
        guard !title.isEmpty else { return }
        do {
            let _: JSONAck = try await app.api.post("/v1/trips/\(tripId)/packing", body: TitleBody(title: title))
            await app.refreshAll(silent: true)
        } catch {
            app.report(error)
        }
    }

    private func addStop() async {
        let title = stopTitle.trimmingCharacters(in: .whitespaces)
        let body = stopBody.trimmingCharacters(in: .whitespaces)
        stopTitle = ""
        stopBody = ""
        guard !title.isEmpty else { return }
        do {
            let _: JSONAck = try await app.api.post(
                "/v1/trips/\(tripId)/itinerary",
                body: ItineraryBody(title: title, dayOn: nil, body: body.isEmpty ? nil : body)
            )
            await app.refreshAll(silent: true)
        } catch {
            app.report(error)
        }
    }

    private func delete(_ path: String) async {
        do {
            let _: JSONAck = try await app.api.delete(path)
            await app.refreshAll(silent: true)
        } catch {
            app.report(error)
        }
    }

    private func deleteTrip() async {
        do {
            let _: JSONAck = try await app.api.delete("/v1/trips/\(tripId)")
            await app.refreshAll(silent: true)
            dismiss()
        } catch {
            app.report(error)
        }
    }
}

struct TripEditor: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    var existing: Trip?
    @State private var name = ""
    @State private var destination = ""
    @State private var start = Date()
    @State private var end = Date().addingTimeInterval(172800)
    @State private var savings = ""
    @State private var goal = ""
    @State private var notes = ""
    @State private var error: String?

    var body: some View {
        EditorChrome(title: existing == nil ? "New trip" : "Edit trip", working: false, error: error, onSave: { Task { await save() } }) {
            LabeledInput(title: "Name", text: $name, autocap: .words)
            LabeledInput(title: "Destination", text: $destination, autocap: .words)
            DatePicker("Starts", selection: $start, displayedComponents: .date)
            DatePicker("Ends", selection: $end, displayedComponents: .date)
            LabeledInput(title: "Saved so far", text: $savings, keyboard: .decimalPad, autocap: .never)
            LabeledInput(title: "Savings goal", text: $goal, keyboard: .decimalPad, autocap: .never)
            LabeledInput(title: "Notes", text: $notes)
        }
        .onAppear {
            if let existing {
                name = existing.name
                destination = existing.destination ?? ""
                start = Dates.parseDay(existing.startDate) ?? Date()
                end = Dates.parseDay(existing.endDate) ?? Date()
                savings = Money.plain(existing.savingsCents)
                goal = Money.plain(existing.goalCents)
                notes = existing.notes ?? ""
            }
        }
    }

    private func save() async {
        guard let saved = Money.cents(from: savings.isEmpty ? "0" : savings),
              let target = Money.cents(from: goal.isEmpty ? "0" : goal),
              saved >= 0, target >= 0 else {
            error = "Check the savings amounts."
            return
        }
        guard end >= start else { error = "The trip ends before it starts."; return }
        let previous = existing?.savingsCents ?? 0
        let previousGoal = existing?.goalCents ?? target
        do {
            if let existing {
                let updated: Trip = try await app.api.patch(
                    "/v1/trips/\(existing.id)",
                    body: TripPatchBody(
                        name: name,
                        destination: destination,
                        startDate: Dates.isoDay(start),
                        endDate: Dates.isoDay(end),
                        savingsCents: saved,
                        goalCents: target,
                        notes: notes
                    )
                )
                if updated.goalJustReached == true || (previous < previousGoal && saved >= target && target > 0) {
                    app.celebration = Celebration(title: "Trip fund complete")
                }
            } else {
                let _: Trip = try await app.api.post(
                    "/v1/trips",
                    body: TripBody(
                        name: name,
                        destination: destination,
                        startDate: Dates.isoDay(start),
                        endDate: Dates.isoDay(end),
                        savingsCents: saved,
                        goalCents: target,
                        notes: notes
                    )
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
