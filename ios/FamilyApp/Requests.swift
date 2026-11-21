import Foundation

struct CreateFamilyBody: Encodable {
    var name: String
    var familyName: String
}

struct JoinBody: Encodable {
    var code: String
    var name: String
}

struct NameBody: Encodable {
    var name: String
}

struct TxnBody: Encodable {
    var merchant: String
    var amountCents: Int
    var kind: String
    var occurredOn: String
    var categoryId: String?
    var note: String?
}

struct BudgetSetBody: Encodable {
    var month: String
    var amountCents: Int
    var setDefault: Bool
}

struct CategoryBody: Encodable {
    var name: String
    var color: String?
    var icon: String?
    var defaultBudgetCents: Int
}

struct ImportBody: Encodable {
    var rows: [ImportRowBody]
}

struct ImportRowBody: Encodable {
    var date: String
    var merchant: String
    var amountCents: Int
    var category: String?
    var kind: String
}

struct SuggestBody: Encodable {
    var month: String
    var apply: Bool
    var today: String
}

struct IncomeBody: Encodable {
    var label: String
    var month: String
    var expectedCents: Int
    var receivedCents: Int
    var expectedOn: String?
    var receivedOn: String?
    var memberId: String?
}

struct BillBody: Encodable {
    var name: String
    var amountCents: Int
    var dueOn: String
    var categoryId: String?
    var cadence: String
    var notes: String?
}

struct BillPatchBody: Encodable {
    var name: String?
    var amountCents: Int?
    var dueOn: String?
    var categoryId: String?
    var cadence: String?
    var paid: Bool?
    var notes: String?
}

struct AccountBody: Encodable {
    var name: String
    var institution: String?
    var balanceCents: Int
    var kind: String
}

struct MarriageBody: Encodable {
    var anniversaryDate: String?
    var firstDate: String?
    var flowerNudgeDays: Int
}

struct BirthdayBody: Encodable {
    var name: String
    var month: Int
    var day: Int
    var year: Int?
}

struct FlowerBody: Encodable {
    var boughtOn: String
    var note: String?
}

struct DateBody: Encodable {
    var title: String
    var startsAt: String
    var location: String?
    var notes: String?
}

struct CheckinBody: Encodable {
    var weekStart: String
    var connection: Int
    var appreciation: Int
    var fun: Int
    var note: String?
}

struct LoveBody: Encodable {
    var body: String
}

struct ChoreBody: Encodable {
    var title: String
    var assigneeId: String?
    var dueOn: String?
}

struct ChorePatchBody: Encodable {
    var done: Bool
}

struct ImportantBody: Encodable {
    var title: String
    var dateOn: String
    var repeatsYearly: Bool
    var notes: String?
}

struct NoteBody: Encodable {
    var body: String
    var kind: String
}

struct NotePatchBody: Encodable {
    var done: Bool? = nil
    var body: String? = nil
}

struct EventBody: Encodable {
    var title: String
    var startsAt: String
    var endsAt: String?
    var allDay: Bool
    var location: String?
    var notes: String?
    var color: String
}

struct TripBody: Encodable {
    var name: String
    var destination: String?
    var startDate: String
    var endDate: String
    var savingsCents: Int
    var goalCents: Int
    var notes: String?
}

struct TripPatchBody: Encodable {
    var name: String? = nil
    var destination: String? = nil
    var startDate: String? = nil
    var endDate: String? = nil
    var savingsCents: Int? = nil
    var goalCents: Int? = nil
    var notes: String? = nil
}

struct TitleBody: Encodable {
    var title: String
}

struct DoneTitleBody: Encodable {
    var title: String? = nil
    var done: Bool? = nil
}

struct ItineraryBody: Encodable {
    var title: String
    var dayOn: String?
    var body: String?
}
