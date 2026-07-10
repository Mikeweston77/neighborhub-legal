import Foundation
import StoreKit
import Combine

// MARK: - Product IDs

enum NeighborHubProduct: String, CaseIterable {
    case singleMonthly    = "com.ml5ar66rq7.neighborhubwf3.subscription.single.monthly"
    case householdMonthly = "com.ml5ar66rq7.neighborhubwf3.subscription.household.monthly"

    var displayName: String {
        switch self {
        case .singleMonthly:    return "Single User"
        case .householdMonthly: return "Household (up to 5)"
        }
    }

    var description: String {
        switch self {
        case .singleMonthly:    return "Full access for one resident"
        case .householdMonthly: return "Full access for up to 5 household members"
        }
    }
}

// MARK: - Subscription Entitlement

enum SubscriptionEntitlement: Equatable {
    case none
    case single
    case household

    var isSubscribed: Bool { self != .none }
}

// MARK: - StoreKitManager

@MainActor
final class StoreKitManager: ObservableObject {
    static let shared = StoreKitManager()

    @Published private(set) var products: [Product] = []
    @Published private(set) var isLoadingProducts: Bool = false
    @Published private(set) var productsLoadError: String? = nil
    @Published private(set) var entitlement: SubscriptionEntitlement = .none
    @Published private(set) var purchaseState: PurchaseState = .idle

    enum PurchaseState: Equatable {
        case idle
        case purchasing
        case success
        case failed(String)
    }

    private var transactionListenerTask: Task<Void, Never>?

    private init() {
        transactionListenerTask = listenForTransactions()
        Task { await loadProducts() }
        Task { await refreshEntitlement() }
    }

    deinit {
        transactionListenerTask?.cancel()
    }

    // MARK: - Load Products

    func loadProducts() async {
        isLoadingProducts = true
        productsLoadError = nil
        defer { isLoadingProducts = false }

        do {
            let ids = NeighborHubProduct.allCases.map(\.rawValue)
            let loaded = try await Product.products(for: ids)
            // Sort: single first, then household
            products = loaded.sorted { lhs, rhs in
                let lhsOrder = NeighborHubProduct(rawValue: lhs.id)?.sortOrder ?? 99
                let rhsOrder = NeighborHubProduct(rawValue: rhs.id)?.sortOrder ?? 99
                return lhsOrder < rhsOrder
            }
            print("✅ StoreKitManager: Loaded \(products.count) products")
        } catch {
            productsLoadError = error.localizedDescription
            print("❌ StoreKitManager: Failed to load products: \(error.localizedDescription)")
        }
    }

    // MARK: - Purchase

    func purchase(_ product: Product) async {
        purchaseState = .purchasing
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    await transaction.finish()
                    await refreshEntitlement()
                    purchaseState = .success
                    print("✅ StoreKitManager: Purchase verified for \(product.id)")
                case .unverified(_, let error):
                    purchaseState = .failed("Purchase could not be verified: \(error.localizedDescription)")
                    print("❌ StoreKitManager: Unverified purchase: \(error.localizedDescription)")
                }
            case .pending:
                purchaseState = .idle
                print("⏳ StoreKitManager: Purchase pending approval")
            case .userCancelled:
                purchaseState = .idle
                print("ℹ️ StoreKitManager: User cancelled purchase")
            @unknown default:
                purchaseState = .idle
            }
        } catch {
            purchaseState = .failed(error.localizedDescription)
            print("❌ StoreKitManager: Purchase error: \(error.localizedDescription)")
        }
    }

    // MARK: - Restore Purchases

    func restorePurchases() async {
        do {
            try await AppStore.sync()
            await refreshEntitlement()
            print("✅ StoreKitManager: Purchases restored")
        } catch {
            print("❌ StoreKitManager: Restore failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Entitlement Check

    func refreshEntitlement() async {
        var resolved: SubscriptionEntitlement = .none

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard transaction.revocationDate == nil else { continue }

            switch transaction.productID {
            case NeighborHubProduct.householdMonthly.rawValue:
                resolved = .household
            case NeighborHubProduct.singleMonthly.rawValue:
                if resolved != .household { resolved = .single }
            default:
                break
            }
        }

        entitlement = resolved
        print("ℹ️ StoreKitManager: Entitlement refreshed → \(resolved)")
    }

    // MARK: - Transaction Listener

    private func listenForTransactions() -> Task<Void, Never> {
        Task(priority: .background) {
            for await result in Transaction.updates {
                guard case .verified(let transaction) = result else { continue }
                await transaction.finish()
                await refreshEntitlement()
                print("ℹ️ StoreKitManager: Transaction update processed for \(transaction.productID)")
            }
        }
    }

    // MARK: - Helpers

    func product(for kind: NeighborHubProduct) -> Product? {
        products.first { $0.id == kind.rawValue }
    }

    func resetPurchaseState() {
        purchaseState = .idle
    }
}

private extension NeighborHubProduct {
    var sortOrder: Int {
        switch self {
        case .singleMonthly:    return 0
        case .householdMonthly: return 1
        }
    }
}
