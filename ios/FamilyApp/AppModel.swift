import Foundation

@MainActor
final class AppModel: ObservableObject {
    enum Phase {
        case loading
        case signedOut
        case ready
    }

    @Published var phase: Phase = .loading
    @Published var serverURL: String
    @Published var family: Family?
    @Published var member: Member?
    @Published var members: [Member] = []
    @Published var dashboard: Dashboard?
    @Published var budget: BudgetSnapshot?
    @Published var budgetMonth: String
    @Published var marriage: MarriageBundle?
    @Published var household: Household?
    @Published var events: [FamilyEvent] = []
    @Published var trips: [Trip] = []
    @Published var food: FoodBundle?
    @Published var mortgage: MortgageSnapshot?
    @Published var foodMemberId: String?
    @Published var lastSynced: Date?
    @Published var banner: String?
    @Published var celebration: Celebration?
    @Published var tab: AppTab = .home
    @Published var openLoveNote = false

    let api = APIClient()
    private let keychainService: String
    private let budgetOnly: Bool
    private var token: String?
    private var poll: Timer?
    private var refreshTask: Task<Void, Never>?

    init(keychainService: String = KeychainStore.familyService, budgetOnly: Bool = false) {
        self.keychainService = keychainService
        self.budgetOnly = budgetOnly
        let stored = UserDefaults.standard.string(forKey: "serverURL")
        let url = (stored?.isEmpty == false ? stored! : AppConfig.defaultServer)
        serverURL = url
        api.baseURL = url
        budgetMonth = Dates.monthKey()
    }

    func bootstrap() async {
        api.baseURL = serverURL
        if let saved = KeychainStore.read(service: keychainService), !saved.isEmpty {
            token = saved
            api.token = saved
            await refreshAll()
            if token != nil {
                phase = .ready
                startPolling()
            }
        } else {
            phase = .signedOut
        }
    }

    func createFamily(name: String, familyName: String) async throws -> String {
        api.baseURL = normalized(serverURL)
        let session: SessionResponse = try await api.post(
            "/v1/families",
            body: CreateFamilyBody(name: name, familyName: familyName)
        )
        store(session)
        return session.joinCode ?? ""
    }

    func join(name: String, code: String) async throws {
        api.baseURL = normalized(serverURL)
        let session: SessionResponse = try await api.post(
            "/v1/families/join",
            body: JoinBody(code: code, name: name)
        )
        store(session)
        phase = .ready
        startPolling()
        await refreshAll()
    }

    func finishOnboarding() async {
        phase = .ready
        startPolling()
        await refreshAll()
    }

    func signOut() {
        let oldToken = token
        let root = api.baseURL
        token = nil
        api.token = nil
        KeychainStore.clear(service: keychainService)
        stopPolling()
        clearData()
        phase = .signedOut
        if let oldToken {
            Task {
                let client = APIClient()
                client.baseURL = root
                client.token = oldToken
                let _: JSONAck? = try? await client.post("/v1/logout")
            }
        }
    }

    func updateServer(_ url: String) {
        let next = normalized(url)
        guard next != serverURL else { return }
        serverURL = next
        UserDefaults.standard.set(next, forKey: "serverURL")
        api.baseURL = next
        signOut()
        banner = "Server changed. Sign in on this server."
    }

    func saveProfile(name: String, familyName: String) async {
        do {
            let me: MeResponse = try await api.patch("/v1/me", body: NameBody(name: name))
            apply(me)
            let family: MeResponse = try await api.patch("/v1/family", body: NameBody(name: familyName))
            apply(family)
            banner = "Saved."
            await refreshAll(silent: true)
        } catch {
            handle(error)
        }
    }

    func newJoinCode() async -> String? {
        do {
            let result: JoinCodeResult = try await api.post("/v1/join-codes")
            return result.joinCode
        } catch {
            handle(error)
            return nil
        }
    }

    func newBudgetPairingCode() async -> String? {
        do {
            let result: BudgetPairingCode = try await api.post("/v1/budget-app/pairing-code")
            return result.pairingCode
        } catch {
            handle(error)
            return nil
        }
    }

    func pairBudgetApp(code: String) async throws {
        api.baseURL = normalized(serverURL)
        let session: SessionResponse = try await api.post(
            "/v1/budget-app/redeem",
            body: BudgetPairingRedeemBody(code: code)
        )
        store(session)
        phase = .ready
        startPolling()
        await refreshAll()
    }

    /// Pull-to-refresh entry point. SwiftUI cancels a `.refreshable` task as soon as the screen
    /// re-renders (which our own data updates cause), so the work runs in its own task that the
    /// gesture only waits on. A cancelled refresh is never reported as an error.
    func pullToRefresh() async {
        await Task { await self.refreshAll() }.value
    }

    func refreshAll(silent: Bool = false) async {
        // Let an in-flight refresh finish first so two refreshes never race each other,
        // then load fresh data (the earlier one may predate a change the user just made).
        while let running = refreshTask {
            await running.value
        }
        let task = Task { await self.performRefresh(silent: silent) }
        refreshTask = task
        await task.value
        if refreshTask == task { refreshTask = nil }
    }

    private func performRefresh(silent: Bool) async {
        do {
            let today = Dates.isoDay(Date())
            let month = budgetMonth
            let api = self.api
            if budgetOnly {
                async let budgetCall: BudgetSnapshot = api.get("/v1/budget?month=\(month)&today=\(today)")
                async let meCall: MeResponse = api.get("/v1/me")
                let (budgetData, meData) = try await (budgetCall, meCall)
                if month == budgetMonth { budget = budgetData }
                apply(meData)
                lastSynced = Date()
                banner = nil
                return
            }
            async let dashCall: Dashboard = api.get("/v1/dashboard?today=\(today)")
            async let budgetCall: BudgetSnapshot = api.get("/v1/budget?month=\(month)&today=\(today)")
            async let marriageCall: MarriageBundle = api.get("/v1/marriage")
            async let householdCall: Household = api.get("/v1/household")
            async let eventCall: EventList = api.get("/v1/events")
            async let tripCall: TripList = api.get("/v1/trips")
            async let foodCall: FoodBundle = api.get("/v1/food?day=\(today)")
            async let mortgageCall: MortgageSnapshot = api.get("/v1/mortgage?today=\(today)")
            let (dash, budgetData, marriageData, householdData, eventList, tripList, foodData, mortgageData) =
                try await (dashCall, budgetCall, marriageCall, householdCall, eventCall, tripCall, foodCall, mortgageCall)
            // Publish everything in one go so the screen redraws once, after all calls finish.
            dashboard = dash
            family = dash.family
            member = dash.member
            members = dash.members
            if month == budgetMonth { budget = budgetData }
            marriage = marriageData
            household = householdData
            events = eventList.events
            trips = tripList.trips
            food = foodData
            mortgage = mortgageData
            if foodMemberId == nil { foodMemberId = dash.member.id }
            lastSynced = Date()
            banner = nil
        } catch {
            if error.isCancellation { return }
            if silent {
                if let apiError = error as? APIError, apiError.unauthorized { handle(error) }
            } else {
                handle(error)
            }
        }
    }

    func loadBudget() async {
        do {
            let today = Dates.isoDay(Date())
            budget = try await api.get("/v1/budget?month=\(budgetMonth)&today=\(today)")
            lastSynced = Date()
        } catch {
            handle(error)
        }
    }

    func shiftMonth(_ delta: Int) async {
        budgetMonth = Dates.shiftMonth(budgetMonth, by: delta)
        await loadBudget()
    }

    func toggleChore(id: String, done: Bool) async {
        do {
            let _: JSONAck = try await api.patch("/v1/chores/\(id)", body: ChorePatchBody(done: done))
            Haptics.tap()
            await refreshAll(silent: true)
        } catch {
            handle(error)
        }
    }

    func toggleGrocery(id: String, done: Bool) async {
        do {
            let _: JSONAck = try await api.patch("/v1/notes/\(id)", body: NotePatchBody(done: done))
            await refreshAll(silent: true)
        } catch {
            handle(error)
        }
    }

    func togglePacking(id: String, done: Bool) async {
        do {
            let _: JSONAck = try await api.patch("/v1/packing/\(id)", body: DoneTitleBody(done: done))
            await refreshAll(silent: true)
        } catch {
            handle(error)
        }
    }

    func suggestBudgets() async {
        do {
            let result: SuggestResult = try await api.post(
                "/v1/budget/suggest",
                body: SuggestBody(month: budgetMonth, apply: true, today: Dates.isoDay(Date()))
            )
            banner = result.message
            await refreshAll(silent: true)
        } catch {
            handle(error)
        }
    }

    func importRows(_ rows: [ImportRowBody]) async -> ImportResult? {
        do {
            let result: ImportResult = try await api.post("/v1/transactions/import", body: ImportBody(rows: rows))
            banner = "Imported \(result.imported). Skipped \(result.skipped) duplicates."
            await refreshAll(silent: true)
            return result
        } catch {
            handle(error)
            return nil
        }
    }

    private func store(_ session: SessionResponse) {
        token = session.token
        api.token = session.token
        KeychainStore.save(session.token, service: keychainService)
        let url = normalized(serverURL)
        serverURL = url
        api.baseURL = url
        UserDefaults.standard.set(url, forKey: "serverURL")
        family = session.family
        member = session.member
        members = session.members
    }

    private func apply(_ me: MeResponse) {
        family = me.family
        member = me.member
        members = me.members
    }

    private func clearData() {
        family = nil
        member = nil
        members = []
        dashboard = nil
        budget = nil
        marriage = nil
        household = nil
        events = []
        trips = []
        food = nil
        mortgage = nil
        foodMemberId = nil
        lastSynced = nil
        celebration = nil
        tab = .home
    }

    /// Show an error from a screen action. Cancelled requests stay silent.
    func report(_ error: Error) {
        handle(error)
    }

    private func handle(_ error: Error) {
        if error.isCancellation { return }
        if let apiError = error as? APIError, apiError.unauthorized {
            signOut()
            banner = apiError.message
            return
        }
        banner = (error as? LocalizedError)?.errorDescription ?? "Something went wrong."
    }

    private func normalized(_ url: String) -> String {
        var value = url.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasSuffix("/") { value.removeLast() }
        if !value.contains("://") { value = "https://" + value }
        return value
    }

    private func startPolling() {
        stopPolling()
        poll = Timer.scheduledTimer(withTimeInterval: 45, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refreshAll(silent: true)
            }
        }
    }

    private func stopPolling() {
        poll?.invalidate()
        poll = nil
    }
}
