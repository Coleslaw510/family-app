import Foundation

struct CategoryRule: Decodable, Identifiable {
    var id: String
    var pattern: String
    var categoryId: String
    var categoryName: String
}

struct RuleList: Decodable {
    var rules: [CategoryRule]
}

struct ImportPreview: Decodable {
    var importId: String
    var filename: String
    var columns: [String]
    var sample: [[String]]
    var rowCount: Int
    var suggested: ImportSuggestion
}

struct ImportSuggestion: Decodable {
    var dateColumn: Int
    var descriptionColumn: Int
    var amountColumn: Int?
    var debitColumn: Int?
    var creditColumn: Int?
}

struct ImportCommitResult: Decodable {
    var imported: Int
    var skipped: Int
    var categorized: Int
}

struct OrderBody: Encodable {
    var ids: [String]
}

struct RuleBody: Encodable {
    var pattern: String
    var categoryId: String
}

struct TransactionRule: Decodable, Identifiable {
    var id: String
    var pattern: String
    var kind: String
    var flowDirection: String
    var categoryId: String?
    var categoryName: String?
}

struct TransactionRuleList: Decodable {
    var rules: [TransactionRule]
}

struct BudgetPairingCode: Decodable {
    var pairingCode: String
    var expiresAt: String
}

struct BudgetPairingRedeemBody: Encodable {
    var code: String
}

struct TransactionRuleBody: Encodable {
    var pattern: String
    var kind: String
    var flowDirection: String
    var categoryId: String?
    var applyToExisting: Bool
}

struct TransactionRulePatchBody: Encodable {
    var pattern: String
    var kind: String
    var flowDirection: String
    var categoryId: String?
    var applyToExisting: Bool
}

struct ImportCommitBody: Encodable {
    var dateColumn: Int
    var descriptionColumn: Int
    var amountColumn: Int?
    var debitColumn: Int?
    var creditColumn: Int?
    var flipSigns: Bool
    var hasHeader: Bool
}

struct CalendarFeed: Decodable, Identifiable {
    var id: String
    var name: String
    var color: String
    var urlMasked: String
    var lastFetchedAt: String?
    var lastError: String?
    var eventCount: Int
}

struct FeedList: Decodable {
    var feeds: [CalendarFeed]
}

struct FeedBody: Encodable {
    var name: String
    var color: String
    var url: String
}

struct IntegrationsStatus: Decodable {
    var geminiConfigured: Bool
    var rentcastActive: Bool
    var feeds: [CalendarFeed]
}

struct SimpleFINStatus: Decodable {
    var connected: Bool
    var encryptionConfigured: Bool
    var lastSyncedAt: String?
    var lastError: String?
}

struct SimpleFINConnectBody: Encodable {
    var setupToken: String
}

struct SimpleFINConnectResult: Decodable {
    var connected: Bool
    var message: String
}

struct SimpleFINSyncResult: Decodable {
    var ok: Bool
    var imported: Int
    var skipped: Int
    var lastSyncedAt: String?
}

struct HomeValuePoint: Decodable, Identifiable {
    var id: String
    var valuedOn: String
    var valueCents: Int
    var source: String
}

struct MortgageSummary: Decodable {
    var balanceCents: Int?
    var interestPaidCents: Int?
    var principalPaidCents: Int?
    var payoffDate: String?
    var interestSavedCents: Int?
    var progress: Double?
    var equityCents: Int?
    var homeValueCents: Int?
    var error: String?
}

struct MortgageSnapshot: Decodable {
    var address: String?
    var values: [HomeValuePoint]
    var rentcastActive: Bool
    var summary: MortgageSummary?
    var loanCents: Int?
    var annualRatePercent: Double?
    var termMonths: Int?
    var startDate: String?
    var paymentCents: Int?
    var extraCents: Int
}

struct MortgageBody: Encodable {
    var loanCents: Int
    var annualRatePercent: Double
    var termMonths: Int
    var startDate: String
    var paymentCents: Int
    var extraCents: Int
    var address: String?
}

struct HomeValueBody: Encodable {
    var valuedOn: String
    var valueCents: Int
}

struct AskBody: Encodable {
    var month: String
    var question: String
    var today: String
}

struct AskResult: Decodable {
    var answer: String
}

struct FoodGoals: Decodable {
    var calories: Int
    var protein: Int
    var carbs: Int
    var fat: Int
    var water: Int
}

struct FoodTotals: Decodable {
    var calories: Int
    var protein: Int
    var carbs: Int
    var fat: Int
}

struct FoodItem: Decodable, Identifiable {
    var id: String
    var dayOn: String?
    var name: String
    var meal: String
    var calories: Int
    var protein: Int
    var carbs: Int
    var fat: Int
    var serving: String?
}

struct FoodHistoryDay: Decodable, Identifiable {
    var day: String
    var calories: Int
    var protein: Int
    var carbs: Int
    var fat: Int
    var id: String { day }
}

struct DinnerPlan: Decodable, Identifiable {
    var id: String
    var dayOn: String
    var title: String
    var notes: String?
    var createdBy: String?
}

struct FoodBundle: Decodable {
    var memberId: String
    var day: String
    var goals: FoodGoals
    var entries: [FoodItem]
    var favorites: [FoodItem]
    var waterCups: Int
    var totals: FoodTotals
    var history: [FoodHistoryDay]
    var dinners: [DinnerPlan]
}

struct GoalsBody: Encodable {
    var calories: Int
    var protein: Int
    var carbs: Int
    var fat: Int
    var water: Int
}

struct FoodBody: Encodable {
    var dayOn: String
    var name: String
    var meal: String
    var calories: Int
    var protein: Int
    var carbs: Int
    var fat: Int
    var serving: String?
}

struct WaterBody: Encodable {
    var dayOn: String
    var cups: Int
}

struct DinnerBody: Encodable {
    var dayOn: String
    var title: String
    var notes: String?
}

struct DinnerLogBody: Encodable {
    var memberIds: [String]
    var calories: Int
    var protein: Int
    var carbs: Int
    var fat: Int
}

struct GroceryItemsBody: Encodable {
    var items: [String]
}

struct MealEstimate: Decodable {
    var mealName: String
    var items: [MealEstimateItem]
    var calories: Double
    var proteinG: Double
    var carbsG: Double
    var fatG: Double
    var confidence: Double
}

struct MealEstimateItem: Decodable {
    var name: String
    var estimatedPortion: String
}

struct CreatedId: Decodable {
    var id: String?
    var ok: Bool?
}
