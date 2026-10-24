import Foundation

struct BarcodeProduct: Decodable, Sendable {
    struct NutrientNumber: Decodable, Sendable {
        let value: Double?
        let rawText: String?
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let number = try? container.decode(Double.self) { value = number; rawText = nil }
            else if let text = try? container.decode(String.self) { value = Double(text); rawText = text }
            else { value = nil; rawText = nil }
        }
    }
    let product_name: String?
    let nutriments: [String: NutrientNumber]?
    func draft(amount: Double, barcode: String) -> MealDraft? {
        guard amount.isFinite, amount > 0, amount <= 10_000,
              let name = product_name, !name.isEmpty, let nutrients = nutriments else { return nil }
        func number(_ name: String) -> Double? {
            guard let value = nutrients[name]?.value, value.isFinite, value >= 0 else { return nil }; return value
        }
        func grams(_ name: String) -> Double? {
            guard let value = number(name + "_100g"), let unit = nutrients[name + "_unit"]?.rawText else { return nil }
            switch unit.lowercased() {
            case "g": return value
            case "mg": return value / 1000
            default: return nil
            }
        }
        guard let protein = grams("proteins"), let carbs = grams("carbohydrates"), let fat = grams("fat"),
              protein + carbs + fat <= 105,
              let calories = number("energy-kcal_100g") ?? number("energy-kj_100g").map({ $0 / 4.184 }) else { return nil }
        let factor = amount / 100
        let draft = MealDraft(name: name, serving: "\(amount.formatted()) g / ml — verify package units", calories: calories * factor,
                              protein: protein * factor, carbs: carbs * factor, fat: fat * factor,
                              source: "Open Food Facts · \(barcode)", assumptions: "Community-supplied package data, scaled from per-100 g/ml values. Verify product, serving, preparation and package label before logging. Data: Open Food Facts (ODbL), https://world.openfoodfacts.org/")
        return draft.isValid ? draft : nil
    }
}
