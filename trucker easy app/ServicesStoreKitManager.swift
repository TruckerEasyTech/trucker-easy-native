import StoreKit
import SwiftUI

// MARK: - Product IDs
enum TruckerEasyProduct {
    static let standardMonthly = "com.truckereasy.standard.monthly"
    static let standardAnnual  = "com.truckereasy.standard.annual"
    static let premiumMonthly  = "com.truckereasy.premium.monthly"
    static let premiumAnnual   = "com.truckereasy.premium.annual"

    // Legacy IDs already used by the current build. Treat them as Premium until
    // the new Standard/Premium product set is approved in App Store Connect.
    static let monthly = "com.truckereasy.monthly"
    static let annual  = "com.truckereasy.annual"

    static var allIDs: [String] {
        [standardMonthly, standardAnnual, premiumMonthly, premiumAnnual, monthly, annual]
    }
}

enum TruckerEasyPlan: Int, Comparable {
    case free = 0
    case standard = 1
    case premium = 2

    static func < (lhs: TruckerEasyPlan, rhs: TruckerEasyPlan) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var displayName: String {
        switch self {
        case .free: return "Free"
        case .standard: return "Standard"
        case .premium: return "Premium"
        }
    }

    var hasTruckRoutes: Bool { self >= .standard }
    var hasRouteIntelligence: Bool { self >= .premium }
    var hasAIWellnessAndLogbook: Bool { self >= .premium }
}

// MARK: - Store Manager
@Observable
final class StoreKitManager {
    static let shared = StoreKitManager()

    // Available products loaded from App Store
    private(set) var products: [Product] = []
    // Product IDs the user has active entitlements for
    private(set) var purchasedProductIDs: Set<String> = []
    // Whether user has an active pro subscription
    private(set) var isSubscribed = false
    private(set) var currentPlan: TruckerEasyPlan = .free

    /// Respects `AppAccessPolicy.unlockAllFeaturesForTesting` (Premium during QA).
    var effectivePlan: TruckerEasyPlan {
        AppAccessPolicy.unlockAllFeaturesForTesting ? .premium : currentPlan
    }

    var effectiveIsSubscribed: Bool {
        AppAccessPolicy.unlockAllFeaturesForTesting || isSubscribed
    }
    // Loading / error state
    private(set) var isLoading = false
    private(set) var isPurchasing = false
    private(set) var errorMessage: String?

    private var transactionListener: Task<Void, Error>?

    private init() {
        transactionListener = listenForTransactions()
        Task { await loadProducts() }
        Task { await refreshPurchasedProducts() }
    }

    deinit {
        transactionListener?.cancel()
    }

    // MARK: - Load Products
    @MainActor
    func loadProducts() async {
        isLoading = true
        errorMessage = nil
        do {
            let loaded = try await Product.products(for: TruckerEasyProduct.allIDs)
            products = loaded.sorted { a, b in
                productSortRank(a.id) < productSortRank(b.id)
            }
        } catch {
            errorMessage = "Could not load plans. Check your connection and try again."
        }
        isLoading = false
    }

    // MARK: - Purchase
    @MainActor
    func purchase(_ product: Product) async -> Bool {
        isPurchasing = true
        errorMessage = nil
        defer { isPurchasing = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await updatePurchasedProducts()
                await transaction.finish()
                return true
            case .userCancelled:
                return false
            case .pending:
                // Awaiting Ask to Buy / SCA
                errorMessage = "Purchase is pending approval."
                return false
            @unknown default:
                return false
            }
        } catch {
            errorMessage = "Purchase failed: \(error.localizedDescription)"
            return false
        }
    }

    // MARK: - Restore Purchases
    @MainActor
    func restorePurchases() async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await AppStore.sync()
            await refreshPurchasedProducts()
        } catch {
            errorMessage = "Restore failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Product Helpers
    func product(for id: String) -> Product? {
        products.first { $0.id == id }
    }

    var monthlyProduct: Product? { product(for: TruckerEasyProduct.monthly) }
    var annualProduct:  Product? { product(for: TruckerEasyProduct.annual)  }
    var standardMonthlyProduct: Product? { product(for: TruckerEasyProduct.standardMonthly) }
    var standardAnnualProduct: Product? { product(for: TruckerEasyProduct.standardAnnual) }
    var premiumMonthlyProduct: Product? { product(for: TruckerEasyProduct.premiumMonthly) ?? monthlyProduct }
    var premiumAnnualProduct: Product? { product(for: TruckerEasyProduct.premiumAnnual) ?? annualProduct }

    // Formatted price string — falls back to hardcoded if not loaded yet
    func priceString(for id: String) -> String {
        if let p = product(for: id) { return p.displayPrice }
        return id == TruckerEasyProduct.annual
            ? AppDistributionConfig.MarketingPrice.annualUSD
            : AppDistributionConfig.MarketingPrice.monthlyUSD
    }

    // MARK: - Transaction Listener
    private func listenForTransactions() -> Task<Void, Error> {
        Task.detached(priority: .background) { [weak self] in
            for await result in Transaction.updates {
                do {
                    guard let self else { continue }
                    let transaction = try await MainActor.run { try self.checkVerified(result) }
                    await self.updatePurchasedProducts()
                    await transaction.finish()
                } catch {
                    // Invalid transaction — ignore
                }
            }
        }
    }

    // MARK: - Entitlement Checks
    @MainActor
    func refreshPurchasedProducts() async {
        await updatePurchasedProducts()
    }

    @MainActor
    private func updatePurchasedProducts() async {
        var active: Set<String> = []
        for await result in Transaction.currentEntitlements {
            if let transaction = try? checkVerified(result) {
                if transaction.revocationDate == nil {
                    active.insert(transaction.productID)
                }
            }
        }
        purchasedProductIDs = active
        isSubscribed = !active.isEmpty
        currentPlan = Self.plan(for: active)
    }

    private static func plan(for productIDs: Set<String>) -> TruckerEasyPlan {
        if productIDs.contains(TruckerEasyProduct.premiumMonthly)
            || productIDs.contains(TruckerEasyProduct.premiumAnnual)
            || productIDs.contains(TruckerEasyProduct.monthly)
            || productIDs.contains(TruckerEasyProduct.annual) {
            return .premium
        }
        if productIDs.contains(TruckerEasyProduct.standardMonthly)
            || productIDs.contains(TruckerEasyProduct.standardAnnual) {
            return .standard
        }
        return .free
    }

    private func productSortRank(_ id: String) -> Int {
        switch id {
        case TruckerEasyProduct.premiumAnnual: return 0
        case TruckerEasyProduct.premiumMonthly: return 1
        case TruckerEasyProduct.standardAnnual: return 2
        case TruckerEasyProduct.standardMonthly: return 3
        case TruckerEasyProduct.annual: return 4
        case TruckerEasyProduct.monthly: return 5
        default: return 99
        }
    }

    // MARK: - Verification
    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let safe):
            return safe
        }
    }
}
