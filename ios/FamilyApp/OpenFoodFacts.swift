import Foundation

enum BarcodeError: LocalizedError {
    case invalid, notFound, incomplete, unavailable
    var errorDescription: String? {
        switch self {
        case .invalid: return "That doesn't look like a product barcode."
        case .notFound: return "Open Food Facts doesn't have this barcode yet."
        case .incomplete: return "This product is missing nutrition. Check the package."
        case .unavailable: return "Open Food Facts is unavailable right now."
        }
    }
}

struct NutrientAmounts {
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    func scaled(_ factor: Double) -> NutrientAmounts {
        NutrientAmounts(calories: calories * factor, protein: protein * factor, carbs: carbs * factor, fat: fat * factor)
    }
}

struct ProductFacts {
    var code: String
    var name: String
    var servingLabel: String
    var perServing: NutrientAmounts?
    var per100: NutrientAmounts?
    var unit: String
}

enum OpenFoodFacts {
    static let userAgent = "FamilyApp/1.1"

    static func lookup(code: String) async throws -> ProductFacts {
        let cleaned = code.filter(\.isNumber)
        guard cleaned.count >= 8, let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(cleaned).json") else {
            throw BarcodeError.invalid
        }
        var request = URLRequest(url: url, timeoutInterval: 25)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw BarcodeError.unavailable }
        if http.statusCode == 404 { throw BarcodeError.notFound }
        guard (200..<300).contains(http.statusCode) else { throw BarcodeError.unavailable }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              (root["status"] as? Int) == 1 || (root["status"] as? NSNumber)?.intValue == 1,
              let product = root["product"] as? [String: Any],
              let nutriments = product["nutriments"] as? [String: Any] else {
            throw BarcodeError.notFound
        }
        func amount(_ suffix: String) -> NutrientAmounts? {
            let kcal = number(nutriments["energy-kcal_\(suffix)"])
                ?? number(nutriments["energy-kj_\(suffix)"]).map { $0 / 4.184 }
            guard let kcal, let protein = number(nutriments["proteins_\(suffix)"]),
                  let carbs = number(nutriments["carbohydrates_\(suffix)"]),
                  let fat = number(nutriments["fat_\(suffix)"]) else { return nil }
            return NutrientAmounts(calories: kcal, protein: protein, carbs: carbs, fat: fat)
        }
        let perServing = amount("serving")
        let per100 = amount("100g")
        guard perServing != nil || per100 != nil else { throw BarcodeError.incomplete }
        let name = (product["product_name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = (product["serving_size"] as? String) ?? ""
        let unit = ((product["nutrition_data_per"] as? String) ?? "").lowercased().contains("100ml") ? "mL" : "g"
        return ProductFacts(
            code: cleaned,
            name: (name?.isEmpty == false ? name! : "Product \(cleaned)"),
            servingLabel: label.isEmpty ? "100 \(unit)" : label,
            perServing: perServing,
            per100: per100,
            unit: unit
        )
    }

    private static func number(_ raw: Any?) -> Double? {
        if let number = raw as? NSNumber { return number.doubleValue }
        if let text = raw as? String { return Double(text) }
        return nil
    }
}
