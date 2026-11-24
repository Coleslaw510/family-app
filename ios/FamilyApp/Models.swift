import Foundation

struct Family: Decodable, Equatable {
    var id: String
    var name: String
    var anniversaryDate: String?
    var firstDate: String?
    var flowerNudgeDays: Int
    var createdAt: String?
}

struct Member: Decodable, Identifiable, Equatable {
    var id: String
    var name: String
    var createdAt: String?
}

struct SessionResponse: Decodable {
    var token: String
    var tokenExpiresAt: String?
    var joinCode: String?
    var joinCodeExpiresAt: String?
    var family: Family
    var member: Member
    var members: [Member]
}

struct MeResponse: Decodable {
    var family: Family
    var member: Member
    var members: [Member]
}

struct Insight: Decodable, Equatable {
    var level: String
    var title: String
    var body: String
}

struct Txn: Decodable, Identifiable, Equatable {
    var id: String
    var categoryId: String?
    var categoryName: String?
    var categoryColor: String?
    var categoryIcon: String?
    var memberId: String?
    var memberName: String?
    var merchant: String
    var amountCents: Int
    var kind: String
    var direction: String?
    var occurredOn: String
    var note: String?
    var source: String
    var createdAt: String
}

struct Dashboard: Decodable {
    var family: Family
    var member: Member
    var members: [Member]
    var budget: DashBudget
    var chores: DashChores
    var events: [FamilyEvent]
    var nextDate: DateNight?
    var trip: Trip?
}

struct DashBudget: Decodable {
    var month: String
    var monthLabel: String
    var spentCents: Int
    var budgetCents: Int
    var remainingCents: Int
    var pace: String
    var insight: Insight?
    var recent: [Txn]
}

struct DashChores: Decodable {
    var done: Int
    var total: Int
    var items: [DashChore]
}

struct DashChore: Decodable, Identifiable {
    var id: String
    var title: String
    var done: Bool
    var assigneeId: String?
    var assigneeName: String?
}

struct CategorySpend: Decodable, Identifiable {
    var id: String
    var name: String
    var color: String
    var icon: String
    var spentCents: Int
    var budgetCents: Int
    var defaultBudgetCents: Int
}

struct IncomeEntry: Decodable, Identifiable {
    var id: String
    var memberId: String?
    var memberName: String?
    var label: String
    var month: String
    var expectedCents: Int
    var receivedCents: Int
    var expectedOn: String?
    var receivedOn: String?
}

struct Bill: Decodable, Identifiable {
    var id: String
    var name: String
    var amountCents: Int
    var dueOn: String
    var categoryId: String?
    var categoryName: String?
    var cadence: String
    var paid: Bool
    var notes: String?
}

struct Account: Decodable, Identifiable {
    var id: String
    var name: String
    var institution: String?
    var balanceCents: Int
    var kind: String
}

struct HistoryMonth: Decodable, Identifiable {
    var month: String
    var spentCents: Int
    var budgetCents: Int
    var isCurrent: Bool
    var id: String { month }

    var shortLabel: String {
        let monthNumber = Int(month.suffix(2)) ?? 1
        let letters = ["J", "F", "M", "A", "M", "J", "J", "A", "S", "O", "N", "D"]
        let index = min(max(monthNumber - 1, 0), 11)
        return letters[index]
    }
}

struct Trend: Decodable, Identifiable {
    var categoryId: String
    var name: String
    var color: String
    var points: [Int]
    var deltaLabel: String
    var direction: String
    var id: String { categoryId }
}

struct Placeholders: Decodable {
    var bankSync: String
    var ai: String
}

struct BudgetSnapshot: Decodable {
    var month: String
    var monthLabel: String
    var spentCents: Int
    var budgetCents: Int
    var remainingCents: Int
    var uncategorizedCents: Int
    var incomeReceivedCents: Int
    var incomeExpectedCents: Int
    var incomeFromTransactionsCents: Int
    var projectedLeftoverCents: Int?
    var daysInMonth: Int
    var daysElapsed: Int
    var daysLeft: Int
    var pace: String
    var safeToSpendCents: Int
    var safePerDayCents: Int
    var upcomingBillsCents: Int
    var categories: [CategorySpend]
    var incomeEntries: [IncomeEntry]
    var bills: [Bill]
    var transactions: [Txn]
    var accounts: [Account]
    var history: [HistoryMonth]
    var historyBudgetCents: Int
    var trends: [Trend]
    var insights: [Insight]
    var importCount: Int
    var placeholders: Placeholders
}

struct CategoryRecord: Decodable, Identifiable {
    var id: String
    var name: String
    var color: String
    var icon: String
    var defaultBudgetCents: Int
    var sortOrder: Int
}

struct CategoryList: Decodable {
    var categories: [CategoryRecord]
}

struct Birthday: Decodable, Identifiable {
    var id: String
    var name: String
    var month: Int
    var day: Int
    var year: Int?
    var memberId: String?
}

struct FlowerLog: Decodable, Identifiable {
    var id: String
    var boughtOn: String
    var note: String?
    var createdAt: String
}

struct FlowerState: Decodable {
    var nudgeAfterDays: Int
    var logs: [FlowerLog]
}

struct DateNight: Decodable, Identifiable {
    var id: String
    var title: String
    var startsAt: String
    var location: String?
    var notes: String?
    var createdBy: String?
}

struct Checkin: Decodable, Identifiable {
    var id: String
    var memberId: String
    var memberName: String
    var weekStart: String
    var connection: Int
    var appreciation: Int
    var fun: Int
    var note: String?
    var createdAt: String
}

struct LoveNote: Decodable, Identifiable {
    var id: String
    var authorId: String
    var authorName: String
    var body: String
    var createdAt: String
}

struct MarriageBundle: Decodable {
    var anniversaryDate: String?
    var firstDate: String?
    var flowerNudgeDays: Int
    var birthdays: [Birthday]
    var flowers: FlowerState
    var dates: [DateNight]
    var checkins: [Checkin]
    var loveNotes: [LoveNote]
}

struct Chore: Decodable, Identifiable {
    var id: String
    var title: String
    var assigneeId: String?
    var assigneeName: String?
    var done: Bool
    var dueOn: String?
    var createdBy: String?
    var completedAt: String?
}

struct ImportantDate: Decodable, Identifiable {
    var id: String
    var title: String
    var dateOn: String
    var repeatsYearly: Bool
    var notes: String?
}

struct SharedNote: Decodable, Identifiable {
    var id: String
    var kind: String
    var body: String
    var done: Bool
    var createdBy: String?
    var authorName: String?
    var createdAt: String
}

struct Household: Decodable {
    var chores: [Chore]
    var importantDates: [ImportantDate]
    var notes: [SharedNote]
}

struct FamilyEvent: Decodable, Identifiable {
    var id: String
    var title: String
    var startsAt: String
    var endsAt: String?
    var allDay: Bool
    var location: String?
    var notes: String?
    var color: String
    var createdBy: String?
    var source: String?
    var readOnly: Bool?
}

struct EventList: Decodable {
    var events: [FamilyEvent]
}

struct PackingItem: Decodable, Identifiable {
    var id: String
    var title: String
    var done: Bool
    var sortOrder: Int
}

struct ItineraryItem: Decodable, Identifiable {
    var id: String
    var dayOn: String?
    var title: String
    var body: String?
    var sortOrder: Int
}

struct Trip: Decodable, Identifiable {
    var id: String
    var name: String
    var destination: String?
    var startDate: String
    var endDate: String
    var savingsCents: Int
    var goalCents: Int
    var notes: String?
    var packing: [PackingItem]
    var itinerary: [ItineraryItem]
    var daysUntil: Int?
    var goalJustReached: Bool?
}

struct TripList: Decodable {
    var trips: [Trip]
}

struct ImportResult: Decodable {
    var imported: Int
    var skipped: Int
    var createdCategories: Int
}

struct SuggestResult: Decodable {
    var message: String
}

struct JoinCodeResult: Decodable {
    var joinCode: String
    var joinCodeExpiresAt: String
}

struct JSONAck: Decodable {}

struct Celebration: Identifiable, Equatable {
    let id = UUID()
    var title: String
}
