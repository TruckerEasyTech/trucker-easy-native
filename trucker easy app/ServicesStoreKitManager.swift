import StoreKit
import SwiftUI

// MARK: - Product IDs
enum TruckerEasyProduct {
    static let monthly = "com.truckereasy.monthly"
    static let annual  = "com.truckereasy.annual"

    static var allIDs: [String] { [monthly, annual] }
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
            // Sort so annual appears first
            products = loaded.sorted { a, _ in
                a.id == TruckerEasyProduct.annual
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

    // Formatted price string — falls back to hardcoded if not loaded yet
    func priceString(for id: String) -> String {
        if let p = product(for: id) { return p.displayPrice }
        return id == TruckerEasyProduct.annual ? "$169.99" : "$19.99"
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
