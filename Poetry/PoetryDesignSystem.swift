import SwiftUI
import UIKit
import CoreFoundation
import RevenueCat
import StoreKit

private func compactInscriptionText(_ text: String) -> String {
    text
        .replacingOccurrences(of: "\u{2009}", with: "")
        .replacingOccurrences(of: "\u{00A0}", with: "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

struct PaywallView: View {
    private enum Plan {
        case monthly
        case yearly
        case lifetime
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.poemTypeface) private var typeface
    @Environment(\.poemScript) private var script
    @ObservedObject private var store = StoreManager.shared
    @State private var selectedPlan: Plan = .monthly
    @State private var contentHeight: CGFloat = 0
    let onUnlock: () -> Void

    private static var features: [String] {
        AppLanguage.isEnglish
            ? ["Every included poem", "Every included poet", "Premium typefaces", "White seal style", "Premium papers and backgrounds"]
            : ["全部已收錄詩詞", "全部已收錄詩人", "高級字體", "朱印樣式·白文", "會員紙面與背景"]
    }

    private func priceText(_ product: StoreProduct?) -> String {
        product?.localizedPriceString ?? "…"
    }

    var body: some View {
        ZStack {
            PaperBackground()

            ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        HStack {
                            Spacer()
                            QuietBackButton(title: "關閉", spotlightStep: .returnFromShare) { dismiss() }
                        }
                        .padding(.bottom, -12)

                        VStack(alignment: .leading, spacing: 10) {
                            Text(AppLanguage.copy("雅集會員", "Pro").poemScript(script))
                                .font(typeface.titleFont)
                                .foregroundStyle(Color.ink)
                            Text(AppLanguage.copy("開通雅集，閱讀全部已收錄詩詞與詩人，解鎖更多創作樣式。", "Read every poem and meet every poet in the collection.").poemScript(script))
                                .font(typeface.smallFont)
                                .foregroundStyle(Color.mutedInk)
                        }

                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(Self.features, id: \.self) { feature in
                                PaywallFeatureRow(text: feature, compact: false)
                            }
                        }

                        if store.hasCompleteProductCatalog {
                            planSelection
                        } else {
                            productLoadingSection
                        }

                        if let error = store.purchaseError {
                            Text(error.poemScript(script))
                                .font(typeface.tinySealFont)
                                .foregroundStyle(Color.cinnabar)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }

                        footerActions

                    }
                    .padding(.horizontal, 30)
                    .padding(.top, 20)
                    .padding(.bottom, 28)
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(key: PaywallContentHeightKey.self, value: proxy.size.height)
                        }
                    }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .onPreferenceChange(PaywallContentHeightKey.self) { contentHeight = $0 }
        .task {
            await store.loadProducts()
        }
        // Size the sheet to its content so there is no empty band above or
        // between sections; the system caps it at full height on small screens.
        .presentationDetents(contentHeight > 0 ? [.height(contentHeight)] : [.large])
        .presentationDragIndicator(.visible)
        .presentationContentInteraction(.scrolls)
    }

    private var planSelection: some View {
        VStack(spacing: 12) {
            PaywallPlanButton(
                title: AppLanguage.copy("雅集月度", "Pro monthly"),
                price: priceText(store.monthly),
                note: monthlyPlanNote,
                isSelected: selectedPlan == .monthly
            ) {
                selectedPlan = .monthly
            }
            PaywallPlanButton(
                title: AppLanguage.copy("雅集年度", "Pro yearly"),
                price: priceText(store.yearly),
                note: AppLanguage.copy("每年自動續訂，可隨時取消", "Renews yearly. Cancel anytime."),
                isSelected: selectedPlan == .yearly
            ) {
                selectedPlan = .yearly
            }
            PaywallPlanButton(
                title: AppLanguage.copy("終身雅集", "Pro lifetime"),
                price: priceText(store.lifetime),
                note: AppLanguage.copy("一次購買，永久解鎖", "One payment. Lifetime access."),
                isSelected: selectedPlan == .lifetime
            ) {
                selectedPlan = .lifetime
            }

            Button {
                Task { await purchaseAndUnlock(selectedProduct) }
            } label: {
                Text(AppLanguage.copy("立即開通", "Continue").poemScript(script))
                    .font(typeface.smallFont)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color.cinnabar, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .disabled(selectedProduct == nil || store.isLoading)
            .opacity(selectedProduct == nil || store.isLoading ? 0.55 : 1)
        }
    }

    private var selectedProduct: StoreProduct? {
        switch selectedPlan {
        case .monthly:
            return store.monthly
        case .yearly:
            return store.yearly
        case .lifetime:
            return store.lifetime
        }
    }

    private func purchaseAndUnlock(_ product: StoreProduct?) async {
        guard let product else { return }
        let purchased = await store.purchase(product)
        if purchased {
            onUnlock()
            dismiss()
        }
    }

    private var footerActions: some View {
        VStack(spacing: 12) {
            HStack(spacing: 18) {
                restorePurchaseButton
                redemptionSection
            }
            legalLinksSection
        }
    }

    private var restorePurchaseButton: some View {
        Button {
            Task {
                await store.restore()
                if store.isPremium {
                    onUnlock()
                    dismiss()
                }
            }
        } label: {
            Text(AppLanguage.copy("恢復購買", "Restore purchases").poemScript(script))
                .font(typeface.tinySealFont)
                .foregroundStyle(Color.mutedInk)
        }
        .buttonStyle(.plain)
    }

    private var redemptionSection: some View {
        Button {
            presentOfferCodeRedemption()
        } label: {
            Text(AppLanguage.copy("兌換優惠碼", "Redeem offer code").poemScript(script))
                .font(typeface.tinySealFont)
                .foregroundStyle(Color.mutedInk)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var productLoadingSection: some View {
        VStack(spacing: 12) {
            if store.isLoading || !store.hasFinishedLoadingProducts {
                ProgressView()
                    .tint(Color.cinnabar)
                Text(AppLanguage.copy("正在取得購買選項…", "Loading purchase options…").poemScript(script))
                    .font(typeface.tinySealFont)
                    .foregroundStyle(Color.mutedInk)
            } else {
                Text((store.productLoadError ?? AppLanguage.copy("暫時無法取得購買選項", "Purchase options are unavailable right now.")).poemScript(script))
                    .font(typeface.smallFont)
                    .foregroundStyle(Color.mutedInk)
                    .multilineTextAlignment(.center)
                Button {
                    Task { await store.reloadProducts() }
                } label: {
                    Text(AppLanguage.copy("重新載入價格", "Reload prices").poemScript(script))
                        .font(typeface.smallFont)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .frame(height: 42)
                        .background(Color.cinnabar, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private var legalLinksSection: some View {
        HStack(spacing: 18) {
            Button {
                openLegalURL(AppLanguage.isEnglish
                    ? "https://jackyrwj.github.io/Poetry/terms-en.html"
                    : "https://jackyrwj.github.io/Poetry/terms.html")
            } label: {
                Text(AppLanguage.copy("用戶協議", "Terms of use").poemScript(script))
                    .font(typeface.tinySealFont)
                    .foregroundStyle(Color.cinnabar.opacity(0.85))
            }
            .buttonStyle(.plain)

            Rectangle()
                .fill(Color.mutedInk.opacity(0.22))
                .frame(width: 0.5, height: 12)

            Button {
                openLegalURL(AppLanguage.isEnglish
                    ? "https://jackyrwj.github.io/Poetry/privacy-en.html"
                    : "https://jackyrwj.github.io/Poetry/privacy.html")
            } label: {
                Text(AppLanguage.copy("隱私政策", "Privacy policy").poemScript(script))
                    .font(typeface.tinySealFont)
                    .foregroundStyle(Color.cinnabar.opacity(0.85))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func openLegalURL(_ rawValue: String) {
        guard let url = URL(string: rawValue) else { return }
        openURL(url)
    }

    private func presentOfferCodeRedemption() {
        Task {
            await store.presentOfferCodeRedemption()
            if store.isPremium {
                onUnlock()
                SensoryFeedback.lightTap()
                dismiss()
            }
        }
    }

    private var monthlyPlanNote: String {
        if let monthly = store.monthly, let offer = store.monthlyIntroOffer {
            return AppLanguage.isEnglish
                ? "First month \(offer.localizedPriceString), then \(monthly.localizedPriceString)/month. Cancel anytime."
                : "首月 \(offer.localizedPriceString)，之後 \(monthly.localizedPriceString)/月自動續訂，可隨時取消"
        }
        return AppLanguage.copy("每月自動續訂，可隨時取消", "Renews monthly. Cancel anytime.")
    }
}

private struct PaywallContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct PremiumStatusView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.poemTypeface) private var typeface
    @Environment(\.poemScript) private var script
    @ObservedObject private var store = StoreManager.shared

    var body: some View {
        ZStack {
            PaperBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(AppLanguage.copy("雅集會員", "Pro").poemScript(script))
                            .font(typeface.titleFont)
                            .foregroundStyle(Color.ink)
                        Text(AppLanguage.copy("已開通，感謝支持。", "You're all set. Thank you for your support.").poemScript(script))
                            .font(typeface.smallFont)
                            .foregroundStyle(Color.mutedInk)
                    }
                    Spacer()
                    QuietBackButton(title: "關閉") { dismiss() }
                }

                VStack(alignment: .leading, spacing: 14) {
                    PremiumFeatureRow(icon: "book.closed", text: AppLanguage.copy("全部已收錄詩詞", "Every included poem"))
                    PremiumFeatureRow(icon: "person.text.rectangle", text: AppLanguage.copy("全部已收錄詩人", "Every included poet"))
                    PremiumFeatureRow(icon: "textformat", text: AppLanguage.copy("全部字體", "All typefaces"))
                    PremiumFeatureRow(icon: "seal", text: AppLanguage.copy("朱印樣式：朱文與白文", "Seal styles, including white seals"))
                    PremiumFeatureRow(icon: "photo.artframe", text: AppLanguage.copy("全部紙面與背景", "All paper and backgrounds"))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(AppLanguage.copy("訂閱管理", "Subscription").poemScript(script))
                        .font(typeface.smallFont)
                        .foregroundStyle(Color.mutedInk)
                        .padding(.bottom, 4)

                    Button {
                        openSubscriptionManagement()
                    } label: {
                        HStack {
                            Text(AppLanguage.copy("管理訂閱", "Manage subscription").poemScript(script))
                                .font(typeface.smallFont)
                                .foregroundStyle(Color.cinnabar)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.cinnabar.opacity(0.6))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.white.opacity(0.58))
                                .stroke(Color.cinnabar.opacity(0.2), lineWidth: 0.8)
                        }
                    }
                    .buttonStyle(.plain)
                }

                }
                .padding(.horizontal, 30)
                .padding(.top, 28)
                .padding(.bottom, 36)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationContentInteraction(.scrolls)
    }

    private func openSubscriptionManagement() {
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else { return }
        Task {
            try? await AppStore.showManageSubscriptions(in: windowScene)
        }
    }
}

private struct PremiumFeatureRow: View {
    @Environment(\.poemTypeface) private var typeface
    @Environment(\.poemScript) private var script
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.cinnabar)
                .frame(width: 24)
            Text(text.poemScript(script))
                .font(typeface.smallFont)
                .foregroundStyle(Color.ink)
        }
    }
}

private struct PaywallFeatureRow: View {
    @Environment(\.poemTypeface) private var typeface
    @Environment(\.poemScript) private var script
    let text: String
    let compact: Bool

    var body: some View {
        HStack(alignment: .top, spacing: compact ? 7 : 10) {
            Image(systemName: "checkmark")
                .font(.system(size: compact ? 9 : 11, weight: .bold))
                .foregroundStyle(.white)
            .frame(width: compact ? 18 : 22, height: compact ? 18 : 22)
            .background(Circle().fill(Color.cinnabar))
            Text(text.poemScript(script))
                .font(compact ? typeface.tinySealFont : typeface.smallFont)
                .foregroundStyle(Color.ink)
                .lineLimit(compact ? 2 : nil)
                .minimumScaleFactor(compact ? 0.82 : 1)
        }
    }
}

private struct PaywallPlanButton: View {
    @Environment(\.poemTypeface) private var typeface
    @Environment(\.poemScript) private var script
    let title: String
    let price: String
    let note: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title.poemScript(script))
                        .font(typeface.smallFont)
                    if let note {
                        Text(note.poemScript(script))
                            .font(typeface.tinySealFont)
                            .foregroundStyle(isSelected ? Color.white.opacity(0.82) : Color.mutedInk)
                    }
                }
                Spacer()
                HStack(spacing: 10) {
                    Text(price)
                        .font(typeface.accentFont)
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 17, weight: .medium))
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(isSelected ? Color.white : Color.ink)
            .padding(.horizontal, 18)
            .frame(minHeight: AppLanguage.isEnglish ? 70 : 58)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.cinnabar : Color.white.opacity(0.6))
                    .stroke(isSelected ? Color.cinnabar : Color.mutedInk.opacity(0.22), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityValue(isSelected ? AppLanguage.copy("已選擇", "Selected") : "")
    }
}

enum AppReviewPrompt {
    static let completedFirstPoemKey = "poetry.completedFirstPoem"
    static let requestedAfterFirstPoemKey = "poetry.requestedReviewAfterFirstPoem"
    private static let lastRequestKey = "poetry.lastReviewRequestDate"
    private static let favoriteMilestonesKey = "poetry.reviewedFavoriteMilestones"
    /// Saving a poem is the clearest sign someone is enjoying the app.
    private static let favoriteMilestones = [3, 12]
    private static let minimumInterval: TimeInterval = 30 * 24 * 3600

    /// Keeps other prompts (such as the widget guide) from landing on top of this one.
    static var wasRequestedRecently: Bool {
        guard let last = UserDefaults.standard.object(forKey: lastRequestKey) as? Date else { return false }
        return Date().timeIntervalSince(last) < 24 * 3600
    }

    /// Asks once when the saved-poem count first reaches each milestone, at
    /// least 30 days after the previous request (the system also caps it at
    /// three times a year).
    static func requestAfterFavoriteIfNeeded(favoriteCount: Int) {
        let defaults = UserDefaults.standard
        var reached = Set(defaults.array(forKey: favoriteMilestonesKey) as? [Int] ?? [])
        guard let milestone = favoriteMilestones.last(where: { favoriteCount >= $0 }),
              !reached.contains(milestone) else { return }
        reached.formUnion(favoriteMilestones.filter { $0 <= milestone })
        defaults.set(Array(reached), forKey: favoriteMilestonesKey)

        if let last = defaults.object(forKey: lastRequestKey) as? Date,
           Date().timeIntervalSince(last) < minimumInterval { return }
        // Let the save animation finish before the system sheet appears.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { request() }
    }

    static func request() {
        Task { @MainActor in
            guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }) else {
                return
            }

            // Only record a request that was actually made.
            UserDefaults.standard.set(Date(), forKey: lastRequestKey)
            AppStore.requestReview(in: scene)
        }
    }
}

struct SmallCircleButton: View {
    @Environment(\.poemTypeface) private var typeface
    @Environment(\.poemScript) private var script
    @Environment(\.spotlightGuide) private var spotlightGuide
    var title: String? = nil
    var systemName: String? = nil
    var spotlightStep: SpotlightStep? = nil
    let action: () -> Void

    private var isSpotlightTarget: Bool {
        spotlightStep != nil && spotlightGuide.step == spotlightStep
    }

    private var displayTitle: String? {
        guard let title else { return nil }
        guard AppLanguage.isEnglish else { return title.poemScript(script) }
        switch title {
        case "換": return "Refresh"
        case "撰": return "Compose"
        case "書": return "Write"
        default: return title
        }
    }

    var body: some View {
        Button {
            action()
            if isSpotlightTarget {
                spotlightGuide.advance()
            }
        } label: {
            Group {
                if let systemName {
                    Image(systemName: systemName)
                        .font(.system(size: 18, weight: .semibold))
                } else if let displayTitle {
                    Text(displayTitle)
                        .font(AppLanguage.isEnglish ? .system(size: 11, weight: .semibold) : typeface.font(size: 17))
                }
            }
            .foregroundStyle(.white)
            .frame(width: AppLanguage.isEnglish && title != nil ? 68 : 44, height: 44)
            .background(Circle().fill(Color.cinnabar))
        }
        .buttonStyle(.plain)
        .spotlightTarget(spotlightStep ?? .selectMood, active: isSpotlightTarget)
    }
}

struct QuietBackButton: View {
    @Environment(\.poemTypeface) private var typeface
    @Environment(\.poemScript) private var script
    @Environment(\.spotlightGuide) private var spotlightGuide
    let title: String
    var spotlightStep: SpotlightStep? = nil
    let action: () -> Void

    private var isSpotlightTarget: Bool {
        spotlightStep != nil && spotlightGuide.step == spotlightStep
    }

    private var displayTitle: String {
        guard AppLanguage.isEnglish else { return title.poemScript(script) }
        switch title {
        case "返回": return "Back"
        case "關閉": return "Close"
        case "分享": return "Share"
        default: return title
        }
    }

    var body: some View {
        Button {
            action()
            if isSpotlightTarget {
                spotlightGuide.advance()
            }
        } label: {
            HStack(alignment: .center, spacing: 7) {
                Rectangle()
                    .fill(Color.cinnabar.opacity(0.7))
                    .frame(width: 1, height: AppLanguage.isEnglish ? 20 : 34)
                if AppLanguage.isEnglish {
                    Text(displayTitle)
                        .font(.system(size: 14, weight: .medium, design: .serif))
                        .foregroundStyle(Color.mutedInk)
                } else {
                    VerticalText(displayTitle, font: typeface.tinySealFont, color: .mutedInk, spacing: 3)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .spotlightTarget(spotlightStep ?? .selectMood, active: isSpotlightTarget)
    }
}

/// Back on the left and the page's quiet actions on the right, written on the
/// paper itself rather than in a navigation bar, so the artwork reads as one sheet.
struct PaperDetailTopBar<Actions: View>: View {
    @Environment(\.dismiss) private var dismiss
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            QuietBackButton(title: "返回") { dismiss() }
            Spacer()
            actions()
        }
        .padding(.horizontal, 22)
        .padding(.top, 4)
    }
}

/// Pages that draw their own back button hide the system bar, which would
/// otherwise also switch off the edge swipe back.
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        gestureRecognizer !== interactivePopGestureRecognizer || viewControllers.count > 1
    }
}

/// 「我的」tab: membership, reading defaults, personal seal and app info.
struct ProfileView: View {
    @Environment(\.poemTypeface) private var typeface
    @Environment(\.poemScript) private var script
    @AppStorage(PoemBackground.storageKey) private var selectedBgRaw = PoemBackground.defaultBackground.rawValue
    @AppStorage(PoemTypeface.storageKey) private var selectedTypefaceRaw = PoemTypeface.kaiti.rawValue
    @AppStorage(PoemScript.storageKey) private var selectedScriptRaw = PoemScript.simplified.rawValue
    @AppStorage(PoemTextLayout.storageKey) private var usesVerticalText = false
    @AppStorage(ShadowStyle.storageKey) private var selectedShadowRaw = ShadowStyle.defaultStyle.rawValue
    @AppStorage(SealStampView.storageKey) private var sealName = ""
    @AppStorage(SealStampStyle.storageKey) private var selectedSealStyleRaw = SealStampStyle.zhuwen.rawValue
    @AppStorage(NameTransliterator.overrideStorageKey) private var transliteration = ""
    @AppStorage(PoemLocationPreference.storageKey) private var showsInscriptionPlace = true
    @FocusState private var sealNameFocused: Bool
    @ObservedObject private var store = StoreManager.shared
    @State private var showsPaywall = false
    @State private var showsPremiumStatus = false
    @State private var legalDocument: LegalDocument?
    @State private var showsContact = false
    @State private var showsDeveloperLetter = false
    @State private var showsWidgetGuide = false
    @State private var showsMusicCredits = false

    private var hasPremiumAccess: Bool {
        store.isPremium
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PaperBackground()
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        Text(AppLanguage.copy("我的", "Settings").poemScript(script))
                            .font(typeface.font(size: 29))
                            .foregroundStyle(Color.ink)
                            .frame(minHeight: 38)

                        // Membership banner
                        if !hasPremiumAccess {
                            Button {
                                showsPaywall = true
                            } label: {
                                HStack(spacing: 12) {
                                    MembershipIndicator()
                                        .foregroundStyle(.white)
                                        .frame(width: 32, height: 32)
                                        .background(Circle().fill(Color.cinnabar))
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(AppLanguage.copy("雅集會員", "Pro").poemScript(script))
                                            .font(typeface.bodyFont)
                                            .foregroundStyle(Color.ink)
                                        Text(AppLanguage.copy("解鎖全部已收錄詩詞與詩人、字體、朱印與紙面", "Unlock every included poem and poet, plus premium typefaces, seals, and papers.").poemScript(script))
                                            .font(typeface.tinySealFont)
                                            .foregroundStyle(Color.mutedInk)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(Color.mutedInk.opacity(0.5))
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .background {
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color.white.opacity(0.84))
                                        .stroke(Color.cinnabar.opacity(0.2), lineWidth: 0.8)
                                }
                            }
                            .buttonStyle(.plain)
                        } else {
                            Button {
                                showsPremiumStatus = true
                            } label: {
                                HStack(spacing: 12) {
                                    MembershipIndicator()
                                        .foregroundStyle(.white)
                                        .frame(width: 32, height: 32)
                                        .background(Circle().fill(Color.cinnabar.opacity(0.7)))
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(AppLanguage.copy("雅集會員已開通", "Pro active").poemScript(script))
                                            .font(typeface.bodyFont)
                                            .foregroundStyle(Color.ink)
                                        Text(AppLanguage.copy("查看權益與訂閱狀態", "View benefits and subscription status").poemScript(script))
                                            .font(typeface.tinySealFont)
                                            .foregroundStyle(Color.mutedInk)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(Color.mutedInk.opacity(0.5))
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .background {
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color.white.opacity(0.84))
                                        .stroke(Color.cinnabar.opacity(0.15), lineWidth: 0.8)
                                }
                            }
                            .buttonStyle(.plain)
                        }

                        VStack(alignment: .leading, spacing: 20) {
                            Text(AppLanguage.copy("顯示與閱讀", "Display & reading").poemScript(script))
                                .font(typeface.bodyFont)
                                .foregroundStyle(Color.ink)
                            Text(AppLanguage.copy("用於日常閱讀，並作為新分享圖的默認外觀。", "Used throughout the app and as the default for new share images.").poemScript(script))
                                .font(typeface.tinySealFont)
                                .foregroundStyle(Color.mutedInk)

                            ArtworkPaperControls(
                                selectedShadowRaw: $selectedShadowRaw,
                                selectedBgRaw: $selectedBgRaw,
                                horizontalPadding: 0,
                                participatesInGuide: false
                            ) { showsPaywall = true }

                            ArtworkTextControls(
                                selectedTypefaceRaw: $selectedTypefaceRaw,
                                selectedScriptRaw: $selectedScriptRaw,
                                usesVerticalText: $usesVerticalText,
                                showsLayoutPicker: false
                            ) { showsPaywall = true }
                        }
                        .padding(18)
                        .settingsModuleSurface()

                        VStack(alignment: .leading, spacing: 16) {
                            Text(AppLanguage.copy("個人朱印", "Personal seal").poemScript(script))
                                .font(typeface.bodyFont)
                                .foregroundStyle(Color.ink)
                            Text(AppLanguage.copy("作為新作品與分享圖的默認署名。", "Your default signature for new poems and share images.").poemScript(script))
                                .font(typeface.tinySealFont)
                                .foregroundStyle(Color.mutedInk)
                            ArtworkSealControls(
                                sealName: $sealName,
                                selectedSealStyleRaw: $selectedSealStyleRaw,
                                transliteration: $transliteration,
                                sealNameFocused: $sealNameFocused
                            ) { showsPaywall = true }
                        }
                        .padding(18)
                        .settingsModuleSurface()

                        Toggle(isOn: $showsInscriptionPlace) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(AppLanguage.copy("落款顯示地點", "Show place in colophon").poemScript(script))
                                    .font(typeface.bodyFont)
                                    .foregroundStyle(Color.ink)
                                Text(AppLanguage.copy("關閉後，新作品與分享圖不再寫入所在城市，已保存作品的地點也會隱藏。", "When off, new poems and share images leave out your city, and places on saved poems are hidden.").poemScript(script))
                                    .font(typeface.tinySealFont)
                                    .foregroundStyle(Color.mutedInk)
                            }
                        }
                        .tint(Color.cinnabar)
                        .padding(18)
                        .settingsModuleSurface()

                        aboutSection

                        Text(appVersionText)
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(Color.mutedInk.opacity(0.6))
                            .frame(maxWidth: .infinity)
                    }
                    .padding(.top, 20)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationBarHidden(true)
            .navigationDestination(item: $legalDocument) { document in
                LegalDocumentView(document: document)
            }
            .navigationDestination(isPresented: $showsContact) {
                ContactSettingsView()
            }
        }
        .onAppear { normalizePreferences() }
        .onChange(of: store.isPremium) { _, _ in normalizePreferences() }
        .onChange(of: sealNameFocused) { _, focused in
            if !focused { sealName = ShareArtworkStyle.normalizedSealName(sealName) }
        }
        .onDisappear { sealName = ShareArtworkStyle.normalizedSealName(sealName) }
        .sheet(isPresented: $showsPremiumStatus) {
            PremiumStatusView()
        }
        .sheet(isPresented: $showsDeveloperLetter) {
            DeveloperLetterView()
        }
        .sheet(isPresented: $showsWidgetGuide) {
            WidgetGuideView()
        }
        .sheet(isPresented: $showsMusicCredits) {
            PoemMusicCreditsSheet()
        }
        .sheet(isPresented: $showsPaywall) {
            PaywallView {
                showsPaywall = false
            }
        }
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(AppLanguage.copy("關於诗客", "About Ink & Verse").poemScript(script))
                .font(typeface.bodyFont)
                .foregroundStyle(Color.ink)
                .padding(.bottom, 4)

            ProfileRow(title: AppLanguage.copy("桌面小組件", "Home Screen widget"), mark: "件") {
                showsWidgetGuide = true
            }

            ProfileRow(title: AppLanguage.copy("開發者的一封信", "A letter from the developer"), mark: "箋") {
                showsDeveloperLetter = true
            }

            ShareLink(item: AppLanguage.copy("我在用诗客，以今日心绪生成一首古诗。", "I'm using Ink & Verse to create classical Chinese poetry.")) {
                ProfileRowLabel(title: AppLanguage.copy("分享給好友", "Share with friends"), mark: "享")
            }
            .buttonStyle(.plain)

            ProfileRow(title: AppLanguage.copy("聯繫我們", "Contact us"), mark: "信") {
                showsContact = true
            }

            ProfileRow(title: AppLanguage.copy("用戶協議", "Terms of use"), mark: "約") {
                legalDocument = .terms
            }

            ProfileRow(title: AppLanguage.copy("隱私政策", "Privacy policy"), mark: "隱") {
                legalDocument = .privacy
            }

            ProfileRow(title: AppLanguage.copy("音樂致謝", "Music credits"), mark: "樂") {
                showsMusicCredits = true
            }
        }
        .padding(18)
        .settingsModuleSurface()
    }

    private var appVersionText: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(AppLanguage.copy("版本", "Version").poemScript(script)) \(version) (\(build))"
    }

    private func normalizePreferences() {
        guard !hasPremiumAccess else { return }
        if let background = PoemBackground(rawValue: selectedBgRaw),
           !SeasonalAppearance.hasAccess(to: background, isPremium: hasPremiumAccess) {
            selectedBgRaw = PoemBackground.defaultBackground.rawValue
        }
        if PoemTypeface(rawValue: selectedTypefaceRaw)?.isFree == false {
            selectedTypefaceRaw = PoemTypeface.kaiti.rawValue
        }
        if SealStampStyle(rawValue: selectedSealStyleRaw)?.isFree == false {
            selectedSealStyleRaw = SealStampStyle.zhuwen.rawValue
        }
    }
}

private extension View {
    /// Keeps settings readable when a reader has chosen a detailed paper or
    /// background image. The shared surface also makes the top-level groups
    /// scan like the cards used in the other tabs.
    func settingsModuleSurface() -> some View {
        background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.86))
                .stroke(Color.mutedInk.opacity(0.16), lineWidth: 0.8)
        }
    }
}

private struct ProfileRow: View {
    let title: String
    let mark: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ProfileRowLabel(title: title, mark: mark)
        }
        .buttonStyle(.plain)
    }
}

private struct ProfileRowLabel: View {
    @Environment(\.poemTypeface) private var typeface
    @Environment(\.poemScript) private var script
    let title: String
    let mark: String

    var body: some View {
        HStack(spacing: 12) {
            Text(mark.poemScript(script))
                .font(typeface.tinySealFont)
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.cinnabar))

            Text(title.poemScript(script))
                .font(typeface.smallFont)
                .foregroundStyle(Color.ink)

            Spacer()

            Text("›")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(Color.cinnabar.opacity(0.78))
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .contentShape(Rectangle())
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.55))
                .stroke(Color.mutedInk.opacity(0.18), lineWidth: 0.8)
        }
    }
}

private struct ContactSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.poemTypeface) private var typeface
    @Environment(\.poemScript) private var script
    @State private var showsMailComposer = false
    @State private var copiedEmail = false

    var body: some View {
        ZStack {
            PaperBackground()

            VStack(spacing: 0) {
                HStack(alignment: .top) {
                    Text(AppLanguage.copy("聯繫我們", "Contact us").poemScript(script))
                        .font(typeface.titleFont)
                        .foregroundStyle(Color.ink)

                    Spacer()

                    QuietBackButton(title: "返回") { dismiss() }
                }
                .padding(.horizontal, 30)
                .padding(.top, 56)
                .padding(.bottom, 28)

                VStack(alignment: .leading, spacing: 18) {
                    contactRow(
                        title: AppLanguage.copy("寫信反饋", "Email feedback"),
                        value: copiedEmail ? AppLanguage.copy("已複製郵箱", "Email copied") : FeedbackMail.recipient,
                        mark: "郵"
                    ) {
                        FeedbackMail.compose(showComposer: $showsMailComposer) {
                            withAnimation { copiedEmail = true }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                withAnimation { copiedEmail = false }
                            }
                        }
                    }

                    contactRow(title: AppLanguage.copy("App Store 評價", "Review on the App Store"), value: "", mark: "評") {
                        AppStoreLinks.openWriteReview()
                    }

                    // Xiaohongshu is only meaningful to Chinese-speaking readers.
                    if !AppLanguage.isEnglish {
                        contactRow(title: "小紅書", value: "织诗", mark: "書") {
                            if let url = URL(string: "https://www.xiaohongshu.com/user/profile/608e5e7500000000010050c2") {
                                openURL(url)
                            }
                        }
                    }

                    Text(AppLanguage.copy("有想法、問題，或想分享你喜歡的詩，都可以來找我。", "Ideas, problems, or a poem you love: I'd be glad to hear from you.").poemScript(script))
                        .font(typeface.tinySealFont)
                        .foregroundStyle(Color.mutedInk)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 30)

                Spacer()
            }
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $showsMailComposer) {
            FeedbackMailComposer()
                .ignoresSafeArea()
        }
    }

    private func contactRow(title: String, value: String, mark: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(mark.poemScript(script))
                    .font(typeface.tinySealFont)
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.cinnabar))

                Text(title.poemScript(script))
                    .font(typeface.smallFont)
                    .foregroundStyle(Color.ink)

                Spacer()

                Text(value.poemScript(script))
                    .font(typeface.tinySealFont)
                    .foregroundStyle(Color.mutedInk)
                    .lineLimit(1)

                Text("›")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(Color.cinnabar.opacity(0.78))
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.55))
                    .stroke(Color.mutedInk.opacity(0.18), lineWidth: 0.8)
            }
        }
        .buttonStyle(.plain)
    }
}

private enum LegalDocument: String, Identifiable {
    case terms
    case privacy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .terms: return AppLanguage.copy("用戶協議", "Terms of use")
        case .privacy: return AppLanguage.copy("隱私政策", "Privacy policy")
        }
    }

    var bodyText: String {
        if AppLanguage.isEnglish {
            switch self {
            case .terms:
                return """
                Welcome to Ink & Verse. By downloading, installing, or using the app, you agree to these terms.

                Ink & Verse helps you create classical Chinese poetry. You choose imagery and select from an offline, editor-curated line library to shape a poem.

                You own the poems you create in the app and may use, share, or publish them. Curated candidate lines and their combinations may resemble other works, so we do not guarantee that a poem is unique.

                Do not use the app to create unlawful content or content that infringes another person's rights. Do not reverse engineer, decompile, or disassemble the app.

                Candidate lines are selected and combined on your device. The app is provided as is, without express or implied warranties.

                We may update these terms. Continued use after an update means you accept the revised terms.

                Full terms: https://jackyrwj.github.io/Poetry/terms-en.html

                Contact: raowenjieszu@gmail.com
                """
            case .privacy:
                return """
                Ink & Verse respects your privacy.

                With your permission, the app uses only your city name to add a place to a poem's inscription. It does not record precise coordinates or keep location history. You can turn off location access in Settings at any time.

                Your poems, preferences, and saved work are stored on your device. They are not uploaded to our servers.

                Poem-composition choices and candidate-line matching are processed on your device and are not sent to an external content-generation service.

                The app does not collect advertising identifiers and does not include advertising, analytics, or social-media SDKs. We do not sell personal information.

                Full privacy policy: https://jackyrwj.github.io/Poetry/privacy-en.html

                Contact: raowenjieszu@gmail.com
                """
            }
        }

        switch self {
        case .terms:
            return """
            歡迎使用「詩客」。下載、安裝或使用本應用即表示你同意以下條款。

            本應用是一款古典中文詩歌創作輔助工具。用戶選擇意境後，應用從內置的人工編選詩句庫中匹配候選句，逐句擇選完成詩歌創作。

            你通過本應用創作的詩歌作品歸你所有，可自由使用、分享和發佈。但內置候選句及其組合可能與其他作品相似，本應用不對內容的獨創性作出保證。

            使用本應用時，請勿生成違反法律法規或侵犯他人權益的內容，不得對本應用進行逆向工程、反編譯或反匯編。

            候選詩句的匹配與組合均在設備本地完成。本應用按「現狀」提供，不作任何明示或暗示的保證。

            我們可能會不時更新本協議。更新後繼續使用，即表示你接受更新內容。

            完整協議：https://jackyrwj.github.io/Poetry/terms.html

            聯繫郵箱：raowenjieszu@gmail.com
            """
        case .privacy:
            return """
            「詩客」重視你的隱私。

            經你明確授權後，本應用僅獲取你所在城市的名稱，用於在詩歌落款處顯示創作地點。我們不會記錄你的精確地理坐標，也不會存儲你的位置歷史。你可以隨時在系統設置中關閉位置權限。

            你在應用內的所有創作數據均存儲在設備本地，不會上傳至任何伺服器。我們無法訪問你的創作內容。

            寫詩功能中的意境選擇、候選句匹配與詩作組合均在你的設備本地完成，不會發送至外部內容生成服務。

            本應用不會主動收集你的設備標識符或廣告標識符，不集成任何廣告、分析或社交媒體 SDK。我們不會出售你的個人信息。

            完整隱私政策：https://jackyrwj.github.io/Poetry/privacy.html

            聯繫郵箱：raowenjieszu@gmail.com
            """
        }
    }
}

private struct LegalDocumentView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.poemTypeface) private var typeface
    @Environment(\.poemScript) private var script
    let document: LegalDocument

    var body: some View {
        ZStack {
            PaperBackground()

            VStack(spacing: 0) {
                HStack(alignment: .top) {
                    Text(document.title.poemScript(script))
                        .font(typeface.titleFont)
                        .foregroundStyle(Color.ink)

                    Spacer()

                    QuietBackButton(title: "返回") { dismiss() }
                }
                .padding(.horizontal, 30)
                .padding(.top, 56)
                .padding(.bottom, 26)

                ScrollView(.vertical, showsIndicators: false) {
                    Text(document.bodyText.poemScript(script))
                        .font(typeface.smallFont)
                        .foregroundStyle(Color.ink)
                        .lineSpacing(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 30)
                        .padding(.bottom, 60)
                }
            }
        }
        .navigationBarHidden(true)
    }
}

private struct ScriptStylePicker: View {
    @Environment(\.poemTypeface) private var typeface
    @Environment(\.poemScript) private var script
    @Binding var selectedRawValue: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(AppLanguage.copy("字形", "Script").poemScript(script))
                .font(typeface.smallFont)
                .foregroundStyle(Color.mutedInk)

            HStack(spacing: 18) {
                ForEach(PoemScript.allCases) { item in
                    Button {
                        selectedRawValue = item.rawValue
                    } label: {
                        HStack(spacing: 8) {
                            Text(item.displayName)
                                .font(typeface.smallFont)
                                .foregroundStyle(selectedRawValue == item.rawValue ? Color.ink : Color.mutedInk)
                            SelectionIndicator(isSelected: selectedRawValue == item.rawValue, size: 22)
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 36)
                        .background {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(selectedRawValue == item.rawValue ? Color.cinnabar.opacity(0.8) : Color.mutedInk.opacity(0.25), lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

enum PoemTextLayout {
    static let storageKey = "poemUsesVerticalText"
}

enum ShareArtworkLayout: String, CaseIterable, Identifiable, Hashable {
    case portrait
    case landscape

    var id: String { rawValue }

    var label: String {
        switch self {
        case .portrait: return AppLanguage.copy("豎版", "Portrait")
        case .landscape: return AppLanguage.copy("橫版", "Landscape")
        }
    }

    var canvasSize: CGSize {
        switch self {
        case .portrait:
            return CGSize(width: 1080, height: 1620)
        case .landscape:
            return CGSize(width: 1600, height: 1000)
        }
    }

    var aspectRatio: CGFloat {
        canvasSize.width / canvasSize.height
    }
}

/// A snapshot shared by the thumbnail, fullscreen preview, and JPEG renderer.
struct ShareArtworkStyle: Hashable {
    let background: PoemBackground
    let typeface: PoemTypeface
    let script: PoemScript
    let usesVerticalText: Bool
    let sealName: String
    let sealStyle: SealStampStyle
    let transliteration: String
    let shadow: ShadowStyle
}

/// The English reading printed beneath (or beside) the Chinese artwork on an
/// English share image. The artwork itself — verse, colophon, seal — stays Chinese.
struct ShareTranslation: Hashable {
    let title: String
    let byline: String
    let text: String
}

extension ShareArtworkStyle {
    static var defaultPreferences: ShareArtworkStyle {
        let defaults = UserDefaults.standard
        return ShareArtworkStyle(
            background: PoemBackground(rawValue: defaults.string(forKey: PoemBackground.storageKey) ?? "") ?? .defaultBackground,
            typeface: PoemTypeface(rawValue: defaults.string(forKey: PoemTypeface.storageKey) ?? "") ?? .kaiti,
            script: PoemScript(rawValue: defaults.string(forKey: PoemScript.storageKey) ?? "") ?? .simplified,
            // Fresh share images default to traditional vertical verse; an
            // explicitly saved preference (via "Set as default") still wins.
            usesVerticalText: defaults.object(forKey: PoemTextLayout.storageKey) as? Bool ?? true,
            sealName: defaults.string(forKey: SealStampView.storageKey) ?? "",
            sealStyle: SealStampStyle(rawValue: defaults.string(forKey: SealStampStyle.storageKey) ?? "") ?? .zhuwen,
            transliteration: defaults.string(forKey: NameTransliterator.overrideStorageKey) ?? "",
            shadow: ShadowStyle(rawValue: defaults.string(forKey: ShadowStyle.storageKey) ?? "") ?? .defaultStyle
        )
    }

    func replacingBackground(_ background: PoemBackground) -> ShareArtworkStyle {
        ShareArtworkStyle(
            background: background, typeface: typeface, script: script,
            usesVerticalText: usesVerticalText, sealName: sealName, sealStyle: sealStyle,
            transliteration: transliteration, shadow: shadow
        )
    }

    static func normalizedSealName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains(where: { $0.isCJK }) else { return String(trimmed.prefix(24)) }
        return String(NameTransliterator.rawSealText(trimmed).prefix(4))
    }
}

extension SavedPoem {
    var artworkStyle: ShareArtworkStyle {
        let defaults = UserDefaults.standard
        return ShareArtworkStyle(
            background: PoemBackground(rawValue: backgroundRawValue ?? defaults.string(forKey: PoemBackground.storageKey) ?? "") ?? .defaultBackground,
            typeface: PoemTypeface(rawValue: typefaceRawValue ?? defaults.string(forKey: PoemTypeface.storageKey) ?? "") ?? .kaiti,
            script: PoemScript(rawValue: scriptRawValue ?? defaults.string(forKey: PoemScript.storageKey) ?? "") ?? .simplified,
            // “藏诗” preserves the traditional vertical reading direction.
            usesVerticalText: true,
            sealName: sealName ?? defaults.string(forKey: SealStampView.storageKey) ?? "",
            sealStyle: SealStampStyle(rawValue: sealStyleRawValue ?? defaults.string(forKey: SealStampStyle.storageKey) ?? "") ?? .zhuwen,
            transliteration: sealTransliteration ?? defaults.string(forKey: NameTransliterator.overrideStorageKey) ?? "",
            shadow: ShadowStyle(rawValue: shadowRawValue ?? defaults.string(forKey: ShadowStyle.storageKey) ?? "") ?? .defaultStyle
        )
    }

    func applyingArtworkStyle(_ style: ShareArtworkStyle) -> SavedPoem {
        var updated = self
        updated.typefaceRawValue = style.typeface.rawValue
        updated.backgroundRawValue = style.background.rawValue
        updated.usesVerticalText = true
        updated.sealName = style.sealName
        updated.scriptRawValue = style.script.rawValue
        updated.sealStyleRawValue = style.sealStyle.rawValue
        updated.sealTransliteration = style.transliteration
        updated.shadowRawValue = style.shadow.rawValue
        return updated
    }
}

/// Shared presentation for authored poems and bookmarked classics.
struct PoemArchiveCard<Artwork: View>: View {
    @Environment(\.poemTypeface) private var typeface
    let title: String
    let subtitle: String
    var titleLineLimit = 1
    @ViewBuilder let artwork: () -> Artwork

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            artwork()
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay {
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(Color.mutedInk.opacity(0.18), lineWidth: 0.7)
                }
                .shadow(color: Color.ink.opacity(0.08), radius: 5, y: 2)

            Text(title)
                .font(typeface.smallFont)
                .foregroundStyle(Color.ink)
                .lineLimit(titleLineLimit)

            Text(subtitle)
                .font(.system(size: 10))
                .foregroundStyle(Color.mutedInk.opacity(0.68))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct ConfiguredShareArtwork: View {
    let layout: ShareArtworkLayout
    let imageTitle: String
    let lines: [String]
    let locationMark: String?
    let lunarDateText: String
    let dayPeriodText: String
    let style: ShareArtworkStyle
    var translation: ShareTranslation? = nil
    var extraTopPadding: CGFloat = 0
    var extraBottomPadding: CGFloat = 0

    var body: some View {
        SharePoemArtwork(
            layout: layout,
            imageTitle: imageTitle,
            lines: lines,
            locationMark: locationMark,
            lunarDateText: lunarDateText,
            dayPeriodText: dayPeriodText,
            sealName: style.sealName,
            showsLight: true,
            showsSeal: !style.sealName.isEmpty,
            showsTitle: true,
            background: style.background,
            usesVerticalTextOverride: style.usesVerticalText,
            sealStyleOverride: style.sealStyle,
            sealTransliterationOverride: style.transliteration,
            shadowStyleOverride: style.shadow,
            translation: translation,
            extraTopPadding: extraTopPadding,
            extraBottomPadding: extraBottomPadding
        )
        .environment(\.poemTypeface, style.typeface)
        .environment(\.poemScript, style.script)
    }
}

private enum ShareConfigurationSection: String, CaseIterable, Identifiable {
    case paper, text, seal
    var id: String { rawValue }
    var label: String {
        switch self {
        case .paper: AppLanguage.copy("紙面", "Paper")
        case .text: AppLanguage.copy("文字", "Text")
        case .seal: AppLanguage.copy("朱印", "Seal")
        }
    }
}

struct PoemSharePreviewView: View {
    let imageTitle: String
    let lines: [String]
    let locationMark: String?
    let lunarDateText: String
    let dayPeriodText: String
    var translation: ShareTranslation? = nil
    var savedStyle: ShareArtworkStyle? = nil
    /// Opens on this paper instead of the default, e.g. a classic's own paper,
    /// so the share page matches the card it was opened from.
    var initialBackground: PoemBackground? = nil
    var availableLayouts: [ShareArtworkLayout] = ShareArtworkLayout.allCases

    var body: some View {
        PoemArtworkWorkspace(
            imageTitle: imageTitle, lines: lines, locationMark: locationMark,
            lunarDateText: lunarDateText, dayPeriodText: dayPeriodText,
            translation: translation,
            initialStyle: savedStyle,
            initialBackground: initialBackground,
            availableLayouts: availableLayouts
        )
    }
}

struct PoemArtworkEditorView: View {
    let poem: SavedPoem
    let onSave: (SavedPoem) -> Void

    var body: some View {
        PoemArtworkWorkspace(
            imageTitle: poem.imageTitle, lines: poem.lines, locationMark: poem.locationText,
            lunarDateText: poem.lunarDateText, dayPeriodText: poem.dayPeriodText,
            initialStyle: poem.artworkStyle,
            onSave: { onSave(poem.applyingArtworkStyle($0)) }
        )
    }
}

private struct PoemArtworkWorkspace: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.poemTypeface) private var typeface
    @Environment(\.poemScript) private var script
    @Environment(\.spotlightGuide) private var spotlightGuide
    @ObservedObject private var store = StoreManager.shared
    @State private var selectedBgRaw: String
    @State private var selectedTypefaceRaw: String
    @State private var selectedScriptRaw: String
    @State private var usesVerticalText: Bool
    @State private var sealName: String
    @State private var selectedSealStyleRaw: String
    @State private var transliteration: String
    @State private var selectedShadowRaw: String
    @State private var section = ShareConfigurationSection.paper
    @State private var preparedShareItems: [ShareArtworkLayout: PreparedShareItem] = [:]
    @State private var previewLayout: ShareArtworkLayout?
    @State private var pagedLayout: ShareArtworkLayout = .portrait
    @State private var showsPaywall = false
    @State private var showsPaperChoice = false
    /// Set from the paper choice sheet; acted on once that sheet is gone.
    @State private var opensPaywallAfterChoice = false
    @FocusState private var sealNameFocused: Bool

    let imageTitle: String
    let lines: [String]
    let locationMark: String?
    let lunarDateText: String
    let dayPeriodText: String
    let translation: ShareTranslation?

    let initialStyle: ShareArtworkStyle?
    let availableLayouts: [ShareArtworkLayout]
    var onSave: ((ShareArtworkStyle) -> Void)? = nil

    init(
        imageTitle: String, lines: [String], locationMark: String?,
        lunarDateText: String, dayPeriodText: String,
        translation: ShareTranslation? = nil,
        initialStyle: ShareArtworkStyle? = nil,
        initialBackground: PoemBackground? = nil,
        availableLayouts: [ShareArtworkLayout] = ShareArtworkLayout.allCases,
        onSave: ((ShareArtworkStyle) -> Void)? = nil
    ) {
        self.imageTitle = imageTitle
        self.lines = lines
        self.locationMark = locationMark
        self.lunarDateText = lunarDateText
        self.dayPeriodText = dayPeriodText
        self.translation = translation
        self.initialStyle = initialStyle
        self.availableLayouts = availableLayouts
        self.onSave = onSave
        let draft = initialStyle ?? ShareArtworkStyle.defaultPreferences
        _selectedBgRaw = State(initialValue: (initialBackground ?? draft.background).rawValue)
        _selectedTypefaceRaw = State(initialValue: draft.typeface.rawValue)
        _selectedScriptRaw = State(initialValue: draft.script.rawValue)
        _usesVerticalText = State(initialValue: draft.usesVerticalText)
        _sealName = State(initialValue: draft.sealName)
        _selectedSealStyleRaw = State(initialValue: draft.sealStyle.rawValue)
        _transliteration = State(initialValue: draft.transliteration)
        _selectedShadowRaw = State(initialValue: draft.shadow.rawValue)
    }

    private var showsConfiguration: Bool { onSave != nil || initialStyle == nil }

    /// A poem may preview and keep a premium paper even for a free reader;
    /// membership is checked only when the reader actually shares it.
    private var requiresPremiumToShare: Bool {
        !SeasonalAppearance.hasAccess(to: style.background, isPremium: store.isPremium)
    }

    private var style: ShareArtworkStyle {
        // Sharing an archived work preserves its saved appearance.
        if onSave == nil, let initialStyle { return initialStyle }
        let background = PoemBackground(rawValue: selectedBgRaw) ?? .defaultBackground
        let font = PoemTypeface(rawValue: selectedTypefaceRaw) ?? .kaiti
        let seal = SealStampStyle(rawValue: selectedSealStyleRaw) ?? .zhuwen
        return ShareArtworkStyle(
            background: background,
            typeface: !font.isFree && !store.isPremium ? .kaiti : font,
            script: PoemScript(rawValue: selectedScriptRaw) ?? .simplified,
            usesVerticalText: usesVerticalText,
            sealName: ShareArtworkStyle.normalizedSealName(sealName),
            sealStyle: !seal.isFree && !store.isPremium ? .zhuwen : seal,
            transliteration: transliteration,
            shadow: ShadowStyle(rawValue: selectedShadowRaw) ?? .defaultStyle
        )
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            VStack(spacing: 0) {
                HStack(alignment: .top) {
                    if onSave != nil {
                        // Edits save as they happen, so the corner offers sharing instead.
                        QuietBackButton(title: AppLanguage.copy("返回", "Back")) { dismiss() }
                        Spacer()
                        shareButton
                    } else {
                        QuietBackButton(title: "返回") { dismiss() }
                        Spacer()
                        shareButton
                    }
                }
                .padding(.horizontal, 30)
                .padding(.top, 16)
                .padding(.bottom, 18)

                layoutPager
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if showsConfiguration { configurationPanel }
            }

            if let layout = previewLayout {
                ShareFullscreenPreview(
                    layout: layout,
                    imageTitle: imageTitle,
                    lines: lines,
                    locationMark: locationMark,
                    lunarDateText: lunarDateText,
                    dayPeriodText: dayPeriodText,
                    style: style,
                    translation: translation,
                    onDismiss: { previewLayout = nil }
                )
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.25), value: previewLayout != nil)
        .onChange(of: style) { _, newStyle in
            onSave?(newStyle)
        }
        .task(id: style) {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            await renderShareImages(style: style)
        }
        .onAppear {
            // Normalize the draft without changing this archived work until the reader edits it.
            let initial = style
            selectedBgRaw = initial.background.rawValue
            selectedTypefaceRaw = initial.typeface.rawValue
            selectedScriptRaw = initial.script.rawValue
            usesVerticalText = initial.usesVerticalText
            sealName = initial.sealName
            selectedSealStyleRaw = initial.sealStyle.rawValue
            transliteration = initial.transliteration
            selectedShadowRaw = initial.shadow.rawValue
        }
        .onChange(of: section) { _, _ in
            sealNameFocused = false
            sealName = style.sealName
        }
        .onChange(of: store.isPremium) { _, isPremium in
            guard !isPremium else { return }
            let fallback = style
            selectedBgRaw = fallback.background.rawValue
            selectedTypefaceRaw = fallback.typeface.rawValue
            selectedSealStyleRaw = fallback.sealStyle.rawValue
        }
        .sheet(isPresented: $showsPaywall) {
            PaywallView { showsPaywall = false }
        }
        .sheet(isPresented: $showsPaperChoice, onDismiss: {
            if opensPaywallAfterChoice {
                opensPaywallAfterChoice = false
                showsPaywall = true
            }
        }) {
            SharePaperChoiceSheet(
                paper: style.background,
                onUnlock: {
                    opensPaywallAfterChoice = true
                    showsPaperChoice = false
                },
                onChooseFreePaper: {
                    showsPaperChoice = false
                }
            )
        }
        .spotlightOverlay(for: [.selectBackground, .tapShareButton, .returnFromShare])
    }

    /// Portrait and landscape sit side by side in a fixed pager sized to the
    /// space above the configuration panel, so the page itself never scrolls.
    private var layoutPager: some View {
        VStack(spacing: 12) {
            GeometryReader { geometry in
                TabView(selection: $pagedLayout) {
                    ForEach(availableLayouts) { layout in
                        SharePreviewCard(
                            layout: layout,
                            imageTitle: imageTitle,
                            lines: lines,
                            locationMark: locationMark,
                            lunarDateText: lunarDateText,
                            dayPeriodText: dayPeriodText,
                            style: style,
                            translation: translation,
                            maxSize: CGSize(
                                width: geometry.size.width - 88,
                                height: geometry.size.height - 16
                            ),
                            onTapPreview: {
                                sealNameFocused = false
                                previewLayout = layout
                            }
                        )
                        // Top-leading: vertical verse starts at the right edge.
                        .overlay(alignment: .topLeading) {
                            if requiresPremiumToShare {
                                MemberPaperTag().padding(8)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .tag(layout)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .overlay { pagerArrows }
            }

            if availableLayouts.count > 1 {
                layoutIndicator
                    .frame(minHeight: 34)
                    .padding(.horizontal, 30)
            }
        }
        .padding(.bottom, 14)
        .onAppear {
            if !availableLayouts.contains(pagedLayout), let first = availableLayouts.first {
                pagedLayout = first
            }
        }
    }

    /// The rendered image for the current layout, once it matches the style.
    private var readyShareItem: PreparedShareItem? {
        let item = preparedShareItems[pagedLayout]
        return item?.style == style ? item : nil
    }

    private var shareButton: some View {
        let readyItem = readyShareItem
        return ShareArtworkButton(
            shareItem: readyItem,
            isSpotlightTarget: spotlightGuide.step == .tapShareButton && pagedLayout == .portrait && readyItem != nil,
            requiresPremium: requiresPremiumToShare,
            requestPremium: {
                sealNameFocused = false
                showsPaperChoice = true
            }
        )
        .padding(.top, 4)
    }

    private var pagedIndex: Int {
        availableLayouts.firstIndex(of: pagedLayout) ?? 0
    }

    private func pageTo(offset: Int) {
        let target = pagedIndex + offset
        guard availableLayouts.indices.contains(target) else { return }
        sealNameFocused = false
        SensoryFeedback.lightTap()
        withAnimation(.easeInOut(duration: 0.3)) {
            pagedLayout = availableLayouts[target]
        }
    }

    /// Chevrons at the pager's edges hint that the other layout is a swipe away.
    private var pagerArrows: some View {
        HStack {
            pagerArrow(systemName: "chevron.left", isVisible: pagedIndex > 0) { pageTo(offset: -1) }
                .accessibilityLabel(AppLanguage.copy("上一版式", "Previous layout").poemScript(script))
            Spacer()
            pagerArrow(systemName: "chevron.right", isVisible: pagedIndex < availableLayouts.count - 1) { pageTo(offset: 1) }
                .accessibilityLabel(AppLanguage.copy("下一版式", "Next layout").poemScript(script))
        }
        .padding(.horizontal, 8)
        .animation(.easeOut(duration: 0.2), value: pagedLayout)
    }

    private func pagerArrow(systemName: String, isVisible: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.cinnabar)
                .frame(width: 28, height: 28)
                .background {
                    Circle()
                        .fill(Color.white.opacity(0.92))
                        .stroke(Color.cinnabar.opacity(0.35), lineWidth: 0.8)
                }
                .shadow(color: Color.black.opacity(0.10), radius: 3, x: 0, y: 1)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isVisible ? 1 : 0)
        .allowsHitTesting(isVisible)
        .accessibilityHidden(!isVisible)
    }

    private var layoutIndicator: some View {
        HStack(spacing: 14) {
            ForEach(availableLayouts) { layout in
                let isCurrent = layout == pagedLayout
                Button {
                    guard !isCurrent else { return }
                    pageTo(offset: (availableLayouts.firstIndex(of: layout) ?? 0) - pagedIndex)
                } label: {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(isCurrent ? Color.cinnabar : Color.mutedInk.opacity(0.3))
                            .frame(width: 5, height: 5)
                        Text(layout.label.poemScript(script))
                            .font(typeface.tinySealFont)
                            .foregroundStyle(isCurrent ? Color.ink : Color.mutedInk)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isCurrent ? .isSelected : [])
            }
        }
        .animation(.easeOut(duration: 0.2), value: pagedLayout)
    }

    private var configurationPanel: some View {
        VStack(spacing: 16) {
            Picker(AppLanguage.copy("作品配置", "Artwork options"), selection: $section) {
                ForEach(ShareConfigurationSection.allCases) { item in
                    Text(item.label.poemScript(script)).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 30)

            ScrollView {
                switch section {
                case .paper:
                    ArtworkPaperControls(selectedShadowRaw: $selectedShadowRaw, selectedBgRaw: $selectedBgRaw) {
                        showsPaywall = true
                    }
                case .text:
                    ArtworkTextControls(
                        selectedTypefaceRaw: $selectedTypefaceRaw,
                        selectedScriptRaw: $selectedScriptRaw,
                        usesVerticalText: $usesVerticalText,
                        showsLayoutPicker: false
                    ) { showsPaywall = true }
                    .padding(.horizontal, 30)
                case .seal:
                    ArtworkSealControls(
                        sealName: $sealName,
                        selectedSealStyleRaw: $selectedSealStyleRaw,
                        transliteration: $transliteration,
                        sealNameFocused: $sealNameFocused
                    ) { showsPaywall = true }
                    .padding(.horizontal, 30)
                }
            }
            .frame(height: section == .text ? 230 : 170)
            .scrollDismissesKeyboard(.interactively)
        }
        .padding(.top, 18)
        .padding(.bottom, 8)
        .background(Color(.systemBackground))
        .overlay(alignment: .top) {
            Rectangle().fill(Color.mutedInk.opacity(0.12)).frame(height: 0.5)
        }
    }

    @MainActor
    private func renderShareImages(style snapshot: ShareArtworkStyle) async {
        for layout in availableLayouts {
            guard !Task.isCancelled else { return }
            let size = layout.canvasSize
            let renderer = ImageRenderer(content: ConfiguredShareArtwork(
                layout: layout, imageTitle: imageTitle, lines: lines,
                locationMark: locationMark, lunarDateText: lunarDateText,
                dayPeriodText: dayPeriodText, style: snapshot,
                translation: translation
            ).frame(width: size.width, height: size.height))
            renderer.scale = 1
            guard let image = renderer.uiImage else { continue }
            let url = await Task.detached(priority: .userInitiated) {
                guard let data = image.jpegData(compressionQuality: 0.92) else { return nil as URL? }
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("poem-share-\(UUID().uuidString).jpg")
                do {
                    try data.write(to: url, options: .atomic)
                    return url
                } catch { return nil }
            }.value
            guard let url else { continue }
            guard !Task.isCancelled else {
                try? FileManager.default.removeItem(at: url)
                return
            }
            if let previous = preparedShareItems[layout] {
                try? FileManager.default.removeItem(at: previous.url)
            }
            preparedShareItems[layout] = PreparedShareItem(
                url: url, style: snapshot, controller: SharePresenter.makeController(url: url)
            )
        }
    }
}

private struct PreparedShareItem {
    let url: URL
    let style: ShareArtworkStyle
    let controller: UIActivityViewController
}

private struct ArtworkTextControls: View {
    @Environment(\.poemTypeface) private var typeface
    @Environment(\.poemScript) private var script
    @ObservedObject private var store = StoreManager.shared
    @Binding var selectedTypefaceRaw: String
    @Binding var selectedScriptRaw: String
    @Binding var usesVerticalText: Bool
    var showsLayoutPicker = true
    let requestPremium: () -> Void

    private var selectedTypeface: PoemTypeface {
        let selected = PoemTypeface(rawValue: selectedTypefaceRaw) ?? .kaiti
        return store.isPremium || selected.isFree ? selected : .kaiti
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if showsLayoutPicker {
                Picker(AppLanguage.copy("詩句排版", "Text layout"), selection: $usesVerticalText) {
                    Text(AppLanguage.copy("橫排", "Horizontal").poemScript(script)).tag(false)
                    Text(AppLanguage.copy("豎排", "Vertical").poemScript(script)).tag(true)
                }
                .pickerStyle(.segmented)
            }
            ScriptStylePicker(selectedRawValue: $selectedScriptRaw)
            Text(AppLanguage.copy("字體", "Typefaces").poemScript(script))
                .font(typeface.smallFont).foregroundStyle(Color.mutedInk)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 94), spacing: 12)], spacing: 12) {
                ForEach(PoemTypeface.allCases) { font in
                    Button {
                        guard store.isPremium || font.isFree else {
                            requestPremium()
                            return
                        }
                        selectedTypefaceRaw = font.rawValue
                    } label: {
                        HStack(spacing: 4) {
                            VStack(spacing: 3) {
                                Text(font.displayName.poemScript(script))
                                    .font(font.previewFont(size: 14))
                                if AppLanguage.isEnglish {
                                    Text(font.englishStyleName)
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(selectedTypeface == font ? Color.cinnabar.opacity(0.8) : Color.mutedInk)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            if !font.isFree { PremiumCrownBadge() }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(AppLanguage.isEnglish ? font.englishStyleName : font.displayName.poemScript(script))
                        .accessibilityValue(font.isFree ? "" : AppLanguage.copy("會員", "Premium"))
                        .foregroundStyle(selectedTypeface == font ? Color.cinnabar : Color.ink)
                        .padding(10)
                        .background {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(selectedTypeface == font ? Color.cinnabar : Color.mutedInk.opacity(0.25), lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selectedTypeface == font ? .isSelected : [])
                }
            }
        }
        .padding(.bottom, 12)
    }

}

private struct ArtworkSealControls: View {
    @Environment(\.poemTypeface) private var typeface
    @Environment(\.poemScript) private var script
    @ObservedObject private var store = StoreManager.shared
    @Binding var sealName: String
    @Binding var selectedSealStyleRaw: String
    @Binding var transliteration: String
    @FocusState.Binding var sealNameFocused: Bool
    let requestPremium: () -> Void

    private var normalizedSealName: String { ShareArtworkStyle.normalizedSealName(sealName) }
    private var selectedSealStyle: SealStampStyle {
        let selected = SealStampStyle(rawValue: selectedSealStyleRaw) ?? .zhuwen
        return store.isPremium || selected.isFree ? selected : .zhuwen
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 20) {
                TextField(AppLanguage.copy("姓名", "Name").poemScript(script), text: $sealName)
                    .font(typeface.bodyFont)
                    .foregroundStyle(Color.ink)
                    .focused($sealNameFocused)
                    .submitLabel(.done)
                    .onSubmit {
                        sealName = normalizedSealName
                        sealNameFocused = false
                    }
                    .padding(.vertical, 10)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Color.mutedInk.opacity(0.3)).frame(height: 0.5)
                    }
                if !normalizedSealName.isEmpty {
                    SealStampView(name: normalizedSealName, style: selectedSealStyle, size: 64, transliterationOverrideValue: transliteration)
                }
            }
            if !normalizedSealName.isEmpty {
                SealTransliterationChips(name: normalizedSealName, overrideBinding: $transliteration)
            }
            HStack(spacing: 14) {
                ForEach(SealStampStyle.allCases) { seal in
                    Button {
                        sealNameFocused = false
                        guard store.isPremium || seal.isFree else {
                            requestPremium()
                            return
                        }
                        selectedSealStyleRaw = seal.rawValue
                    } label: {
                        HStack(spacing: 8) {
                            Text(seal.displayName.poemScript(script)).font(typeface.smallFont)
                            if !seal.isFree { PremiumCrownBadge() }
                        }
                        .foregroundStyle(selectedSealStyle == seal ? Color.cinnabar : Color.mutedInk)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(selectedSealStyle == seal ? Color.cinnabar : Color.mutedInk.opacity(0.25), lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selectedSealStyle == seal ? .isSelected : [])
                }
            }
            Text(AppLanguage.copy("留空則不顯示朱印", "Leave blank to hide the seal").poemScript(script))
                .font(typeface.tinySealFont).foregroundStyle(Color.mutedInk)
        }
        .padding(.bottom, 12)
    }

}

/// Image papers and plain-paper effects share one configuration section.
private struct PaperScrollMetrics: Equatable {
    var offset: CGFloat = 0
    var contentWidth: CGFloat = 0
}

private struct PaperScrollMetricsKey: PreferenceKey {
    static var defaultValue = PaperScrollMetrics()
    static func reduce(value: inout PaperScrollMetrics, nextValue: () -> PaperScrollMetrics) {
        value = nextValue()
    }
}

private struct PaperScrollViewportKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct ArtworkPaperControls: View {
    @Environment(\.poemTypeface) private var typeface
    @Environment(\.poemScript) private var script
    @Environment(\.spotlightGuide) private var spotlightGuide
    @Binding var selectedShadowRaw: String
    @ObservedObject private var store = StoreManager.shared
    @Binding var selectedBgRaw: String
    var horizontalPadding: CGFloat = 30
    var participatesInGuide = true
    let requestPremium: () -> Void

    /// Named space must be unique per instance so simultaneous pickers
    /// (settings + share sheet) don't read each other's scroll offset.
    private let scrollSpace = UUID().uuidString
    @State private var scrollMetrics = PaperScrollMetrics()
    @State private var viewportWidth: CGFloat = 0

    private var hasPremiumAccess: Bool {
        store.isPremium
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(AppLanguage.copy("紙面", "Paper").poemScript(script))
                .font(typeface.smallFont)
                .foregroundStyle(Color.mutedInk)
                .padding(.horizontal, horizontalPadding)

            ZStack(alignment: .trailing) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
	                    // Background images
	                    ForEach(PoemBackground.imageBackgrounds) { bg in
                        let isSpotlightTarget = participatesInGuide && spotlightGuide.step == .selectBackground && bg == PoemBackground.freeImageBackgrounds.first
                        let isActive = selectedBgRaw == bg.rawValue
                        Button {
                            guard SeasonalAppearance.hasAccess(to: bg, isPremium: hasPremiumAccess) else {
                                requestPremium()
                                return
                            }
                            withAnimation(.easeOut(duration: 0.25)) {
                                selectedBgRaw = bg.rawValue
                            }
                            SensoryFeedback.lightTap()
                            if isSpotlightTarget {
                                spotlightGuide.advance()
                            }
                        } label: {
                            VStack(spacing: 8) {
                                ZStack(alignment: .bottomTrailing) {
	                                    if let imageName = bg.imageName {
	                                        Image(imageName)
	                                            .resizable()
	                                            .scaledToFill()
	                                            .frame(width: 52, height: 72)
	                                            .clipShape(RoundedRectangle(cornerRadius: 6))
                                                .spotlightTarget(.selectBackground, active: isSpotlightTarget)
	                                    }

                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(
                                            isActive ? Color.cinnabar : Color.mutedInk.opacity(0.3),
                                            lineWidth: isActive ? 1.5 : 0.8
                                        )
                                        .frame(width: 52, height: 72)

                                    if SeasonalAppearance.isSeasonallyFree(bg) {
                                        SeasonalFreeBadge()
                                            .offset(x: 5, y: 5)
                                    } else if bg.isPremium {
                                        PremiumCrownBadge()
                                            .offset(x: 5, y: 5)
                                    }
                                }
                                Text(bg.displayName.poemScript(script))
                                    .font(typeface.tinySealFont)
                                    .foregroundStyle(isActive ? Color.ink : Color.mutedInk)
                            }
                        }
	                        .buttonStyle(.plain)
	                        .accessibilityAddTraits(isActive ? .isSelected : [])
	                    }

                        Rectangle()
                            .fill(Color.mutedInk.opacity(0.2))
                            .frame(width: 0.5, height: 60)

                        plainPaperButton

                        ForEach(ShadowStyle.visibleCases) { style in
                            shadowStyleButton(style)
                        }
                    }
                    .padding(.horizontal, horizontalPadding)
                    .padding(.vertical, 2)
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: PaperScrollMetricsKey.self,
                                value: PaperScrollMetrics(
                                    offset: -proxy.frame(in: .named(scrollSpace)).minX,
                                    contentWidth: proxy.size.width
                                )
                            )
                        }
                    }
                }

                if showsMorePapersHint {
                    morePapersHint
                        .transition(.opacity)
                }
            }
            .coordinateSpace(name: scrollSpace)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: PaperScrollViewportKey.self,
                        value: proxy.frame(in: .named(scrollSpace)).width
                    )
                }
            }
            .onPreferenceChange(PaperScrollMetricsKey.self) { scrollMetrics = $0 }
            .onPreferenceChange(PaperScrollViewportKey.self) { viewportWidth = $0 }
            .animation(.easeInOut(duration: 0.25), value: showsMorePapersHint)
        }
    }

    /// True while the row overflows and the trailing end is still off-screen.
    private var showsMorePapersHint: Bool {
        guard viewportWidth > 0 else { return true }
        return scrollMetrics.contentWidth > viewportWidth + 4
            && scrollMetrics.offset < scrollMetrics.contentWidth - viewportWidth - 4
    }

    /// A floating chevron at the trailing edge signalling that more papers
    /// hide to the left; it fades away once the end of the row is reached.
    private var morePapersHint: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(Color.cinnabar)
            .frame(width: 20, height: 20)
            .background {
                Circle()
                    .fill(Color.white.opacity(0.92))
                    .stroke(Color.cinnabar.opacity(0.35), lineWidth: 0.8)
            }
            .shadow(color: Color.black.opacity(0.12), radius: 3, x: 0, y: 1)
            .padding(.trailing, 2)
            .accessibilityHidden(true)
    }

    private var isShadowSelected: Bool {
        let background = PoemBackground(rawValue: selectedBgRaw)
        return background == PoemBackground.none || background == nil
    }

    private var plainPaperButton: some View {
        Button {
            withAnimation(.easeOut(duration: 0.25)) {
                selectedBgRaw = PoemBackground.none.rawValue
                selectedShadowRaw = ShadowStyle.none.rawValue
            }
            SensoryFeedback.lightTap()
        } label: {
            paperTileLabel(
                isActive: isShadowSelected && selectedShadowRaw == ShadowStyle.none.rawValue,
                name: AppLanguage.copy("素紙", "Plain paper")
            ) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isShadowSelected && selectedShadowRaw == ShadowStyle.none.rawValue ? .isSelected : [])
    }

    private func shadowStyleButton(_ style: ShadowStyle) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.25)) {
                selectedShadowRaw = style.rawValue
                selectedBgRaw = PoemBackground.none.rawValue
            }
            SensoryFeedback.lightTap()
        } label: {
            paperTileLabel(
                isActive: isShadowSelected && selectedShadowRaw == style.rawValue,
                name: style.displayName
            ) {
                ShadowPreviewTile(style: style)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isShadowSelected && selectedShadowRaw == style.rawValue ? .isSelected : [])
    }

    private func paperTileLabel(
        isActive: Bool,
        name: String,
        @ViewBuilder tile: () -> some View
    ) -> some View {
        VStack(spacing: 8) {
            tile()
                .frame(width: 52, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(
                            isActive ? Color.cinnabar : Color.mutedInk.opacity(0.3),
                            lineWidth: isActive ? 1.5 : 0.8
                        )
                )
            Text(name.poemScript(script))
                .font(typeface.tinySealFont)
                .foregroundStyle(isActive ? Color.ink : Color.mutedInk)
        }
    }
}

/// Marks a share preview whose paper needs membership, so the lock reads as
/// belonging to the paper rather than to sharing itself.
private struct MemberPaperTag: View {
    @Environment(\.poemTypeface) private var typeface
    @Environment(\.poemScript) private var script

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "crown.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color.premiumGold)
            Text(AppLanguage.copy("會員紙張", "Member paper").poemScript(script))
                .font(typeface.tinySealFont)
                .foregroundStyle(Color.ink)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background {
            Capsule()
                .fill(Color.white.opacity(0.9))
                .stroke(Color.premiumGold.opacity(0.5), lineWidth: 0.7)
        }
        .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
        .allowsHitTesting(false)
    }
}

/// Shown when a free reader shares on a member paper: unlock every paper, or
/// return to the picker to choose a free one. Sharing itself is never locked.
private struct SharePaperChoiceSheet: View {
    @Environment(\.poemTypeface) private var typeface
    @Environment(\.poemScript) private var script
    let paper: PoemBackground
    let onUnlock: () -> Void
    let onChooseFreePaper: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 8) {
                Text(AppLanguage.copy(
                    "「\(paper.displayName)」是會員紙張",
                    "\u{201C}\(paper.displayName)\u{201D} is a member paper"
                ).poemScript(script))
                    .font(typeface.titleFont)
                    .foregroundStyle(Color.ink)
                    .multilineTextAlignment(.center)
                Text(AppLanguage.copy(
                    "成為會員即可用全部紙張分享；也可以選擇免費紙張後分享。",
                    "Members can share on every paper. Or choose a free paper before sharing."
                ).poemScript(script))
                    .font(typeface.smallFont)
                    .foregroundStyle(Color.mutedInk)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 10) {
                Button(action: onUnlock) {
                    HStack(spacing: 6) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 12, weight: .bold))
                        Text(AppLanguage.copy("解鎖全部紙張", "Unlock all papers").poemScript(script))
                            .font(typeface.smallFont)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Capsule().fill(Color.cinnabar))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)

                Button(action: onChooseFreePaper) {
                    Text(AppLanguage.copy(
                        "選擇免費紙張",
                        "Choose a free paper"
                    ).poemScript(script))
                        .font(typeface.smallFont)
                        .foregroundStyle(Color.ink)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Capsule().stroke(Color.mutedInk.opacity(0.35), lineWidth: 0.8))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 30)
        .padding(.top, 28)
        .padding(.bottom, 16)
        .presentationDetents([.height(300)])
        .presentationDragIndicator(.visible)
    }
}

struct PremiumCrownBadge: View {
    var body: some View {
        Image(systemName: "crown.fill")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(Color.premiumGold)
            .frame(width: 18, height: 18)
            .background {
                Circle()
                    .fill(Color.white.opacity(0.88))
                    .stroke(Color.premiumGold.opacity(0.58), lineWidth: 0.7)
            }
            .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
    }
}

private struct SeasonalFreeBadge: View {
    var body: some View {
        Text(AppLanguage.copy("限免", "FREE"))
            .font(.system(size: 8, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .frame(height: 18)
            .background(Color.cinnabar.opacity(0.92), in: Capsule())
    }
}

private struct MembershipIndicator: View {
    @Environment(\.poemTypeface) private var typeface
    @Environment(\.poemScript) private var script

    var body: some View {
        Group {
            if AppLanguage.isEnglish {
                Image(systemName: "crown.fill")
                    .font(.system(size: 13, weight: .semibold))
            } else {
                Text("雅".poemScript(script))
                    .font(typeface.sealFont)
            }
        }
    }
}

private struct SelectionIndicator: View {
    @Environment(\.poemTypeface) private var typeface
    @Environment(\.poemScript) private var script
    var isSelected = true
    var size: CGFloat = 18

    var body: some View {
        Group {
            if isSelected {
                if AppLanguage.isEnglish {
                    Image(systemName: "checkmark")
                        .font(.system(size: max(8, size * 0.48), weight: .bold))
                } else {
                    Text("擇".poemScript(script))
                        .font(typeface.tinySealFont)
                }
            }
        }
        .foregroundStyle(.white)
        .frame(width: size, height: size)
        .background(Circle().fill(isSelected ? Color.cinnabar : Color.clear))
    }
}

private struct SharePreviewCard: View {
    @Environment(\.poemScript) private var script
    let layout: ShareArtworkLayout
    let imageTitle: String
    let lines: [String]
    let locationMark: String?
    let lunarDateText: String
    let dayPeriodText: String
    let style: ShareArtworkStyle
    var translation: ShareTranslation? = nil
    /// Size the artwork may occupy; it fits inside while keeping its ratio.
    let maxSize: CGSize
    var onTapPreview: (() -> Void)?

    var body: some View {
        let canvasSize = layout.canvasSize
        let width = max(min(maxSize.width, maxSize.height * layout.aspectRatio), 1)
        let scale = width / canvasSize.width

        Button {
            onTapPreview?()
        } label: {
            ConfiguredShareArtwork(
                layout: layout,
                imageTitle: imageTitle,
                lines: lines,
                locationMark: locationMark,
                lunarDateText: lunarDateText,
                dayPeriodText: dayPeriodText,
                style: style,
                translation: translation
            )
            .frame(width: canvasSize.width, height: canvasSize.height)
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: width, height: width / layout.aspectRatio, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AppLanguage.copy("放大預覽", "Enlarge preview").poemScript(script))
    }
}

/// The 享 seal that opens the system share sheet once the JPEG is rendered.
private struct ShareArtworkButton: View {
    @Environment(\.poemTypeface) private var typeface
    @Environment(\.poemScript) private var script
    @Environment(\.spotlightGuide) private var spotlightGuide
    let shareItem: PreparedShareItem?
    var isSpotlightTarget = false
    var requiresPremium = false
    var requestPremium: () -> Void = {}

    var body: some View {
        if let shareItem {
            Button {
                guard !requiresPremium else {
                    requestPremium()
                    return
                }
                if isSpotlightTarget {
                    spotlightGuide.advance()
                }
                SharePresenter.present(controller: shareItem.controller)
            } label: {
                Group {
                    if AppLanguage.isEnglish {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 13, weight: .semibold))
                    } else {
                        Text("享".poemScript(script))
                            .font(typeface.sealFont)
                    }
                }
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.cinnabar))
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .spotlightTarget(.tapShareButton, active: isSpotlightTarget)
            .accessibilityLabel(AppLanguage.copy("分享", "Share"))
        } else {
            Group {
                if AppLanguage.isEnglish {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                } else {
                    Text("備".poemScript(script))
                        .font(typeface.sealFont)
                }
            }
            .foregroundStyle(.white)
            .frame(width: 34, height: 34)
            .background(Circle().fill(Color.mutedInk.opacity(0.35)))
        }
    }
}

private enum SharePresenter {
    static func makeController(url: URL) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    static func present(url: URL, completion: ((Bool) -> Void)? = nil) {
        present(controller: makeController(url: url), completion: completion)
    }

    static func present(controller: UIActivityViewController, completion: ((Bool) -> Void)? = nil) {
        let presentBlock = {
            controller.completionWithItemsHandler = { _, completed, _, _ in
                completion?(completed)
            }
            guard let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
                  let root = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
                completion?(false)
                return
            }

            let presenter = topViewController(from: root)
            if let popover = controller.popoverPresentationController {
                popover.sourceView = presenter.view
                popover.sourceRect = CGRect(
                    x: presenter.view.bounds.midX,
                    y: presenter.view.bounds.midY,
                    width: 1,
                    height: 1
                )
            }
            presenter.present(controller, animated: true)
        }

        if Thread.isMainThread {
            presentBlock()
        } else {
            DispatchQueue.main.async(execute: presentBlock)
        }
    }

    private static func topViewController(from controller: UIViewController) -> UIViewController {
        if let presented = controller.presentedViewController {
            return topViewController(from: presented)
        }
        if let navigation = controller as? UINavigationController,
           let visible = navigation.visibleViewController {
            return topViewController(from: visible)
        }
        if let tab = controller as? UITabBarController,
           let selected = tab.selectedViewController {
            return topViewController(from: selected)
        }
        return controller
    }
}

private struct ShareFullscreenPreview: View {
    @Environment(\.poemTypeface) private var typeface
    @Environment(\.poemScript) private var script
    let layout: ShareArtworkLayout
    let imageTitle: String
    let lines: [String]
    let locationMark: String?
    let lunarDateText: String
    let dayPeriodText: String
    let style: ShareArtworkStyle
    var translation: ShareTranslation? = nil
    let onDismiss: () -> Void

    var body: some View {
        GeometryReader { geo in
            let canvasSize = layout.canvasSize
            let scaleW = (geo.size.width - 32) / canvasSize.width
            let scaleH = (geo.size.height - 100) / canvasSize.height
            let scale = min(scaleW, scaleH)

            ZStack {
                Color.black.opacity(0.85)
                    .ignoresSafeArea()
                    .onTapGesture { onDismiss() }

                VStack(spacing: 20) {
                    ConfiguredShareArtwork(
                        layout: layout,
                        imageTitle: imageTitle,
                        lines: lines,
                        locationMark: locationMark,
                        lunarDateText: lunarDateText,
                        dayPeriodText: dayPeriodText,
                        style: style,
                        translation: translation
                    )
                    .frame(width: canvasSize.width, height: canvasSize.height)
                    .scaleEffect(scale)
                    .frame(width: canvasSize.width * scale, height: canvasSize.height * scale)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
            }
        }
    }
}

/// Shared verse-splitting for poem display and share artwork.
///
/// Short-sentence poems read best with one clause per row, but a clause that
/// is a touch too wide wraps and strands a few characters on a second row.
/// Callers split only when every resulting clause fits the available width.
enum PoemVerseSplitter {
    private static let sentenceEndings: Set<Character> = ["，", "。", "！", "？", "；", "：", ",", ".", "!", "?", ";", ":"]

    /// Split one verse into punctuation-terminated clauses.
    static func split(_ line: String) -> [String] {
        var lines: [String] = []
        var current = ""
        for character in line {
            current.append(character)
            if sentenceEndings.contains(character) {
                lines.append(current)
                current = ""
            }
        }
        if !current.isEmpty {
            lines.append(current)
        }
        return lines.isEmpty ? [line] : lines
    }

    static func fitsOnOneLine(_ text: String, typeface: PoemTypeface, fontSize: CGFloat, maxWidth: CGFloat) -> Bool {
        let uiFont: UIFont
        if let name = typeface.resolvedFontName, let font = UIFont(name: name, size: fontSize) {
            uiFont = font
        } else {
            uiFont = UIFont.systemFont(ofSize: fontSize)
        }
        let size = (text as NSString).size(withAttributes: [.font: uiFont])
        return size.width <= maxWidth
    }
}

/// Traditional composition shared by the live poem and its share artwork.
/// The colophon follows the last column of verse, never starting above the
/// verse's first character, and the seal is pressed right beneath it.
struct VerticalPoemComposition<Inscription: View, Seal: View, Verses: View, Title: View>: View {
    var columnSpacing: CGFloat
    var minimumGap: CGFloat
    @ViewBuilder let inscription: () -> Inscription
    @ViewBuilder let seal: () -> Seal
    @ViewBuilder let verses: () -> Verses
    @ViewBuilder let title: () -> Title

    var body: some View {
        VerticalPoemLayout(
            minimumGap: minimumGap,
            // Roughly one verse character: the colophon sits a character lower.
            inscriptionIndent: columnSpacing * 1.5,
            sealGap: columnSpacing * 0.45
        ) {
            inscription()
                .layoutValue(key: VerticalPoemRole.self, value: .inscription)
            seal()
                .layoutValue(key: VerticalPoemRole.self, value: .seal)
            HStack(alignment: .top, spacing: columnSpacing) {
                verses()
                title()
            }
            .layoutValue(key: VerticalPoemRole.self, value: .verses)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

extension VerticalPoemComposition where Seal == EmptyView {
    init(
        columnSpacing: CGFloat,
        minimumGap: CGFloat,
        @ViewBuilder inscription: @escaping () -> Inscription,
        @ViewBuilder verses: @escaping () -> Verses,
        @ViewBuilder title: @escaping () -> Title
    ) {
        self.init(
            columnSpacing: columnSpacing,
            minimumGap: minimumGap,
            inscription: inscription,
            seal: { EmptyView() },
            verses: verses,
            title: title
        )
    }
}

private enum VerticalPoemRole: LayoutValueKey {
    enum Role { case inscription, seal, verses }
    static let defaultValue = Role.verses
}

/// Verses at the top right; the colophon and seal at the left, centred down a
/// full sheet (never above the first verse character). Without a fixed
/// height, as in a scroll view, the colophon ends level with the verse.
private struct VerticalPoemLayout: Layout {
    var minimumGap: CGFloat
    var inscriptionIndent: CGFloat
    var sealGap: CGFloat

    private struct Frames {
        var size: CGSize
        var inscription: CGPoint
        var seal: CGPoint
        var verses: CGPoint
    }

    private func frames(proposal: ProposedViewSize, subviews: Subviews) -> Frames {
        func size(of role: VerticalPoemRole.Role) -> CGSize {
            subviews.first { $0[VerticalPoemRole.self] == role }?.sizeThatFits(.unspecified) ?? .zero
        }
        let verses = size(of: .verses)
        let inscription = size(of: .inscription)
        let seal = size(of: .seal)

        let gap = inscription.height > 0 && seal.height > 0 ? sealGap : 0
        let groupHeight = inscription.height + gap + seal.height
        let inscriptionTop: CGFloat
        if let available = proposal.height, available.isFinite, available > 0 {
            // On a full sheet the colophon and seal rest at its vertical middle.
            inscriptionTop = max(inscriptionIndent, (available - groupHeight) / 2)
        } else {
            inscriptionTop = inscription.height == 0 ? 0 : max(inscriptionIndent, verses.height - inscription.height)
        }
        let sealTop = inscriptionTop + inscription.height + gap
        let width = proposal.width ?? (max(inscription.width, seal.width) + minimumGap + verses.width)
        let contentHeight = max(verses.height, inscriptionTop + groupHeight)
        let height = max(contentHeight, proposal.height.flatMap { $0.isFinite ? $0 : nil } ?? 0)
        return Frames(
            size: CGSize(width: width, height: height),
            inscription: CGPoint(x: 0, y: inscriptionTop),
            seal: CGPoint(x: 0, y: sealTop),
            verses: CGPoint(x: width - verses.width, y: 0)
        )
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        frames(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = frames(proposal: ProposedViewSize(bounds.size), subviews: subviews)
        for subview in subviews {
            let origin: CGPoint = switch subview[VerticalPoemRole.self] {
            case .inscription: frames.inscription
            case .seal: frames.seal
            case .verses: frames.verses
            }
            subview.place(
                at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                proposal: .unspecified
            )
        }
    }
}

struct SharePoemArtwork: View {
    @AppStorage(PoemTextLayout.storageKey) private var storedUsesVerticalText = false
    @Environment(\.poemTypeface) private var typeface
    @Environment(\.poemScript) private var script
    let layout: ShareArtworkLayout
    let imageTitle: String
    let lines: [String]
    let locationMark: String?
    let lunarDateText: String
    let dayPeriodText: String
    let sealName: String
    let showsLight: Bool
    let showsSeal: Bool
    let showsTitle: Bool
    var background: PoemBackground = .none
    /// Archive thumbnails retain the text direction that was chosen at creation.
    var usesVerticalTextOverride: Bool? = nil
    var sealStyleOverride: SealStampStyle? = nil
    var sealTransliterationOverride: String? = nil
    var shadowStyleOverride: ShadowStyle? = nil
    /// English edition only: the reading printed with the Chinese artwork.
    var translation: ShareTranslation? = nil
    /// Room kept clear for on-screen chrome when the artwork fills the screen.
    var extraTopPadding: CGFloat = 0
    var extraBottomPadding: CGFloat = 0

    private var usesVerticalText: Bool {
        usesVerticalTextOverride ?? storedUsesVerticalText
    }

    var body: some View {
        ZStack {
            Color.white

            if let imageName = layout == .landscape ? background.landscapeImageName : background.imageName {
                GeometryReader { geo in
                    Image(imageName)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                }
            } else if showsLight {
                DappledShadowView(styleOverride: shadowStyleOverride)
                    .opacity(0.64)
            }

            if let translation {
                switch layout {
                case .portrait: bilingualPortraitBody(translation)
                case .landscape: bilingualLandscapeBody(translation)
                }
            } else if usesVerticalText {
                verticalBody
            } else {
                switch layout {
                case .portrait: portraitBody
                case .landscape: landscapeBody
                }
            }
        }
    }

    private var verticalBody: some View {
        GeometryReader { geometry in
            let horizontalPadding: CGFloat = layout == .portrait ? 90 : 110
            let verticalPadding: CGFloat = layout == .portrait ? 160 : 130
            verticalComposition(
                width: geometry.size.width - horizontalPadding * 2,
                height: geometry.size.height - verticalPadding * 2 - extraTopPadding - extraBottomPadding,
                minimumVerseSize: Self.minimumVerseSize
            )
            .padding(.horizontal, horizontalPadding)
            .padding(.top, verticalPadding + extraTopPadding)
            .padding(.bottom, verticalPadding + extraBottomPadding)
        }
    }

    /// Verse columns, title, colophon and seal fitted to `width` × `height`.
    private func verticalComposition(width: CGFloat, height: CGFloat, minimumVerseSize: CGFloat) -> some View {
        let fit = verticalLayout(width: width, height: height, minimumVerseSize: minimumVerseSize)
        return VerticalPoemComposition(columnSpacing: fit.columnSpacing, minimumGap: Self.inscriptionGap) {
            HStack(alignment: .top, spacing: 14) {
                ArtworkColumnText(text: lunarDateText, fontSize: 28, color: .mutedInk, spacing: 10)
                if let locationMark {
                    ArtworkColumnText(text: inscriptionText(locationMark, isExcerpt: fit.isExcerpt), fontSize: 28, color: .mutedInk, spacing: 10)
                }
            }
        } seal: {
            if showsSeal && !sealName.isEmpty {
                SealStampView(name: sealName, style: sealStyleOverride, size: Self.sealSize, transliterationOverrideValue: sealTransliterationOverride)
            }
        } verses: {
            // Traditional Chinese verse is read top-to-bottom, beginning
            // with the rightmost column and continuing toward the left.
            ForEach(Array(fit.columns.indices.reversed()), id: \.self) { index in
                VerticalText(fit.columns[index], font: typeface.font(size: fit.fontSize), spacing: fit.characterSpacing)
            }
        } title: {
            if showsTitle {
                // The title is the rightmost, first-read column.
                ArtworkColumnText(text: imageTitle, fontSize: fit.titleFontSize, color: .mutedInk, spacing: fit.titleFontSize * 0.36)
            }
        }
    }

    /// "錄李白詩" becomes "節錄李白詩" when only the opening verses are shown.
    private func inscriptionText(_ mark: String, isExcerpt: Bool) -> String {
        let text = compactInscriptionText(mark)
        return isExcerpt && text.hasPrefix("錄") ? "節" + text : text
    }

    private static let inscriptionGap: CGFloat = 40
    /// Below this canvas size verse becomes hard to read on a phone.
    private static let minimumVerseSize: CGFloat = 32
    private static let sealSize: CGFloat = 104
    private static let clausePunctuation = CharacterSet(charactersIn: "，。！？；：、,.!?;:")
    /// A full-width space leaves one quiet cell between clauses sharing a column.
    private static let clauseGap = "\u{3000}"

    /// Columns and metrics sized so the whole poem stays on one sheet.
    private struct VerticalLayout {
        let columns: [String]
        let fontSize: CGFloat
        let characterSpacing: CGFloat
        let columnSpacing: CGFloat
        let titleFontSize: CGFloat
        var isExcerpt = false
    }

    /// Always vertical, never scrolling. Prefer one clause per column; when
    /// that would crowd the sheet, give each verse (comma plus full stop) its
    /// own column; a very long poem is excerpted from its opening verses.
    private func verticalLayout(width: CGFloat, height: CGFloat, minimumVerseSize: CGFloat) -> VerticalLayout {
        let verses = lines.map { line in
            line.components(separatedBy: Self.clausePunctuation)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        .filter { !$0.isEmpty }
        let clauses = verses.flatMap { $0 }
        guard !clauses.isEmpty else {
            return VerticalLayout(columns: [], fontSize: 58, characterSpacing: 19, columnSpacing: 54, titleFontSize: 44)
        }

        let fontName = typeface.resolvedFontName
        let referenceFont = fontName.flatMap { UIFont(name: $0, size: 100) } ?? UIFont.systemFont(ofSize: 100)
        let lineHeightRatio = referenceFont.lineHeight / 100
        let titleLength = showsTitle ? imageTitle.count : 0
        let titleIsLatin = !imageTitle.containsCJK
        let latinTitleWidth = (imageTitle as NSString).size(withAttributes: [.font: referenceFont]).width
        let inscriptionWidth: CGFloat = max(showsSeal && !sealName.isEmpty ? Self.sealSize : 0, locationMark == nil ? 28 : 70)

        // The largest verse size (up to the familiar sizes for short poems)
        // at which these columns fit both across and down the sheet.
        func layout(for columns: [String]) -> VerticalLayout {
            let few = columns.count <= 4
            let maximum: CGFloat = few ? 58 : 42
            let spacingRatio: CGFloat = few ? 19.0 / 58 : 15.0 / 42
            let columnRatio: CGFloat = few ? 54.0 / 58 : 34.0 / 42
            let longest = CGFloat(columns.map(\.count).max() ?? 1)
            var size = maximum
            while size > 8 {
                let titleSize = min(44, size)
                let titleWidth = showsTitle ? titleSize + size * columnRatio : 0
                let across = CGFloat(columns.count) * size + CGFloat(columns.count - 1) * size * columnRatio
                    + titleWidth + Self.inscriptionGap + inscriptionWidth
                let down = longest * size * lineHeightRatio + (longest - 1) * size * spacingRatio
                if across <= width && down <= height { break }
                size -= 1
            }
            // A long title shrinks on its own rather than pulling the verse down.
            var titleSize = min(44, size)
            let titleCount = CGFloat(titleLength)
            func titleExtent(at size: CGFloat) -> CGFloat {
                if titleIsLatin { return latinTitleWidth * size / 100 }
                return titleCount * size * lineHeightRatio + (titleCount - 1) * size * 0.36
            }
            while titleCount > 0 && titleSize > 8 && titleExtent(at: titleSize) > height {
                titleSize -= 1
            }
            return VerticalLayout(
                columns: columns,
                fontSize: size,
                characterSpacing: size * spacingRatio,
                columnSpacing: size * columnRatio,
                titleFontSize: titleSize
            )
        }

        let byClause = layout(for: clauses)
        if byClause.fontSize >= 40 { return byClause }

        let verseColumns = verses.map { $0.joined(separator: Self.clauseGap) }
        let byVerse = layout(for: verseColumns)
        if byVerse.fontSize >= minimumVerseSize || verseColumns.count == 1 { return byVerse }

        // Too long to read on one sheet: keep the opening verses that still
        // fit at a legible size, and mark the colophon as an excerpt.
        var count = verseColumns.count - 1
        while count > 1 && layout(for: Array(verseColumns.prefix(count))).fontSize < minimumVerseSize {
            count -= 1
        }
        var excerpt = layout(for: Array(verseColumns.prefix(count)))
        excerpt.isExcerpt = true
        return excerpt
    }

    /// Rows and metrics for a horizontal layout, computed adaptively: a verse
    /// that fits stays whole on one row; an over-wide verse is broken into
    /// clause rows only when every clause fits — otherwise it stays whole and
    /// wraps evenly instead of dangling a few characters on a second row.
    private struct HorizontalLayout {
        let lines: [String]
        let fontSize: CGFloat
        let rowSpacing: CGFloat
    }

    private func horizontalLayout(for layout: ShareArtworkLayout) -> HorizontalLayout {
        let isPortrait = layout == .portrait
        let horizontalPadding: CGFloat = isPortrait ? 110 : 120
        let usableWidth = layout.canvasSize.width - horizontalPadding * 2 - 4
        // Size from the fully split clause count so the font choice stays
        // stable no matter how many verses later remain whole.
        let manyRows = lines.flatMap(PoemVerseSplitter.split).count > 4
        let fontSize: CGFloat = isPortrait ? (manyRows ? 56 : 72) : (manyRows ? 48 : 66)
        let rowSpacing: CGFloat = isPortrait ? (manyRows ? 34 : 52) : (manyRows ? 17 : 42)

        let displayLines = lines.flatMap { line -> [String] in
            let fits: (String) -> Bool = { PoemVerseSplitter.fitsOnOneLine($0.poemScript(script), typeface: typeface, fontSize: fontSize, maxWidth: usableWidth) }
            if fits(line) { return [line] }

            let segments = PoemVerseSplitter.split(line)
            let allFit = segments.count > 1 && segments.allSatisfy(fits)
            return allFit ? segments : [line]
        }
        return HorizontalLayout(lines: displayLines, fontSize: fontSize, rowSpacing: rowSpacing)
    }

    private var portraitBody: some View {
        let config = horizontalLayout(for: .portrait)
        return VStack(alignment: .leading, spacing: config.rowSpacing) {
            if showsTitle {
                Text(imageTitle.poemScript(script))
                    .font(typeface.font(size: 68))
                    .foregroundStyle(Color.mutedInk)
                    .padding(.bottom, 28)
            }
            ForEach(Array(config.lines.enumerated()), id: \.offset) { _, line in
                Text(line.poemScript(script))
                    .font(typeface.font(size: config.fontSize))
                    .foregroundStyle(Color.ink)
            }
            Spacer(minLength: 0)
            HStack(alignment: .bottom) {
                inscription
                Spacer()
                if showsSeal && !sealName.isEmpty {
                    SealStampView(name: sealName, style: sealStyleOverride, size: 118, transliterationOverrideValue: sealTransliterationOverride)
                }
            }
        }
        .padding(.horizontal, 110)
        .padding(.top, 165)
        .padding(.bottom, 125)
    }

    private var landscapeBody: some View {
        let config = horizontalLayout(for: .landscape)
        return VStack(alignment: .leading, spacing: config.rowSpacing) {
            if showsTitle {
                Text(imageTitle.poemScript(script))
                    .font(typeface.font(size: 62))
                    .foregroundStyle(Color.mutedInk)
                    .padding(.bottom, 14)
            }
            ForEach(Array(config.lines.enumerated()), id: \.offset) { _, line in
                Text(line.poemScript(script))
                    .font(typeface.font(size: config.fontSize))
                    .foregroundStyle(Color.ink)
            }
            HStack(alignment: .bottom, spacing: 44) {
                inscription
                if showsSeal && !sealName.isEmpty {
                    SealStampView(name: sealName, style: sealStyleOverride, size: 104, transliterationOverrideValue: sealTransliterationOverride)
                }
            }
        }
        .fixedSize(horizontal: true, vertical: true)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.horizontal, 120)
        .padding(.top, 108)
        .padding(.bottom, 85)
    }

    // MARK: English edition — Chinese artwork with the English reading

    /// Chinese verse on top, the English reading below — the pairing the
    /// onboarding page introduces. The reading takes at most ~45% of the sheet.
    private func bilingualPortraitBody(_ translation: ShareTranslation) -> some View {
        GeometryReader { geometry in
            let horizontalPadding: CGFloat = 100
            let topPadding = 130 + extraTopPadding
            let bottomPadding = 110 + extraBottomPadding
            let width = geometry.size.width - horizontalPadding * 2
            let height = geometry.size.height - topPadding - bottomPadding
            let gap: CGFloat = 64
            let reading = Self.readingMetrics(translation, width: width, maxHeight: height * 0.45, sizes: 22...30)
            let poemHeight = max(height - reading.height - gap, 1)

            VStack(alignment: .leading, spacing: gap) {
                bilingualPoem(width: width, height: poemHeight)
                    .frame(width: width, height: poemHeight, alignment: .top)
                ShareReadingBlock(translation: translation, metrics: reading)
                    .frame(width: width, alignment: .leading)
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.top, topPadding)
            .padding(.bottom, bottomPadding)
        }
    }

    /// Chinese verse on the left, the English reading beside it.
    private func bilingualLandscapeBody(_ translation: ShareTranslation) -> some View {
        GeometryReader { geometry in
            let horizontalPadding: CGFloat = 110
            let topPadding = 100 + extraTopPadding
            let bottomPadding = 90 + extraBottomPadding
            let width = geometry.size.width - horizontalPadding * 2
            let height = geometry.size.height - topPadding - bottomPadding
            let gap: CGFloat = 80
            let readingWidth = (width - gap) * 0.42
            let poemWidth = width - gap - readingWidth
            let reading = Self.readingMetrics(translation, width: readingWidth, maxHeight: height, sizes: 20...28)

            HStack(alignment: .center, spacing: gap) {
                bilingualPoem(width: poemWidth, height: height)
                    .frame(width: poemWidth, height: height, alignment: .top)
                ShareReadingBlock(translation: translation, metrics: reading)
                    .frame(width: readingWidth, alignment: .leading)
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.top, topPadding)
            .padding(.bottom, bottomPadding)
        }
    }

    /// With the English reading alongside, the verse may run smaller before
    /// it is excerpted: the reading, not the calligraphy, carries the words.
    private static let bilingualMinimumVerseSize: CGFloat = 26

    @ViewBuilder
    private func bilingualPoem(width: CGFloat, height: CGFloat) -> some View {
        if usesVerticalText {
            verticalComposition(width: width, height: height, minimumVerseSize: Self.bilingualMinimumVerseSize)
        } else {
            horizontalPoem(width: width, height: height)
        }
    }

    private struct HorizontalFit {
        let rows: [String]
        let fontSize: CGFloat
        var isExcerpt = false
        var rowSpacing: CGFloat { fontSize * 0.55 }
        var titleSize: CGFloat { fontSize * 0.8 }
    }

    /// Horizontal verse sized to a bounded region: one clause per row while
    /// that stays large, otherwise whole verses, excerpted when still too long.
    private func horizontalFit(width: CGFloat, height: CGFloat) -> HorizontalFit {
        let footerHeight: CGFloat = 130
        let available = height - footerHeight
        func size(for rows: [String]) -> CGFloat {
            let longest = CGFloat(rows.map(\.count).max() ?? 1)
            let count = CGFloat(rows.count)
            let units = (showsTitle ? 0.8 * 1.35 + 0.55 : 0) + count * 1.35 + (count - 1) * 0.55
            return min(64, width / (longest * 1.02), available / units)
        }
        let clauses = lines.flatMap(PoemVerseSplitter.split)
        let byClause = size(for: clauses)
        if byClause >= 40 || clauses.count == lines.count {
            return HorizontalFit(rows: clauses, fontSize: byClause)
        }
        let byVerse = size(for: lines)
        if byVerse >= Self.bilingualMinimumVerseSize || lines.count == 1 {
            return HorizontalFit(rows: lines, fontSize: byVerse)
        }
        var count = lines.count - 1
        while count > 1 && size(for: Array(lines.prefix(count))) < Self.bilingualMinimumVerseSize {
            count -= 1
        }
        let rows = Array(lines.prefix(count))
        return HorizontalFit(rows: rows, fontSize: size(for: rows), isExcerpt: true)
    }

    private func horizontalPoem(width: CGFloat, height: CGFloat) -> some View {
        let fit = horizontalFit(width: width, height: height)
        let colophon = [lunarDateText, locationMark.map { inscriptionText($0, isExcerpt: fit.isExcerpt) } ?? ""]
            .filter { !$0.isEmpty }
            .joined(separator: "\u{3000}")
        return VStack(alignment: .leading, spacing: fit.rowSpacing) {
            if showsTitle {
                Text(imageTitle.poemScript(script))
                    .font(typeface.font(size: fit.titleSize))
                    .foregroundStyle(Color.mutedInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            ForEach(Array(fit.rows.enumerated()), id: \.offset) { _, row in
                Text(row.poemScript(script))
                    .font(typeface.font(size: fit.fontSize))
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
            HStack(alignment: .bottom) {
                Text(colophon.poemScript(script))
                    .font(typeface.font(size: 26))
                    .foregroundStyle(Color.mutedInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer(minLength: 24)
                if showsSeal && !sealName.isEmpty {
                    SealStampView(name: sealName, style: sealStyleOverride, size: 96, transliterationOverrideValue: sealTransliterationOverride)
                }
            }
        }
    }

    /// The largest reading size that fits `maxHeight`. A reading too long even
    /// at the smallest size keeps its opening sentences and ends in an ellipsis.
    private static func readingMetrics(
        _ translation: ShareTranslation,
        width: CGFloat,
        maxHeight: CGFloat,
        sizes: ClosedRange<CGFloat>
    ) -> ShareReadingMetrics {
        func height(_ text: String, _ size: CGFloat) -> CGFloat {
            ShareReadingMetrics(text: text, bodySize: size, height: 0)
                .measuredHeight(title: translation.title, byline: translation.byline, width: width)
        }
        var size = sizes.upperBound
        while size > sizes.lowerBound && height(translation.text, size) > maxHeight {
            size -= 1
        }
        var text = translation.text
        if height(text, size) > maxHeight {
            text = Self.openingText(of: text, fitting: { height($0, size) <= maxHeight })
        }
        return ShareReadingMetrics(text: text, bodySize: size, height: height(text, size))
    }

    /// Whole sentences while they fit; whole words if not even one does.
    private static func openingText(of text: String, fitting fits: (String) -> Bool) -> String {
        func pieces(_ options: String.EnumerationOptions) -> [String] {
            var result: [String] = []
            text.enumerateSubstrings(in: text.startIndex..., options: options) { _, range, enclosing, _ in
                result.append(String(text[options == .bySentences ? range : enclosing]))
            }
            return result
        }
        for options in [String.EnumerationOptions.bySentences, .byWords] {
            var kept = ""
            for piece in pieces(options) {
                let candidate = (kept + piece).trimmingCharacters(in: .whitespaces)
                guard fits(candidate + " …") else { break }
                kept = options == .bySentences ? candidate + " " : kept + piece
            }
            let trimmed = kept.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed + " …" }
        }
        return "…"
    }

    private var inscription: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(lunarDateText.poemScript(script))
                .font(typeface.font(size: 30))
                .foregroundStyle(Color.mutedInk)
            if let locationMark {
                Text(compactInscriptionText(locationMark).poemScript(script))
                    .font(typeface.font(size: 30))
                    .foregroundStyle(Color.mutedInk)
            }
        }
    }
}

/// Type sizes for the English reading on a share image, with the measured
/// height the layout reserves for it.
private struct ShareReadingMetrics {
    let text: String
    let bodySize: CGFloat
    let height: CGFloat

    var titleSize: CGFloat { bodySize * 1.3 }
    var bylineSize: CGFloat { bodySize * 0.8 }
    var lineSpacing: CGFloat { bodySize * 0.38 }
    var bylineGap: CGFloat { bodySize * 0.3 }
    /// Space above and below the short cinnabar rule.
    var ruleGap: CGFloat { bodySize * 0.8 }
    static let ruleHeight: CGFloat = 2

    static func serif(size: CGFloat, weight: UIFont.Weight = .regular, italic: Bool = false) -> UIFont {
        var descriptor = UIFont.systemFont(ofSize: size, weight: weight).fontDescriptor
        descriptor = descriptor.withDesign(.serif) ?? descriptor
        if italic {
            descriptor = descriptor.withSymbolicTraits(.traitItalic) ?? descriptor
        }
        return UIFont(descriptor: descriptor, size: size)
    }

    private static func height(of text: String, font: UIFont, width: CGFloat, lineSpacing: CGFloat = 0) -> CGFloat {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = lineSpacing
        let rect = (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font, .paragraphStyle: paragraph],
            context: nil
        )
        return ceil(rect.height)
    }

    /// Mirrors `ShareReadingBlock`, with a little slack for SwiftUI's line breaking.
    func measuredHeight(title: String, byline: String, width: CGFloat) -> CGFloat {
        let titleHeight = Self.height(of: title, font: Self.serif(size: titleSize, italic: true), width: width)
        let bylineHeight = byline.isEmpty ? 0 : bylineGap + Self.height(of: byline, font: Self.serif(size: bylineSize), width: width)
        let bodyHeight = Self.height(of: text, font: Self.serif(size: bodySize, weight: .light), width: width, lineSpacing: lineSpacing)
        return (titleHeight + bylineHeight + ruleGap * 2 + Self.ruleHeight + bodyHeight) * 1.04
    }
}

/// English title, byline and reading, on a soft wash of paper so the words
/// stay legible where they cross the painting.
private struct ShareReadingBlock: View {
    let translation: ShareTranslation
    let metrics: ShareReadingMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(translation.title)
                .font(.system(size: metrics.titleSize, weight: .regular, design: .serif))
                .italic()
                .foregroundStyle(Color.ink)
            if !translation.byline.isEmpty {
                Text(translation.byline)
                    .font(.system(size: metrics.bylineSize, design: .serif))
                    .foregroundStyle(Color.mutedInk)
                    .padding(.top, metrics.bylineGap)
            }
            Rectangle()
                .fill(Color.cinnabar.opacity(0.75))
                .frame(width: metrics.bodySize * 1.8, height: ShareReadingMetrics.ruleHeight)
                .padding(.vertical, metrics.ruleGap)
            Text(metrics.text)
                .font(.system(size: metrics.bodySize, weight: .light, design: .serif))
                .lineSpacing(metrics.lineSpacing)
                .foregroundStyle(Color.ink.opacity(0.86))
        }
        .fixedSize(horizontal: false, vertical: true)
        .background {
            Rectangle()
                .fill(Color.white.opacity(0.7))
                .padding(-metrics.bodySize * 1.4)
                .blur(radius: metrics.bodySize * 1.1)
        }
    }
}

/// A vertical artwork column that also accepts Latin text (an English title
/// or place name), turned a quarter clockwise as in Chinese books — unlike
/// `VerticalText`, which falls back to a horizontal label for interface text.
private struct ArtworkColumnText: View {
    @Environment(\.poemTypeface) private var typeface
    let text: String
    let fontSize: CGFloat
    var color: Color = .ink
    let spacing: CGFloat

    var body: some View {
        if text.containsCJK || text.isEmpty {
            VerticalText(text, font: typeface.font(size: fontSize), color: color, spacing: spacing)
        } else {
            let font = typeface.resolvedFontName.flatMap { UIFont(name: $0, size: fontSize) } ?? UIFont.systemFont(ofSize: fontSize)
            let length = ceil((text as NSString).size(withAttributes: [.font: font]).width)
            let thickness = ceil(font.lineHeight)
            Text(text)
                .font(typeface.font(size: fontSize))
                .foregroundStyle(color)
                .fixedSize()
                .frame(width: length, height: thickness)
                .rotationEffect(.degrees(90))
                .frame(width: thickness, height: length)
        }
    }
}

enum SealStampStyle: String, CaseIterable, Identifiable {
    static let storageKey = "sealStyle"

    case zhuwen
    case baiwen

    var id: String { rawValue }

    var isFree: Bool {
        self == .zhuwen
    }

    var displayName: String {
        switch self {
        case .zhuwen:
            return AppLanguage.copy("朱文", "Relief seal")
        case .baiwen:
            return AppLanguage.copy("白文", "Intaglio seal")
        }
    }
}

struct SealStampView: View {
    static let storageKey = "sealName"

    @AppStorage(SealStampStyle.storageKey) private var storedStyleRawValue = SealStampStyle.zhuwen.rawValue
    @AppStorage(NameTransliterator.overrideStorageKey) private var transliterationOverride = ""

    let name: String
    var style: SealStampStyle? = nil
    let size: CGFloat
    var transliterationOverrideValue: String? = nil

    private var resolvedStyle: SealStampStyle {
        style ?? SealStampStyle(rawValue: storedStyleRawValue) ?? .zhuwen
    }

    private var sealChars: [String] {
        if let glyphs = NameTransliterator.glyphs(for: name, storedOverride: transliterationOverrideValue ?? transliterationOverride) {
            return glyphs.map(\.value)
        }
        let chars = Array(Self.simplifiedSealText(NameTransliterator.rawSealText(name))).map(String.init)
        return Array(chars.prefix(4))
    }

    private static func simplifiedSealText(_ text: String) -> String {
        let mutable = NSMutableString(string: text)
        CFStringTransform(mutable, nil, "Hant-Hans" as CFString, false)
        return mutable as String
    }

    private var inkColor: Color {
        resolvedStyle == .zhuwen ? .cinnabar : .white
    }

    private var paperColor: Color {
        resolvedStyle == .zhuwen ? Color.white.opacity(0.9) : .cinnabar
    }

    private var scarColor: Color {
        resolvedStyle == .zhuwen ? Color.white.opacity(0.62) : Color.white.opacity(0.2)
    }

    private func sealFont(size fontSize: CGFloat) -> Font {
        let sealFontName = "FZXZTFW--GB1-0"
        if UIFont(name: sealFontName, size: 12) != nil {
            return Font.custom(sealFontName, size: fontSize).weight(.regular)
        }
        return PoemTypeface.mashan.font(size: fontSize)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: max(1, size * 0.025))
                .fill(paperColor)

            RoundedRectangle(cornerRadius: max(1, size * 0.025))
                .stroke(inkColor.opacity(0.96), lineWidth: max(1.4, size * 0.045))
                .padding(size * 0.045)

            stampGrid
                .foregroundStyle(inkColor)
                .padding(size * 0.072)

            sealWear
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: max(1, size * 0.025)))
        .rotationEffect(.degrees(-5))
    }

    private var stampGrid: some View {
        let chars = paddedSealChars
        return HStack(spacing: size * 0.014) {
            VStack(spacing: size * 0.004) {
                stampCharacter(chars[2])
                stampCharacter(chars[3])
            }
            VStack(spacing: size * 0.004) {
                stampCharacter(chars[0])
                stampCharacter(chars[1])
            }
        }
    }

    private var paddedSealChars: [String] {
        let chars = sealChars
        return chars + Array(repeating: "", count: max(0, 4 - chars.count))
    }

    private func stampCharacter(_ character: String) -> some View {
        Text(character)
            .font(sealFont(size: max(20, size * 0.43)))
            .minimumScaleFactor(0.62)
            .lineLimit(1)
            .frame(width: size * 0.40, height: size * 0.40)
    }

    private var sealWear: some View {
        ZStack {
            ForEach(0..<10, id: \.self) { index in
                Rectangle()
                    .fill(scarColor)
                    .frame(
                        width: size * CGFloat([0.08, 0.16, 0.05, 0.12, 0.20, 0.07, 0.10, 0.14, 0.06, 0.18][index]),
                        height: max(0.7, size * CGFloat([0.010, 0.016, 0.012, 0.009, 0.014, 0.011, 0.015, 0.010, 0.013, 0.008][index]))
                    )
                    .position(
                        x: size * CGFloat([0.18, 0.34, 0.62, 0.79, 0.26, 0.52, 0.70, 0.43, 0.86, 0.13][index]),
                        y: size * CGFloat([0.14, 0.23, 0.18, 0.32, 0.56, 0.49, 0.68, 0.79, 0.84, 0.72][index])
                    )
                    .rotationEffect(.degrees(Double([-7, 3, -2, 8, 0, -5, 6, -3, 4, -8][index])))
            }
        }
        .allowsHitTesting(false)
    }
}

struct ChoiceColumn: View {
    @Environment(\.poemTypeface) private var typeface
    let title: String
    let subtitle: String
    let isSelected: Bool
    var isSpotlightTarget: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VerticalText(title, font: typeface.font(size: 19), color: isSelected ? .white : .ink, spacing: 7, forceVertical: true)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? Color.cinnabar : Color.clear)
                }
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.cinnabar, lineWidth: 1)
                    }
                }
                .opacity(isSelected ? 1 : 0.82)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .spotlightTarget(.selectImage, active: isSpotlightTarget, offset: CGSize(width: 0, height: 12), insetBy: CGSize(width: -2, height: 0))
        .animation(.spring(response: 0.25, dampingFraction: 0.65), value: isSelected)
    }
}

struct VerticalText: View {
    @Environment(\.poemTypeface) private var typeface
    @Environment(\.poemScript) private var script
    let text: String
    let font: Font?
    let style: PoemFontStyle?
    let color: Color
    let spacing: CGFloat

    init(_ text: String, font: Font, color: Color = .ink, spacing: CGFloat = 6, forceVertical: Bool = false) {
        self.text = text
        self.font = font
        self.style = nil
        self.color = color
        self.spacing = spacing
    }

    init(_ text: String, style: PoemFontStyle, color: Color = .ink, spacing: CGFloat = 6, forceVertical: Bool = false) {
        self.text = text
        self.font = nil
        self.style = style
        self.color = color
        self.spacing = spacing
    }

    var body: some View {
        let convertedText = text.poemScript(script)
        Group {
            if AppLanguage.isEnglish && !convertedText.unicodeScalars.contains(where: { CharacterSet.cjk.contains($0) }) {
                Text(convertedText)
                    .font(font ?? .system(size: 14, weight: .medium, design: .serif))
                    .foregroundStyle(color)
                    .multilineTextAlignment(.center)
            } else {
                VStack(spacing: spacing) {
                    ForEach(Array(convertedText.enumerated()), id: \.offset) { _, character in
                        Text(String(character))
                            .font(font ?? typeface.font(for: style ?? .body))
                            .foregroundStyle(color)
                    }
                }
            }
        }
        .fixedSize()
    }
}

struct SealButton: View {
    @Environment(\.poemTypeface) private var typeface
    @Environment(\.poemScript) private var script
    @Environment(\.spotlightGuide) private var spotlightGuide
    let title: String
    let isSelected: Bool
    var spotlightStep: SpotlightStep? = nil
    var advancesSpotlightAutomatically = true
    let action: () -> Void

    private var isSpotlightTarget: Bool {
        spotlightStep != nil && spotlightGuide.step == spotlightStep
    }

    var body: some View {
        Button {
            action()
            if isSpotlightTarget && advancesSpotlightAutomatically {
                spotlightGuide.advance()
            }
        } label: {
            Text(title.poemScript(script))
                .font(typeface.sealFont)
                .foregroundStyle(isSelected ? .white : .cinnabar)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(width: 38, height: 38)
                .background {
                    Circle()
                        .fill(isSelected ? Color.cinnabar : Color.clear)
                        .stroke(Color.cinnabar, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .spotlightTarget(spotlightStep ?? .tapShare, active: isSpotlightTarget)
    }
}

struct SealTextButton: View {
    @Environment(\.poemTypeface) private var typeface
    @Environment(\.poemScript) private var script
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title.poemScript(script))
                .font(AppLanguage.isEnglish ? .system(size: 11, weight: .semibold) : typeface.font(size: 17))
                .foregroundStyle(.white)
                .frame(width: AppLanguage.isEnglish ? 76 : 44, height: 44)
                .background {
                    if AppLanguage.isEnglish {
                        RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.cinnabar)
                    } else {
                        Circle().fill(Color.cinnabar)
                    }
                }
        }
        .buttonStyle(.plain)
    }
}

enum SensoryFeedback {
    static func lightTap() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()
    }
}

private struct DateColumnLabel: View {
    @Environment(\.poemTypeface) private var typeface

    var body: some View {
        VStack(spacing: 7) {
            ForEach(Array(PoemDateText.current.yearText.enumerated()), id: \.offset) { _, character in
                Text(String(character))
                    .font(typeface.font(size: 22))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.ink)
            }
        }
        .fixedSize()
    }
}

struct PoemDateText {
    let yearText: String
    let monthText: String
    let fullDateText: String

    static var current: PoemDateText {
        make(from: Date())
    }

    static func make(from date: Date, calendar: Calendar = .current) -> PoemDateText {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 2026
        let month = components.month ?? 1
        let day = components.day ?? 1

        let yearText = "\(digits(year))年"
        let monthText = "\(number(month))月"
        let dayText = "\(number(day))日"

        return PoemDateText(
            yearText: yearText,
            monthText: monthText,
            fullDateText: "\(yearText) \(monthText) \(dayText)"
        )
    }

    private static func digits(_ value: Int) -> String {
        String(value).map { digit in
            switch digit {
            case "0": return "零"
            case "1": return "一"
            case "2": return "二"
            case "3": return "三"
            case "4": return "四"
            case "5": return "五"
            case "6": return "六"
            case "7": return "七"
            case "8": return "八"
            case "9": return "九"
            default: return ""
            }
        }
        .joined()
    }

    private static func number(_ value: Int) -> String {
        switch value {
        case 1...9:
            return digit(value)
        case 10:
            return "十"
        case 11...19:
            return "十\(digit(value - 10))"
        case 20...29:
            return "二十\(value % 10 == 0 ? "" : digit(value % 10))"
        case 30:
            return "三十"
        case 31:
            return "三十一"
        default:
            return digits(value)
        }
    }

    private static func digit(_ value: Int) -> String {
        ["", "一", "二", "三", "四", "五", "六", "七", "八", "九"][value]
    }
}

struct PoemInscriptionDate {
    let lunarDateText: String
    let dayPeriodText: String

    static var current: PoemInscriptionDate {
        make(from: Date())
    }

    static func make(from date: Date) -> PoemInscriptionDate {
        var chineseCalendar = Calendar(identifier: .chinese)
        chineseCalendar.timeZone = .current
        let lunar = chineseCalendar.dateComponents([.year, .month], from: date)
        let gregorian = Calendar.current.dateComponents([.hour], from: date)

        let year = lunar.year ?? 1
        let month = lunar.month ?? 1
        let period = traditionalHour(hour: gregorian.hour ?? 12)
        let season = lunarSeason(month)
        return PoemInscriptionDate(
            lunarDateText: "\(sexagenaryYear(year))年\u{2009}\(season)",
            dayPeriodText: period
        )
    }

    private static func sexagenaryYear(_ year: Int) -> String {
        let stems = ["甲", "乙", "丙", "丁", "戊", "己", "庚", "辛", "壬", "癸"]
        let branches = ["子", "丑", "寅", "卯", "辰", "巳", "午", "未", "申", "酉", "戌", "亥"]
        let index = max(0, year - 1)
        return "\(stems[index % stems.count])\(branches[index % branches.count])"
    }

    private static func lunarSeason(_ month: Int) -> String {
        let seasons = ["孟春", "仲春", "暮春", "孟夏", "仲夏", "暮夏", "孟秋", "仲秋", "暮秋", "孟冬", "仲冬", "暮冬"]
        let safeMonth = min(max(month, 1), seasons.count)
        return seasons[safeMonth - 1]
    }

    private static func lunarMonth(_ month: Int, isLeap: Bool) -> String {
        let names = ["正月", "二月", "三月", "四月", "五月", "六月", "七月", "八月", "九月", "十月", "冬月", "臘月"]
        let safeMonth = min(max(month, 1), names.count)
        return "\(isLeap ? "閏" : "")\(names[safeMonth - 1])"
    }

    private static func lunarDay(_ day: Int) -> String {
        switch day {
        case 1...10:
            return "初\(digit(day))"
        case 11...19:
            return "十\(digit(day - 10))"
        case 20:
            return "二十"
        case 21...29:
            return "廿\(digit(day - 20))"
        case 30:
            return "三十"
        default:
            return ""
        }
    }

    private static func traditionalHour(hour: Int) -> String {
        switch hour {
        case 23, 0:
            return "子時"
        case 1...2:
            return "丑時"
        case 3...4:
            return "寅時"
        case 5...6:
            return "卯時"
        case 7...8:
            return "辰時"
        case 9...10:
            return "巳時"
        case 11...12:
            return "午時"
        case 13...14:
            return "未時"
        case 15...16:
            return "申時"
        case 17...18:
            return "酉時"
        case 19...20:
            return "戌時"
        case 21...22:
            return "亥時"
        default:
            return "午時"
        }
    }

    private static func digit(_ value: Int) -> String {
        ["", "一", "二", "三", "四", "五", "六", "七", "八", "九", "十"][min(max(value, 0), 10)]
    }
}

struct PaperBackground: View {
    @AppStorage(ShadowStyle.storageKey) private var shadowStyleRaw = ShadowStyle.defaultStyle.rawValue
    @AppStorage(PoemBackground.storageKey) private var backgroundRawValue = PoemBackground.defaultBackground.rawValue

    var backgroundOverride: PoemBackground? = nil
    var shadowStyleOverride: ShadowStyle? = nil

    private var shadowStyle: ShadowStyle {
        shadowStyleOverride ?? ShadowStyle(rawValue: shadowStyleRaw) ?? .defaultStyle
    }

    private var background: PoemBackground {
        backgroundOverride ?? PoemBackground(rawValue: backgroundRawValue) ?? PoemBackground.defaultBackground
    }

    var body: some View {
        ZStack {
            Color.white
                .ignoresSafeArea()

            if let imageName = background.imageName {
                GeometryReader { geo in
                    Image(imageName)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .ignoresSafeArea()
                        .transition(.opacity)
                }
                .ignoresSafeArea()
            } else {
                DappledShadowView(styleOverride: shadowStyle)
                    .id(shadowStyle.rawValue)
                    .opacity(shadowStyle.paperOpacity)
                    .ignoresSafeArea()
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.35), value: shadowStyle.rawValue)
        .animation(.easeOut(duration: 0.35), value: background.rawValue)
    }
}

private extension Color {
    static let paper = Color.white
    static let rice = Color(red: 0.94, green: 0.91, blue: 0.84)
    static let ink = Color(red: 0.08, green: 0.075, blue: 0.07)
    static let mutedInk = Color(red: 0.34, green: 0.32, blue: 0.29)
    static let cinnabar = Color(red: 0.77, green: 0.02, blue: 0.06)
}

extension Color {
    /// The membership crown's gold, shared with the poem list's Pro filter.
    static let premiumGold = Color(red: 0.94, green: 0.64, blue: 0.08)
}

enum PoemFontStyle {
    case title
    case body
    case small
    case accent
    case seal
    case tinySeal
}

 enum PoemScript: String, CaseIterable, Identifiable {
    static let storageKey = "poemScript"

    case traditional
    case simplified

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .traditional:
            return AppLanguage.copy("繁體", "Traditional")
        case .simplified:
            return AppLanguage.copy("简体", "Simplified")
        }
    }

    var promptName: String {
        switch self {
        case .traditional:
            return "繁體中文"
        case .simplified:
            return "简体中文"
        }
    }
}

extension String {
    var containsCJK: Bool {
        unicodeScalars.contains { CharacterSet.cjk.contains($0) }
    }
}

extension CharacterSet {
    static let cjk: CharacterSet = {
        var set = CharacterSet()
        set.insert(charactersIn: "\u{4E00}"..."\u{9FFF}")
        set.insert(charactersIn: "\u{3400}"..."\u{4DBF}")
        set.insert(charactersIn: "\u{20000}"..."\u{2A6DF}")
        set.insert(charactersIn: "\u{F900}"..."\u{FAFF}")
        return set
    }()
}

extension String {
    func poemScript(_ script: PoemScript) -> String {
        let mutable = NSMutableString(string: self)
        let transform: CFString = script == .traditional
            ? "Hans-Hant" as CFString
            : "Hant-Hans" as CFString
        CFStringTransform(mutable, nil, transform, false)
        return mutable as String
    }
}

struct PoemTypefaceKey: EnvironmentKey {
    static let defaultValue = PoemTypeface.kaiti
}

extension EnvironmentValues {
    var poemTypeface: PoemTypeface {
        get { self[PoemTypefaceKey.self] }
        set { self[PoemTypefaceKey.self] = newValue }
    }
}

private struct PoemScriptKey: EnvironmentKey {
    static let defaultValue = PoemScript.simplified
}

extension EnvironmentValues {
    var poemScript: PoemScript {
        get { self[PoemScriptKey.self] }
        set { self[PoemScriptKey.self] = newValue }
    }
}

enum PoemTypeface: String, CaseIterable, Identifiable {
    static let storageKey = "poemTypeface"
    static let bodyFontSize: CGFloat = 17

    case kaiti
    case wenyue
    case wenkai
    case songti
    case mashan
    case xiaozhuan

    var id: String { rawValue }

    var isFree: Bool {
        self == .wenyue || self == .wenkai || self == .kaiti
    }

    /// Always the Chinese name: in both languages the picker shows it set in the face itself,
    /// since the Han glyphs are what distinguish these fonts.
    var displayName: String {
        switch self {
        case .wenyue:
            return "文悦仿宋"
        case .wenkai:
            return "霞鹜文楷"
        case .songti:
            return "思源宋体"
        case .kaiti:
            return "汇文明朝体"
        case .mashan:
            return "马善政体"
        case .xiaozhuan:
            return "方正小篆"
        }
    }

    /// Short English style label shown under the Chinese name in the English UI.
    var englishStyleName: String {
        switch self {
        case .wenyue:
            return "FangSong"
        case .wenkai:
            return "Kai · Brush"
        case .songti:
            return "Song · Serif"
        case .kaiti:
            return "Mincho"
        case .mashan:
            return "Calligraphy"
        case .xiaozhuan:
            return "Seal Script"
        }
    }

    var fontNames: [String] {
        switch self {
        case .wenyue:
            return ["WenYue_GuTiFangSong_F", "WenYue GuTiFangSong F", "文悦古体仿宋 繁体 (需授权)"]
        case .wenkai:
            return ["LXGWWenKaiLite-Regular", "LXGW WenKai Lite"]
        case .songti:
            return ["SourceHanSerifCN-ExtraLight", "Source Han Serif CN ExtraLight", "思源宋体 CN ExtraLight"]
        case .kaiti:
            return ["Huiwen-mincho", "汇文明朝体"]
        case .mashan:
            return ["MaShanZheng-Regular", "Ma Shan Zheng Regular", "Ma Shan Zheng"]
        case .xiaozhuan:
            return ["FZXZTFW--GB1-0", "FZXiaoZhuanTi-S13T", "方正小篆体"]
        }
    }

    var resolvedFontName: String? {
        fontNames.first { UIFont(name: $0, size: 12) != nil }
    }

    func font(size: CGFloat) -> Font {
        let scaledSize = size
        if let resolvedFontName {
            return Font.custom(resolvedFontName, size: scaledSize).weight(.regular)
        }

        switch self {
        case .songti:
            return .system(size: scaledSize, design: .serif).weight(.regular)
        case .kaiti:
            return .system(size: scaledSize, design: .serif).italic()
        case .wenyue, .wenkai, .mashan, .xiaozhuan:
            return Font.custom(PoemTypeface.wenyue.fontNames[0], size: scaledSize).weight(.regular)
        }
    }

    func previewFont(size: CGFloat) -> Font {
        font(size: size)
    }

    /// These fonts center full-width punctuation (，。；、) vertically in the em box
    /// (Japanese-style metrics). Shift such punctuation down by this fraction of the
    /// font size to restore the usual Chinese bottom-left placement.
    var punctuationDropFactor: CGFloat? {
        switch self {
        case .kaiti:
            return 0.28
        case .wenyue:
            return 0.30
        case .mashan:
            return 0.07
        case .wenkai, .songti, .xiaozhuan:
            return nil
        }
    }

    var titleFont: Font { font(size: 18) }
    var bodyFont: Font { font(size: 17) }
    var smallFont: Font { font(size: 14) }
    var accentFont: Font { font(size: 16) }
    var sealFont: Font { font(size: 14) }
    var tinySealFont: Font { font(size: 12) }

    func font(for style: PoemFontStyle) -> Font {
        switch style {
        case .title:
            return titleFont
        case .body:
            return bodyFont
        case .small:
            return smallFont
        case .accent:
            return accentFont
        case .seal:
            return sealFont
        case .tinySeal:
            return tinySealFont
        }
    }
}
