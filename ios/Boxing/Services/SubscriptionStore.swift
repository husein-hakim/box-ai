import Foundation
import StoreKit
import Observation

// Developer setup after App Store Connect products exist. No sample prices or fake purchases.
enum CommerceConfiguration {
    static let productIDs: [String] = []
    static let purchasesEnabled = false // User decision: all features free during development.
}

@MainActor @Observable final class SubscriptionStore {
    private(set) var products: [Product] = []
    private(set) var activeProductIDs: Set<String> = []
    private(set) var loading = false
    private(set) var purchasing = false
    var notice: String?
    var configured: Bool { !CommerceConfiguration.productIDs.isEmpty }

    func load() async {
        guard configured else { notice = "Subscriptions are not configured in this development build."; return }
        loading = true
        defer { loading = false }
        do {
            products = try await Product.products(for: CommerceConfiguration.productIDs).sorted { $0.price < $1.price }
            if products.isEmpty { notice = "No App Store products are available for this build." }
            await refreshEntitlements()
        } catch { notice = "The App Store could not be reached. Please try again." }
    }
    func listen() async {
        for await result in Transaction.updates {
            guard !Task.isCancelled else { return }
            guard case .verified(let transaction) = result else { continue }
            await refreshEntitlements()
            await transaction.finish()
        }
    }
    func purchase(_ product: Product) async {
        guard CommerceConfiguration.purchasesEnabled else { notice = "All features are free during development. Purchases are disabled."; return }
        purchasing = true; notice = nil
        defer { purchasing = false }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                guard case .verified(let transaction) = verification else { notice = "The purchase could not be verified. No access was granted."; return }
                await refreshEntitlements(); await transaction.finish()
                notice = "Purchase verified by the App Store."
            case .pending: notice = "Purchase is pending approval."
            case .userCancelled: break
            @unknown default: notice = "The App Store returned an unsupported purchase state."
            }
        } catch { notice = "The purchase could not be completed. Please try again." }
    }
    func restore() async {
        guard configured else { return }
        loading = true; notice = nil
        defer { loading = false }
        do {
            try await StoreKit.AppStore.sync()
            await refreshEntitlements()
            notice = activeProductIDs.isEmpty ? "No active purchases were found." : "Active purchases restored."
        } catch { notice = "Purchases could not be restored. Please try again." }
    }
    private func refreshEntitlements() async {
        var active: Set<String> = []
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  CommerceConfiguration.productIDs.contains(transaction.productID),
                  transaction.revocationDate == nil, !transaction.isUpgraded,
                  transaction.expirationDate.map({ $0 > .now }) ?? true else { continue }
            active.insert(transaction.productID)
        }
        activeProductIDs = active
    }
}
