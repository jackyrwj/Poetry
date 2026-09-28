import Foundation
import RevenueCat
import StoreKit
import UIKit

@MainActor
final class StoreManager: ObservableObject {
    static let shared = StoreManager()

    // MARK: - RevenueCat configuration
    static let revenueCatAPIKey = "appl_omoXbTGaAuAZaCAimwOuFShKVVt"
    static let entitlementID = "pro"

    // MARK: - Product IDs (must match App Store Connect)
    static let monthlyID = "com.raowenjie.Poetry.monthly"
    static let yearlyID = "com.raowenjie.Poetry.yearly"
    static let lifetimeID = "com.raowenjie.Poetry.lifetime"

    private static let allIDs: Set<String> = [monthlyID, yearlyID, lifetimeID]

    /// Must run before `StoreManager.shared` is first touched.
    static func configure() {
        #if DEBUG
        Purchases.logLevel = .debug
        #endif
        Purchases.configure(withAPIKey: revenueCatAPIKey)
    }

    // MARK: - Published state
    @Published private(set) var products: [StoreProduct] = []
    @Published private(set) var isLoading = false
    @Published private(set) var purchaseError: String?
    @Published private(set) var productLoadError: String?
    @Published private(set) var hasFinishedLoadingProducts = false
    /// Whether the current Apple ID can still redeem the monthly intro offer.
    @Published private(set) var isEligibleForMonthlyIntro = false

    /// Entitlement as reported by RevenueCat.
    @Published private(set) var hasRevenueCatEntitlement = false
    /// Entitlement read directly from StoreKit. Keeps paying users unlocked if
    /// RevenueCat is unreachable or has not yet seen a pre-RevenueCat purchase.
    @Published private(set) var hasLocalEntitlement = false

    private var customerInfoListener: Task<Void, Never>?
    private var foregroundObserver: Any?
    private var didSyncLegacyPurchases = false

    var monthly: StoreProduct? {
        product(id: Self.monthlyID)
    }

    var yearly: StoreProduct? {
        product(id: Self.yearlyID)
    }

    var lifetime: StoreProduct? {
        product(id: Self.lifetimeID)
    }

    var isPremium: Bool {
        hasRevenueCatEntitlement || hasLocalEntitlement
    }

    var hasCompleteProductCatalog: Bool {
        monthly != nil && yearly != nil && lifetime != nil
    }

    private init() {
        customerInfoListener = listenForCustomerInfo()

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
        customerInfoListener?.cancel()
        if let foregroundObserver {
            NotificationCenter.default.removeObserver(foregroundObserver)
        }
    }

    // MARK: - Load products
    func loadProducts() async {
        guard products.isEmpty, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        var loaded: [StoreProduct] = []
        if let offering = try? await Purchases.shared.offerings().current {
            loaded = offering.availablePackages.map(\.storeProduct)
        }
        // Fall back to fetching by ID if the dashboard offering is incomplete.
        if !Self.allIDs.isSubset(of: Set(loaded.map(\.productIdentifier))) {
            loaded = await Purchases.shared.products(Array(Self.allIDs))
        }

        products = loaded
            .filter { Self.allIDs.contains($0.productIdentifier) }
            .sorted { productSortIndex($0.productIdentifier) < productSortIndex($1.productIdentifier) }

        if products.isEmpty {
            productLoadError = AppLanguage.copy("無法載入購買選項，請稍後再試", "Unable to load purchase options. Try again later.")
        } else {
            productLoadError = hasCompleteProductCatalog ? nil : AppLanguage.copy("暫時無法取得完整購買選項，請稍後再試", "Unable to load every purchase option. Try again later.")
        }
        hasFinishedLoadingProducts = true
        await updateIntroEligibility()
    }

    /// The monthly intro offer, only when this user can still redeem it.
    var monthlyIntroOffer: StoreProductDiscount? {
        isEligibleForMonthlyIntro ? monthly?.introductoryDiscount : nil
    }

    private func updateIntroEligibility() async {
        guard let monthly, monthly.introductoryDiscount != nil else {
            isEligibleForMonthlyIntro = false
            return
        }
        let status = await Purchases.shared.checkTrialOrIntroDiscountEligibility(product: monthly)
        isEligibleForMonthlyIntro = status == .eligible
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
    func purchase(_ product: StoreProduct) async -> Bool {
        isLoading = true
        purchaseError = nil
        defer { isLoading = false }

        do {
            let result = try await Purchases.shared.purchase(product: product)
            guard !result.userCancelled else { return false }
            apply(result.customerInfo)
            await updateLocalEntitlement()
            await updateIntroEligibility()
            return isPremium
        } catch ErrorCode.purchaseCancelledError {
            return false
        } catch ErrorCode.paymentPendingError {
            purchaseError = AppLanguage.copy("購買待確認", "Purchase is pending confirmation.")
            return false
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

        var restoreFailed = false
        do {
            apply(try await Purchases.shared.restorePurchases())
        } catch {
            restoreFailed = true
        }
        await updateLocalEntitlement()

        if !isPremium {
            purchaseError = restoreFailed
                ? AppLanguage.copy("恢復失敗，請稍後再試", "Restore failed. Try again later.")
                : AppLanguage.copy("未找到可恢復的購買", "No purchases to restore.")
        }
    }

    func refreshPurchaseStatus() async {
        await updatePurchasedProducts()
    }

    func presentOfferCodeRedemption() async {
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else { return }

        do {
            // RevenueCat observes the resulting transaction itself.
            try await AppStore.presentOfferCodeRedeemSheet(in: windowScene)
            await updatePurchasedProducts()
        } catch {
            // The user may dismiss the sheet. Leave the current entitlement state unchanged.
        }
    }

    // MARK: - Customer info listener
    private func listenForCustomerInfo() -> Task<Void, Never> {
        Task { [weak self] in
            for await info in Purchases.shared.customerInfoStream {
                self?.apply(info)
            }
        }
    }

    // MARK: - Entitlements
    private func updatePurchasedProducts() async {
        await updateLocalEntitlement()

        if let info = try? await Purchases.shared.customerInfo() {
            apply(info)
        }

        // Purchases made before RevenueCat was integrated are unknown to it
        // until the SDK uploads them once.
        if hasLocalEntitlement, !hasRevenueCatEntitlement, !didSyncLegacyPurchases {
            didSyncLegacyPurchases = true
            if let info = try? await Purchases.shared.syncPurchases() {
                apply(info)
            }
        }
    }

    private func apply(_ info: CustomerInfo) {
        hasRevenueCatEntitlement = info.entitlements[Self.entitlementID]?.isActive == true
    }

    /// Read-only: RevenueCat finishes transactions, so this never calls `finish()`.
    private func updateLocalEntitlement() async {
        var entitled = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               Self.allIDs.contains(transaction.productID),
               transaction.revocationDate == nil {
                entitled = true
                break
            }
        }
        hasLocalEntitlement = entitled
    }

    private func product(id: String) -> StoreProduct? {
        products.first { $0.productIdentifier == id }
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
