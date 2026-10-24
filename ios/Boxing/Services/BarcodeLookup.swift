import Foundation

enum FoodCatalogConfiguration { static let contactEmail = "" } // User chose to leave unset for now.

enum BarcodeLookupError: LocalizedError {
    case notConfigured, invalidCode, unavailable, notFound, rateLimited
    var errorDescription: String? {
        switch self {
        case .notConfigured: "Barcode lookup needs the developer's Open Food Facts contact setup. Manual meal logging remains available."
        case .invalidCode: "Enter an 8, 12, 13 or 14 digit product barcode."
        case .unavailable: "The food catalog is unavailable. Please try again later or use manual entry."
        case .rateLimited: "Please wait a few seconds before another barcode lookup."
        case .notFound: "This product was not found. You can enter the package values manually."
        }
    }
}

struct BarcodeLookup: Sendable {
    private struct Response: Decodable { let product: BarcodeProduct? }
    func product(code: String) async throws -> BarcodeProduct {
        guard !FoodCatalogConfiguration.contactEmail.isEmpty else { throw BarcodeLookupError.notConfigured }
        guard [8, 12, 13, 14].contains(code.count), code.allSatisfy({ $0.isASCII && $0.isNumber }) else { throw BarcodeLookupError.invalidCode }
        // Pin v3.4 for its documented legacy nutrition representation; v3.5+ changes that schema.
        // Development requests use OFF's documented staging host, with its public staging credentials.
        #if DEBUG
        let host = "world.openfoodfacts.net"
        #else
        let host = "world.openfoodfacts.org"
        #endif
        guard var components = URLComponents(string: "https://\(host)/api/v3.4/product/\(code).json") else { throw BarcodeLookupError.unavailable }
        components.queryItems = [.init(name: "fields", value: "product_name,nutriments")]
        guard let url = components.url else { throw BarcodeLookupError.unavailable }
        var request = URLRequest(url: url); request.timeoutInterval = 20
        request.setValue("BOX/0.1 (\(FoodCatalogConfiguration.contactEmail))", forHTTPHeaderField: "User-Agent")
        #if DEBUG
        request.setValue("Basic " + Data("off:off".utf8).base64EncodedString(), forHTTPHeaderField: "Authorization")
        #endif
        guard await FoodCatalogThrottle.shared.allow() else { throw BarcodeLookupError.rateLimited }
        let (data, response) = try await URLSession.shared.data(for: request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else { throw BarcodeLookupError.unavailable }
        if response.statusCode == 404 { throw BarcodeLookupError.notFound }
        guard (200...299).contains(response.statusCode), data.count < 1_000_000 else { throw BarcodeLookupError.unavailable }
        guard let product = try JSONDecoder().decode(Response.self, from: data).product else { throw BarcodeLookupError.notFound }
        return product
    }
}

private actor FoodCatalogThrottle {
    static let shared = FoodCatalogThrottle()
    private var last: ContinuousClock.Instant?
    func allow() -> Bool {
        let now = ContinuousClock.now
        if let last, last.duration(to: now) < .seconds(4.1) { return false }
        last = now; return true
    }
}
