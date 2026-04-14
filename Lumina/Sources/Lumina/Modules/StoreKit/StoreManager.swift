// StoreManager.swift – StoreKit 2 hybrid purchase model
// Lumina: AI-powered reminders, task management, and focus app
//
// Purchase model:
//   • $14.99 one-time purchase → core app + 1 year of feature updates
//   • "Lumina Pro Pass" annual subscription → continued updates after year 1
//   • Features released after the 1-year purchase anniversary require an active subscription
//   • Base features remain unlocked forever

import Foundation
import StoreKit

// MARK: - Lumina Product IDs
enum LuminaProductID: String, CaseIterable {
    case baseApp         = "com.lumina.app.base"           // $14.99 one-time
    case proPassMonthly  = "com.lumina.pro.monthly"        // ~$2.99/month
    case proPassAnnual   = "com.lumina.pro.annual"         // ~$19.99/year
}

// MARK: - Feature Tier
enum FeatureTier {
    case base              // always available after base purchase
    case proOrRecent       // available with Pro Pass OR within 1 year of base purchase
    case proOnly           // always requires active Pro Pass
}

// MARK: - Purchase State
enum PurchaseState {
    case notPurchased
    case baseOnly(purchaseDate: Date)
    case proActive
    case proExpired(baseDate: Date)
}

// MARK: - StoreManager
@MainActor
final class StoreManager: ObservableObject {

    // MARK: - Published State
    @Published var products: [Product] = []
    @Published var purchaseState: PurchaseState = .notPurchased
    @Published var isLoading = false
    @Published var purchaseError: String?

    // MARK: - Private
    private var transactionListener: Task<Void, Error>?
    private let oneYearInSeconds: TimeInterval = 365.25 * 24 * 3600

    // MARK: - Init
    init() {
        transactionListener = startTransactionListener()
        Task { await loadProducts() }
        Task { await refreshPurchaseState() }
    }

    deinit {
        transactionListener?.cancel()
    }

    // MARK: - Load Products from App Store
    func loadProducts() async {
        isLoading = true
        defer { isLoading = false }
        do {
            products = try await Product.products(for: LuminaProductID.allCases.map(\.rawValue))
        } catch {
            purchaseError = "Failed to load products: \(error.localizedDescription)"
            print("[Lumina] StoreKit load error: \(error)")
        }
    }

    // MARK: - Purchase
    func purchase(_ productID: LuminaProductID) async throws {
        guard let product = products.first(where: { $0.id == productID.rawValue }) else {
            throw StoreError.productNotFound
        }

        isLoading = true
        defer { isLoading = false }

        let result = try await product.purchase()

        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await transaction.finish()
            await refreshPurchaseState()

        case .userCancelled:
            break

        case .pending:
            // Handle deferred purchases
            break

        @unknown default:
            break
        }
    }

    // MARK: - Restore Purchases
    func restorePurchases() async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await AppStore.sync()
            await refreshPurchaseState()
        } catch {
            purchaseError = "Restore failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Refresh Purchase State
    func refreshPurchaseState() async {
        // ── Check for active Pro subscription ──────────────────────────────
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result) else { continue }

            let productID = LuminaProductID(rawValue: transaction.productID)

            if productID == .proPassMonthly || productID == .proPassAnnual {
                if let expDate = transaction.expirationDate, expDate > Date() {
                    purchaseState = .proActive
                    return
                } else if transaction.revocationDate == nil && transaction.expirationDate == nil {
                    // Non-expiring (shouldn't happen for subscriptions, but be safe)
                    purchaseState = .proActive
                    return
                }
            }

            if productID == .baseApp {
                purchaseState = .baseOnly(purchaseDate: transaction.purchaseDate)
                // Continue checking for Pro subscription
            }
        }

        // If we found base but no active Pro, check if we're past the 1-year update window
        if case .baseOnly(let date) = purchaseState {
            let elapsed = Date().timeIntervalSince(date)
            if elapsed > oneYearInSeconds {
                purchaseState = .proExpired(baseDate: date)
            }
        }
    }

    // MARK: - Feature Gate
    /// Returns true if the given feature tier is unlocked for the current user.
    func isUnlocked(_ tier: FeatureTier) -> Bool {
        switch tier {
        case .base:
            switch purchaseState {
            case .notPurchased: return false
            default: return true
            }

        case .proOrRecent:
            switch purchaseState {
            case .notPurchased: return false
            case .proActive: return true
            case .baseOnly(let purchaseDate):
                let elapsed = Date().timeIntervalSince(purchaseDate)
                return elapsed <= oneYearInSeconds
            case .proExpired:
                return false
            }

        case .proOnly:
            if case .proActive = purchaseState { return true }
            return false
        }
    }

    /// Convenience: is any paid tier active?
    var isPurchased: Bool {
        if case .notPurchased = purchaseState { return false }
        return true
    }

    /// Description of the current access level for UI display
    var accessLevelDescription: String {
        switch purchaseState {
        case .notPurchased:
            return "Free"
        case .baseOnly(let date):
            let elapsed = Date().timeIntervalSince(date)
            let remaining = Int((oneYearInSeconds - elapsed) / (24 * 3600))
            return remaining > 0 ? "\(remaining) days of updates remaining" : "Base License"
        case .proActive:
            return "Lumina Pro"
        case .proExpired:
            return "Updates Expired – Subscribe to Continue"
        }
    }

    // MARK: - Transaction Listener
    private func startTransactionListener() -> Task<Void, Error> {
        Task.detached {
            for await result in Transaction.updates {
                do {
                    let transaction = try await self.checkVerified(result)
                    await self.refreshPurchaseState()
                    await transaction.finish()
                } catch {
                    print("[Lumina] Transaction verification failed: \(error)")
                }
            }
        }
    }

    // MARK: - Verification Helper
    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw StoreError.failedVerification(error)
        case .verified(let transaction):
            return transaction
        }
    }
}

// MARK: - Store Errors
enum StoreError: LocalizedError {
    case productNotFound
    case failedVerification(Error)
    case purchaseFailed(String)

    var errorDescription: String? {
        switch self {
        case .productNotFound:         return "Product not found in the App Store."
        case .failedVerification(let e): return "Receipt verification failed: \(e.localizedDescription)"
        case .purchaseFailed(let msg): return "Purchase failed: \(msg)"
        }
    }
}
