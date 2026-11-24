import Foundation
import Security
import UIKit

enum AppConfig {
    static let defaultServer = "https://132-145-159-218.sslip.io"
}

enum Money {
    static func format(_ cents: Int, showCents: Bool? = nil) -> String {
        let show = showCents ?? (cents % 100 != 0)
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = show ? 2 : 0
        formatter.minimumFractionDigits = show ? 2 : 0
        let value = Double(cents) / 100
        return formatter.string(from: NSNumber(value: value)) ?? "$0"
    }

    static func plain(_ cents: Int) -> String {
        String(format: "%.2f", Double(cents) / 100)
    }

    static func cents(from text: String) -> Int? {
        var cleaned = text.replacingOccurrences(of: "$", with: "")
        cleaned = cleaned.replacingOccurrences(of: ",", with: "")
        cleaned = cleaned.trimmingCharacters(in: .whitespaces)
        if cleaned.hasPrefix("(") && cleaned.hasSuffix(")") {
            cleaned = "-" + cleaned.dropFirst().dropLast()
        }
        guard let value = Double(cleaned) else { return nil }
        return Int((value * 100).rounded())
    }
}

enum Dates {
    static func isoDay(_ date: Date) -> String {
        formatter("yyyy-MM-dd").string(from: date)
    }

    static func monthKey(_ date: Date = Date()) -> String {
        formatter("yyyy-MM").string(from: date)
    }

    static func parseDay(_ value: String) -> Date? {
        formatter("yyyy-MM-dd").date(from: String(value.prefix(10)))
    }

    static func parseDateTime(_ value: String) -> Date? {
        if value.count <= 10 { return parseDay(value) }
        return formatter("yyyy-MM-dd'T'HH:mm:ss").date(from: String(value.prefix(19)))
    }

    static func prettyMonth(_ key: String) -> String {
        guard let date = formatter("yyyy-MM").date(from: key) else { return key }
        return display("MMMM yyyy").string(from: date)
    }

    static func shiftMonth(_ key: String, by delta: Int) -> String {
        guard let date = formatter("yyyy-MM").date(from: key),
              let shifted = Calendar.current.date(byAdding: .month, value: delta, to: date) else {
            return key
        }
        return monthKey(shifted)
    }

    static func greeting(name: String, now: Date = Date()) -> String {
        let hour = Calendar.current.component(.hour, from: now)
        let hello: String
        if hour < 12 { hello = "Good morning" }
        else if hour < 17 { hello = "Good afternoon" }
        else { hello = "Good evening" }
        let first = name.split(separator: " ").first.map(String.init) ?? name
        return "\(hello), \(first)"
    }

    static func synced(_ date: Date?) -> String {
        guard let date else { return "Not synced yet" }
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 45 { return "Synced just now" }
        if seconds < 3600 { return "Synced \(max(seconds / 60, 1))m ago" }
        if seconds < 86400 { return "Synced \(seconds / 3600)h ago" }
        return "Synced \(seconds / 86400)d ago"
    }

    static func prettyDateTime(_ value: String) -> String {
        guard let date = parseDateTime(value) else { return value }
        return display("EEEE · h:mm a").string(from: date)
    }

    static func shortDay(_ value: String) -> String {
        guard let date = parseDateTime(value) else { return value }
        return display("MMM d").string(from: date)
    }

    static func longDay(_ date: Date) -> String {
        display("EEEE, MMM d").string(from: date)
    }

    static func timeLabel(_ value: String) -> String {
        guard let date = parseDateTime(value) else { return "" }
        if value.count <= 10 { return "All day" }
        return display("h:mm a").string(from: date)
    }

    static func whenChip(_ value: String, today: Date = Date()) -> (label: String, isToday: Bool) {
        guard let date = parseDateTime(value) else { return (value, false) }
        let cal = Calendar.current
        if cal.isDate(date, inSameDayAs: today) { return ("Today", true) }
        return (display("EEE").string(from: date), false)
    }

    static func daysUntil(_ value: String, from today: Date = Date()) -> Int? {
        guard let date = parseDay(value) else { return nil }
        let cal = Calendar.current
        let start = cal.startOfDay(for: today)
        let target = cal.startOfDay(for: date)
        return cal.dateComponents([.day], from: start, to: target).day
    }

    static func daysSince(_ value: String, from today: Date = Date()) -> Int? {
        guard let days = daysUntil(value, from: today) else { return nil }
        return -days
    }

    static func nextAnnualDays(from fullDate: String, today: Date = Date()) -> Int? {
        guard let date = parseDay(fullDate) else { return nil }
        let cal = Calendar.current
        let month = cal.component(.month, from: date)
        let day = cal.component(.day, from: date)
        return daysUntilMonthDay(month: month, day: day, today: today)
    }

    static func daysUntilMonthDay(month: Int, day: Int, today: Date = Date()) -> Int? {
        let cal = Calendar.current
        let start = cal.startOfDay(for: today)
        let year = cal.component(.year, from: today)
        guard let next = nextDate(year: year, month: month, day: day, cal: cal) else { return nil }
        let target = next < start ? nextDate(year: year + 1, month: month, day: day, cal: cal) : next
        guard let target else { return nil }
        return cal.dateComponents([.day], from: start, to: cal.startOfDay(for: target)).day
    }

    static func yearsSince(_ value: String, today: Date = Date()) -> Int? {
        guard let date = parseDay(value) else { return nil }
        return Calendar.current.dateComponents([.year], from: date, to: today).year
    }

    static func monday(of date: Date = Date()) -> String {
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: date)
        let delta = (weekday + 5) % 7
        let start = cal.startOfDay(for: date)
        let monday = cal.date(byAdding: .day, value: -delta, to: start) ?? start
        return isoDay(monday)
    }

    static func combine(day: Date, time: Date) -> String {
        let cal = Calendar.current
        let dayParts = cal.dateComponents([.year, .month, .day], from: day)
        let timeParts = cal.dateComponents([.hour, .minute], from: time)
        var parts = DateComponents()
        parts.year = dayParts.year
        parts.month = dayParts.month
        parts.day = dayParts.day
        parts.hour = timeParts.hour
        parts.minute = timeParts.minute
        let date = cal.date(from: parts) ?? day
        return formatter("yyyy-MM-dd'T'HH:mm:ss").string(from: date)
    }

    static func flexibleDay(_ raw: String) -> String? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let formats = ["yyyy-MM-dd", "M/d/yyyy", "MM/dd/yyyy", "yyyy/MM/dd", "M/d/yy", "MMM d yyyy", "MMM d, yyyy"]
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone.current
        for format in formats {
            parser.dateFormat = format
            if let date = parser.date(from: text) {
                return isoDay(date)
            }
        }
        return nil
    }

    private static func nextDate(year: Int, month: Int, day: Int, cal: Calendar) -> Date? {
        var parts = DateComponents(year: year, month: month, day: day)
        if let date = cal.date(from: parts) { return date }
        parts.day = min(day, 28)
        return cal.date(from: parts)
    }

    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = format
        return formatter
    }

    private static func display(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = format
        return formatter
    }
}

enum KeychainStore {
    static let familyService = "com.colemcclintock.familyapp"
    private static let account = "session"

    static func save(_ token: String, service: String = familyService) {
        let query = base(service: service)
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = Data(token.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func read(service: String = familyService) -> String? {
        var query = base(service: service)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func clear(service: String = familyService) {
        SecItemDelete(base(service: service) as CFDictionary)
    }

    private static func base(service: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

enum CSVParser {
    static func rows(_ text: String) -> [[String]] {
        var result: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        let chars = Array(text)
        var index = 0
        while index < chars.count {
            let char = chars[index]
            if quoted {
                if char == "\"" {
                    if index + 1 < chars.count && chars[index + 1] == "\"" {
                        field.append("\"")
                        index += 1
                    } else {
                        quoted = false
                    }
                } else {
                    field.append(char)
                }
            } else if char == "\"" {
                quoted = true
            } else if char == "," {
                row.append(field)
                field = ""
            } else if char == "\n" || char == "\r" {
                if char == "\r", index + 1 < chars.count, chars[index + 1] == "\n" {
                    index += 1
                }
                row.append(field)
                field = ""
                if row.contains(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                    result.append(row)
                }
                row = []
            } else {
                field.append(char)
            }
            index += 1
        }
        row.append(field)
        if row.contains(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
            result.append(row)
        }
        return result
    }
}

enum Pasteboard {
    static func copy(_ text: String) {
        UIPasteboard.general.string = text
    }
}
