import Foundation
import StoreKit
import UIKit

@MainActor
final class StoreManager: ObservableObject {
    static let shared = StoreManager()

    // MARK: - Product IDs (must match App Store Connect)
    static let monthlyID = "com.raowenjie.Poetry.monthly"
    static let yearlyID = "com.raowenjie.Poetry.yearly"
    static let lifetimeID = "com.raowenjie.Poetry.lifetime"

    private static let allIDs: Set<String> = [monthlyID, yearlyID, lifetimeID]

    // MARK: - Published state
    @Published private(set) var products: [Product] = []
    @Published private(set) var purchasedProductIDs: Set<String> = []
    @Published private(set) var isLoading = false
    @Published private(set) var purchaseError: String?
    @Published private(set) var productLoadError: String?
    @Published private(set) var hasFinishedLoadingProducts = false

    private var transactionListener: Task<Void, Never>?
    private var foregroundObserver: Any?

    var monthly: Product? {
        product(id: Self.monthlyID)
    }

    var yearly: Product? {
        product(id: Self.yearlyID)
    }

    var lifetime: Product? {
        product(id: Self.lifetimeID)
    }

    var isPremium: Bool {
        !purchasedProductIDs.isEmpty
    }

    var hasCompleteProductCatalog: Bool {
        monthly != nil && yearly != nil && lifetime != nil
    }

    private init() {
        transactionListener = listenForTransactions()

        Task {
            await loadProducts()
            await updatePurchasedProducts()
        }

        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.updatePurchasedProducts()
            }
        }
    }

    deinit {
        transactionListener?.cancel()
        if let foregroundObserver {
            NotificationCenter.default.removeObserver(foregroundObserver)
        }
    }

    // MARK: - Load products
    func loadProducts() async {
        guard products.isEmpty, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let storeProducts = try await Product.products(for: Self.allIDs)
            products = storeProducts.sorted { lhs, rhs in
                productSortIndex(lhs.id) < productSortIndex(rhs.id)
            }
            productLoadError = hasCompleteProductCatalog ? nil : AppLanguage.copy("暫時無法取得完整購買選項，請稍後再試", "Unable to load every purchase option. Try again later.")
        } catch {
            productLoadError = AppLanguage.copy("無法載入購買選項，請稍後再試", "Unable to load purchase options. Try again later.")
            print("StoreManager: Failed to load products - \(error)")
        }
        hasFinishedLoadingProducts = true
    }

    func reloadProducts() async {
        guard !isLoading else { return }
        products = []
        productLoadError = nil
        hasFinishedLoadingProducts = false
        await loadProducts()
    }

    // MARK: - Purchase
    @discardableResult
    func purchase(_ product: Product) async -> Bool {
        isLoading = true
        purchaseError = nil
        defer { isLoading = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                await updatePurchasedProducts()
                return isPremium
            case .userCancelled:
                return false
            case .pending:
                purchaseError = AppLanguage.copy("購買待確認", "Purchase is pending confirmation.")
                return false
            @unknown default:
                return false
            }
        } catch {
            purchaseError = AppLanguage.isEnglish ? "Purchase failed: \(error.localizedDescription)" : "購買失敗：\(error.localizedDescription)"
            return false
        }
    }

    // MARK: - Restore
    func restore() async {
        isLoading = true
        purchaseError = nil
        defer { isLoading = false }

        try? await AppStore.sync()
        await updatePurchasedProducts()
    }

    func refreshPurchaseStatus() async {
        await updatePurchasedProducts()
    }

    func presentOfferCodeRedemption() async {
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else { return }

        do {
            try await AppStore.presentOfferCodeRedeemSheet(in: windowScene)
            await updatePurchasedProducts()
        } catch {
            // The user may dismiss the sheet. Leave the current entitlement state unchanged.
        }
    }

    // MARK: - Transaction listener
    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                if let transaction = try? result.payloadValue {
                    await transaction.finish()
                    await self?.updatePurchasedProducts()
                }
            }
        }
    }

    // MARK: - Entitlements
    private func updatePurchasedProducts() async {
        var purchased: Set<String> = []

        for await result in Transaction.currentEntitlements {
            if let transaction = try? checkVerified(result),
               Self.allIDs.contains(transaction.productID) {
                purchased.insert(transaction.productID)
            }
        }

        purchasedProductIDs = purchased
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let value):
            return value
        }
    }

    private func product(id: String) -> Product? {
        products.first { $0.id == id }
    }

    private func productSortIndex(_ id: String) -> Int {
        switch id {
        case Self.monthlyID:
            return 0
        case Self.yearlyID:
            return 1
        case Self.lifetimeID:
            return 2
        default:
            return 99
        }
    }
}
