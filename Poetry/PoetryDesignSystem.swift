import SwiftUI
import UIKit
import CoreFoundation
import StoreKit

private func compactInscriptionText(_ text: String) -> String {
    text
        .replacingOccurrences(of: "\u{2009}", with: "")
        .replacingOccurrences(of: "\u{00A0}", with: "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

enum PaywallReason: String, Identifiable {
    case membership
    case dailyLimit
    case poemForm
    case typeface
    case sealStyle
    case background
    case classicAppreciation
    case poetProfile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .membership:
            return AppLanguage.copy("雅集會員", "Pro")
        case .dailyLimit:
            return AppLanguage.copy("今日詩興已滿", "Free poems used")
        case .poemForm:
            return AppLanguage.copy("開通詩式", "Unlock poem forms")
        case .typeface:
            return AppLanguage.copy("開通字體", "Unlock typefaces")
        case .sealStyle:
            return AppLanguage.copy("開通朱印", "Unlock seal styles")
        case .background:
            return AppLanguage.copy("開通紙面", "Unlock backgrounds")
        case .classicAppreciation:
            return AppLanguage.copy("解鎖詩歌賞析", "Unlock AI commentary")
        case .poetProfile:
            return AppLanguage.copy("解鎖詩人導讀", "Unlock poet guides")
        }
    }

    var message: String {
        switch self {
        case .membership:
            return AppLanguage.copy("開通雅集，解鎖不限作詩、AI 詩歌賞析、詩人導讀與更多創作樣式。", "Write without limits. Unlock all Pro features.")
        case .dailyLimit:
            return AppLanguage.copy("每日可免費作詩三首，雅集不限生成。", "Upgrade to Pro for unlimited poems.")
        case .poemForm:
            return AppLanguage.copy("七言、律詩與更多詩式收入雅集。", "More poem forms are available with Pro.")
        case .typeface:
            return AppLanguage.copy("更多書體可隨詩稿一同留存。", "More typefaces are available with Pro.")
        case .sealStyle:
            return AppLanguage.copy("白文與專屬落印收入雅集。", "More seal styles are available with Pro.")
        case .background:
            return AppLanguage.copy("更多水墨紙面與付費背景收入雅集，可用於保存與分享詩作。", "More papers and backgrounds are available with Pro.")
        case .classicAppreciation:
            return AppLanguage.copy("每日可免費品讀一首，雅集可不限次生成 AI 詩歌賞析。", "Upgrade to Pro for unlimited commentary.")
        case .poetProfile:
            return AppLanguage.copy("雅集收錄名家小傳與完整作品導讀，循著一生讀懂詩。", "Unlock poet profiles and collections with Pro.")
        }
    }

    var features: [String] {
        switch self {
        case .membership:
            return AppLanguage.isEnglish
                ? ["Unlimited poems", "Unlimited AI commentary", "Poet profiles and collections", "All forms and styles"]
                : ["不限作詩", "AI 詩歌賞析不限次", "名家小傳與完整作品", "七言與律詩", "高級字體", "朱印樣式·白文", "會員紙面與背景"]
        case .dailyLimit:
            return AppLanguage.isEnglish
                ? ["Unlimited poems", "All poem forms", "Premium styles"]
                : ["不限生成", "七言與律詩", "高級字體", "朱印樣式·白文", "會員紙面與背景"]
        case .poemForm:
            return AppLanguage.isEnglish ? ["All poem forms", "Unlimited poems"] : ["七言與律詩", "更多詩式", "不限生成"]
        case .typeface:
            return AppLanguage.isEnglish ? ["Premium typefaces", "Unlimited poems"] : ["高級字體", "詩稿字體同步", "不限生成"]
        case .sealStyle:
            return AppLanguage.isEnglish ? ["More seal styles", "Unlimited poems"] : ["朱印樣式·白文", "更多落印樣式", "不限生成"]
        case .background:
            return AppLanguage.isEnglish ? ["Premium papers and backgrounds", "Unlimited poems"] : ["會員紙面", "付費背景", "保存與分享可用"]
        case .classicAppreciation:
            return AppLanguage.isEnglish ? ["Unlimited AI commentary", "Unlimited poems"] : ["AI 詩歌賞析不限次", "從意象、語言與情感品讀", "不限作詩"]
        case .poetProfile:
            return AppLanguage.isEnglish ? ["Poet profiles and collections", "Unlimited AI commentary"] : ["名家小傳", "完整收錄作品", "AI 詩歌賞析不限次"]
        }
    }
}

enum PremiumAccess {
    private static let freeDailyLimit = 3
    private static let usageDateKey = "freePoemUsageDate"
    private static let usageCountKey = "freePoemUsageCount"
    private static let freeAppreciationDailyLimit = 1
    private static let appreciationUsageDateKey = "freeAppreciationUsageDate"
    private static let appreciationUsageCountKey = "freeAppreciationUsageCount"
    static var freeLimit: Int {
        freeDailyLimit
    }

    static var usedToday: Int {
        usageCountForToday()
    }

    static var freeRemaining: Int {
        max(0, freeDailyLimit - usageCountForToday())
    }

    static var freeAppreciationRemaining: Int {
        max(0, freeAppreciationDailyLimit - appreciationUsageCountForToday())
    }

    static func consumePoemIfNeeded(hasPremiumAccess: Bool) -> Bool {
        guard !hasPremiumAccess else { return true }
        let count = usageCountForToday()
        guard count < freeDailyLimit else { return false }
        UserDefaults.standard.set(todayKey, forKey: usageDateKey)
        UserDefaults.standard.set(count + 1, forKey: usageCountKey)
        return true
    }

    static func consumeAppreciationIfNeeded(hasPremiumAccess: Bool) -> Bool {
        guard !hasPremiumAccess else { return true }
        let count = appreciationUsageCountForToday()
        guard count < freeAppreciationDailyLimit else { return false }
        UserDefaults.standard.set(todayKey, forKey: appreciationUsageDateKey)
        UserDefaults.standard.set(count + 1, forKey: appreciationUsageCountKey)
        return true
    }

    private static func usageCountForToday() -> Int {
        guard UserDefaults.standard.string(forKey: usageDateKey) == todayKey else {
            return 0
        }
        return UserDefaults.standard.integer(forKey: usageCountKey)
    }

    private static func appreciationUsageCountForToday() -> Int {
        guard UserDefaults.standard.string(forKey: appreciationUsageDateKey) == todayKey else {
            return 0
        }
        return UserDefaults.standard.integer(forKey: appreciationUsageCountKey)
    }

    private static var todayKey: String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }
}

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.poemTypeface) private var typeface
    @Environment(\.poemScript) private var script
    @ObservedObject private var store = StoreManager.shared
    let reason: PaywallReason
    let onUnlock: () -> Void

    private func priceText(_ product: Product?) -> String {
        product?.displayPrice ?? "…"
    }

    private var monthlyIntroPrice: String {
        if let offer = store.monthly?.subscription?.introductoryOffer {
            return offer.displayPrice
        }
        return priceText(store.monthly)
    }

    var body: some View {
        ZStack {
            PaperBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(reason.title.poemScript(script))
                                .font(typeface.titleFont)
                                .foregroundStyle(Color.ink)
                            Text(reason.message.poemScript(script))
                                .font(typeface.smallFont)
                                .foregroundStyle(Color.mutedInk)
                        }
                        Spacer()
                        QuietBackButton(title: "關閉", spotlightStep: .returnFromShare) { dismiss() }
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(reason.features, id: \.self) { feature in
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

                    if let footerText {
                        Text(footerText.poemScript(script))
                            .font(typeface.tinySealFont)
                            .foregroundStyle(Color.mutedInk.opacity(0.75))
                            .frame(maxWidth: .infinity, alignment: .center)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 30)
                .padding(.top, 28)
                .padding(.bottom, 36)
            }
        }
        .task {
            await store.loadProducts()
        }
        .presentationDetents([.fraction(0.82), .large])
        .presentationDragIndicator(.visible)
        .presentationContentInteraction(.scrolls)
    }

    private var planSelection: some View {
        VStack(spacing: 12) {
            PaywallPlanButton(
                title: AppLanguage.copy("雅集月度", "Pro monthly"),
                price: monthlyIntroPrice,
                note: monthlyPlanNote,
                isPrimary: true
            ) {
                Task { await purchaseAndUnlock(store.monthly) }
            }
            PaywallPlanButton(
                title: AppLanguage.copy("雅集年度", "Pro yearly"),
                price: "\(priceText(store.yearly))/\(AppLanguage.copy("年", "year"))",
                note: AppLanguage.copy("每年自動續訂，可隨時取消", "Renews yearly. Cancel anytime."),
                isPrimary: false
            ) {
                Task { await purchaseAndUnlock(store.yearly) }
            }
            PaywallPlanButton(
                title: AppLanguage.copy("終身雅集", "Pro lifetime"),
                price: priceText(store.lifetime),
                note: AppLanguage.copy("一次購買，永久解鎖", "One payment. Lifetime access."),
                isPrimary: false
            ) {
                Task { await purchaseAndUnlock(store.lifetime) }
            }

        }
    }

    private func purchaseAndUnlock(_ product: Product?) async {
        guard let product else { return }
        let purchased = await store.purchase(product)
        if purchased {
            onUnlock()
            dismiss()
        }
    }

    private var footerActions: some View {
        VStack(spacing: 18) {
            restorePurchaseButton
            redemptionSection
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
        .frame(maxWidth: .infinity)
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
        .frame(maxWidth: .infinity)
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

    private var footerText: String? {
        switch reason {
        case .dailyLimit:
            return AppLanguage.isEnglish
                ? "Free poems today: \(PremiumAccess.usedToday)/\(PremiumAccess.freeLimit)"
                : "今日免費已用 \(PremiumAccess.usedToday)/\(PremiumAccess.freeLimit) 首"
        case .poemForm:
            return AppLanguage.isEnglish ? nil : "免費額度適用於五言絕句"
        case .typeface:
            return AppLanguage.isEnglish ? nil : "免費額度不包含高級字體"
        case .sealStyle:
            return AppLanguage.isEnglish ? nil : "免費額度不包含進階朱印"
        case .background:
            return AppLanguage.isEnglish ? nil : "前三款紙面免費可用，更多紙面與背景收入雅集"
        case .classicAppreciation:
            return AppLanguage.isEnglish
                ? "\(PremiumAccess.freeAppreciationRemaining) free commentary left today"
                : "今日免費賞析餘 \(PremiumAccess.freeAppreciationRemaining) 次"
        case .poetProfile:
            return AppLanguage.isEnglish ? nil : "李白小傳可免費閱讀，其餘名家內容收入雅集"
        case .membership:
            return AppLanguage.isEnglish
                ? "\(PremiumAccess.freeRemaining) poems · \(PremiumAccess.freeAppreciationRemaining) commentaries left today"
                : "今日可免費作詩餘 \(PremiumAccess.freeRemaining) 首 · 賞析餘 \(PremiumAccess.freeAppreciationRemaining) 次"
        }
    }

    private var monthlyPlanNote: String {
        guard let monthly = store.monthly else { return "" }
        if let offer = monthly.subscription?.introductoryOffer {
            return AppLanguage.isEnglish
                ? "First month \(offer.displayPrice), then \(monthly.displayPrice)/month. Cancel anytime."
                : "首月 \(offer.displayPrice)，之後 \(monthly.displayPrice)/月自動續訂，可隨時取消"
        }
        return AppLanguage.copy("每月自動續訂，可隨時取消", "Renews monthly. Cancel anytime.")
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
                    PremiumFeatureRow(icon: "infinity", text: AppLanguage.copy("不限生成次數", "Unlimited poem writing"))
                    PremiumFeatureRow(icon: "sparkles", text: AppLanguage.copy("AI 詩歌賞析不限次", "Unlimited AI commentary"))
                    PremiumFeatureRow(icon: "person.text.rectangle", text: AppLanguage.copy("名家小傳與完整作品", "Poet profiles and full collections"))
                    PremiumFeatureRow(icon: "text.book.closed", text: AppLanguage.copy("全部詩式：絕句與律詩", "All poem forms, including regulated verse"))
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
            Group {
                if AppLanguage.isEnglish {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                } else {
                    Text("印".poemScript(script))
                        .font(typeface.tinySealFont)
                }
            }
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
    let isPrimary: Bool
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
                            .foregroundStyle(isPrimary ? Color.white.opacity(0.82) : Color.mutedInk)
                    }
                }
                Spacer()
                Text(price)
                    .font(typeface.accentFont)
            }
            .foregroundStyle(isPrimary ? Color.white : Color.ink)
            .padding(.horizontal, 18)
            .frame(minHeight: AppLanguage.isEnglish ? 70 : 58)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isPrimary ? Color.cinnabar : Color.white.opacity(0.6))
                    .stroke(isPrimary ? Color.cinnabar : Color.mutedInk.opacity(0.22), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

/// Shared settings entry for every tab's root page.
struct SettingsButton: View {
    @Environment(\.poemScript) private var script
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "gearshape")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(ClassicPalette.ink)
                .frame(width: 38, height: 38)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AppLanguage.copy("設置", "Settings").poemScript(script))
    }
}

private enum AppReviewPrompt {
    static let completedFirstPoemKey = "poetry.completedFirstPoem"
    static let requestedAfterFirstPoemKey = "poetry.requestedReviewAfterFirstPoem"

    static func request() {
        let requestBlock = {
            guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }) else {
                return
            }

            SKStoreReviewController.requestReview(in: scene)
        }

        if Thread.isMainThread {
            requestBlock()
        } else {
            DispatchQueue.main.async(execute: requestBlock)
        }
    }
}

private struct SmallCircleButton: View {
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

private struct QuietBackButton: View {
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

struct FontSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.poemTypeface) private var typeface
    @Environment(\.poemScript) private var script
    @AppStorage(PoemTypeface.storageKey) private var selectedRawValue = PoemTypeface.kaiti.rawValue
    @AppStorage(PoemScript.storageKey) private var selectedScriptRawValue = PoemScript.simplified.rawValue
    @AppStorage(SealStampView.storageKey) private var sealName = ""
    @AppStorage(SealStampStyle.storageKey) private var selectedSealStyleRawValue = SealStampStyle.zhuwen.rawValue
    @ObservedObject private var store = StoreManager.shared
    @State private var editingSealName = ""
    @State private var paywallReason: PaywallReason?
    @State private var showsAbout = false
    @State private var showsPremiumStatus = false
    @FocusState private var sealNameFocused: Bool

    private var hasPremiumAccess: Bool {
        store.isPremium
    }

    var body: some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    sealNameFocused = false
                }

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    HStack(alignment: .top) {
                        Text(AppLanguage.copy("設置", "Settings").poemScript(script))
                            .font(typeface.titleFont)
                            .foregroundStyle(Color.ink)
                        Spacer()
                        QuietBackButton(title: "返回") { dismiss() }
                    }

                    // Membership banner
                    if !hasPremiumAccess {
                        Button {
                            paywallReason = .membership
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
                                    Text(AppLanguage.copy("解鎖全部詩式、字體、朱印與不限生成", "Unlock all forms, typefaces, seals, papers, and unlimited poems.").poemScript(script))
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
                                    .fill(Color.white.opacity(0.6))
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
                                    .fill(Color.white.opacity(0.6))
                                    .stroke(Color.cinnabar.opacity(0.15), lineWidth: 0.8)
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        Text(AppLanguage.copy("朱印", "Seal").poemScript(script))
                            .font(typeface.smallFont)
                            .foregroundStyle(Color.mutedInk)

                        HStack(alignment: .top, spacing: 24) {
                            VStack(alignment: .leading, spacing: 14) {
                                VStack(alignment: .leading, spacing: 8) {
                                    TextField("", text: $editingSealName, prompt: Text(AppLanguage.copy("姓名", "Name").poemScript(script)).foregroundStyle(Color.mutedInk.opacity(0.5)))
                                        .font(typeface.bodyFont)
                                        .foregroundStyle(Color.ink)
                                        .focused($sealNameFocused)
                                        .submitLabel(.done)
                                        .onSubmit {
                                            editingSealName = normalizedSealName
                                            sealNameFocused = false
                                        }
                                    Rectangle()
                                        .fill(Color.mutedInk.opacity(0.3))
                                        .frame(height: 0.5)
                                }

                                if !editingSealName.isEmpty {
                                    SealTransliterationChips(name: editingSealName)
                                }

                                HStack(spacing: 12) {
                                    ForEach(SealStampStyle.allCases) { style in
                                        Button {
                                            sealNameFocused = false
                                            guard hasPremiumAccess || style.isFree else {
                                                paywallReason = .sealStyle
                                                return
                                            }
                                            selectedSealStyleRawValue = style.rawValue
                                        } label: {
                                            ZStack(alignment: .bottomTrailing) {
                                                Text(style.displayName.poemScript(script))
                                                    .font(typeface.tinySealFont)
                                                    .foregroundStyle(selectedSealStyleRawValue == style.rawValue ? Color.cinnabar : Color.mutedInk)
                                                    .lineLimit(1)
                                                    .minimumScaleFactor(AppLanguage.isEnglish ? 0.62 : 1)
                                                    .frame(width: AppLanguage.isEnglish ? 82 : 48, height: 28)
                                                    .background {
                                                        RoundedRectangle(cornerRadius: 7)
                                                            .stroke(selectedSealStyleRawValue == style.rawValue ? Color.cinnabar.opacity(0.85) : Color.mutedInk.opacity(0.25), lineWidth: 0.9)
                                                    }

                                                if !style.isFree {
                                                    PremiumCrownBadge()
                                                        .offset(x: 7, y: 7)
                                                }
                                            }
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .frame(
                                maxWidth: AppLanguage.isEnglish ? .infinity : 142,
                                alignment: .leading
                            )

                            if !editingSealName.isEmpty {
                                SealStampView(
                                    name: editingSealName,
                                    style: SealStampStyle(rawValue: selectedSealStyleRawValue) ?? .zhuwen,
                                    size: 76
                                )
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        Text(AppLanguage.copy("字體", "Typefaces").poemScript(script))
                            .font(typeface.smallFont)
                            .foregroundStyle(Color.mutedInk)

                        if AppLanguage.isEnglish {
                            LazyVGrid(
                                columns: [GridItem(.adaptive(minimum: 94), spacing: 14)],
                                alignment: .leading,
                                spacing: 18
                            ) {
                                ForEach(PoemTypeface.allCases) { option in
                                    typefaceOption(option, usesEnglishLayout: true)
                                }
                            }
                        } else {
                            HStack(alignment: .top, spacing: 28) {
                                ForEach(PoemTypeface.allCases) { option in
                                    typefaceOption(option, usesEnglishLayout: false)
                                }
                            }
                        }
                    }

                    ScriptStylePicker(selectedRawValue: $selectedScriptRawValue)

                    ShadowStylePicker {
                        paywallReason = $0
                    }

                    SettingsNavigationRow(title: AppLanguage.copy("關於", "About"), mark: "息") {
                        showsAbout = true
                    }
                }
                .padding(.top, 28)
                .padding(.horizontal, 30)
                .padding(.bottom, 30)
            }
            .scrollDismissesKeyboard(.interactively)
            .contentShape(Rectangle())
            .simultaneousGesture(
                TapGesture().onEnded {
                    sealNameFocused = false
                }
            )
        }
        .presentationDetents([.height(560)])
        .presentationDragIndicator(.hidden)
        .presentationBackground(.clear)
        .fullScreenCover(isPresented: $showsAbout) {
            AboutSettingsView()
        }
        .sheet(isPresented: $showsPremiumStatus) {
            PremiumStatusView()
        }
        .sheet(item: $paywallReason) { reason in
            PaywallView(reason: reason) {
                paywallReason = nil
            }
        }
        .onAppear {
            if !hasPremiumAccess && SealStampStyle(rawValue: selectedSealStyleRawValue)?.isFree == false {
                selectedSealStyleRawValue = SealStampStyle.zhuwen.rawValue
            }
            editingSealName = sealName
        }
        .onDisappear {
            sealName = normalizedSealName
        }
    }

    private var normalizedSealName: String {
        let trimmed = editingSealName.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasCJK = trimmed.contains { $0.isCJK }
        return String(trimmed.prefix(hasCJK ? 4 : 24))
    }

    private func typefaceOption(_ option: PoemTypeface, usesEnglishLayout: Bool) -> some View {
        Button {
            guard hasPremiumAccess || option.isFree else {
                paywallReason = .typeface
                return
            }
            selectedRawValue = option.rawValue
        } label: {
            VStack(spacing: usesEnglishLayout ? 8 : 14) {
                ZStack(alignment: .bottomTrailing) {
                    if usesEnglishLayout {
                        Text(option.displayName)
                            .font(.system(size: 14, weight: .medium, design: .serif))
                            .foregroundStyle(Color.ink)
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .frame(maxWidth: .infinity, minHeight: 48)
                    } else {
                        VerticalText(option.displayName, font: option.previewFont(size: 17), spacing: 6, forceVertical: true)
                    }

                    if !option.isFree {
                        PremiumCrownBadge()
                            .offset(x: 8, y: 5)
                    }
                }
                .padding(.trailing, !option.isFree && !usesEnglishLayout ? 10 : 0)

                SelectionIndicator(isSelected: selectedRawValue == option.rawValue, size: 23)
            }
            .frame(maxWidth: usesEnglishLayout ? .infinity : nil)
        }
        .buttonStyle(.plain)
    }
}

private struct SettingsNavigationRow: View {
    @Environment(\.poemTypeface) private var typeface
    @Environment(\.poemScript) private var script
    let title: String
    var mark: String = "入"
    let action: () -> Void

    var body: some View {
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

private struct AboutSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.poemTypeface) private var typeface
    @Environment(\.poemScript) private var script
    @State private var legalDocument: LegalDocument?
    @State private var showsContact = false

    var body: some View {
        NavigationStack {
            ZStack {
                PaperBackground()

                VStack(spacing: 0) {
                    HStack(alignment: .top) {
                        Text(AppLanguage.copy("關於", "About").poemScript(script))
                            .font(typeface.titleFont)
                            .foregroundStyle(Color.ink)
                        Spacer()
                        QuietBackButton(title: "返回") { dismiss() }
                    }
                    .padding(.horizontal, 30)
                    .padding(.top, 56)
                    .padding(.bottom, 28)

                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 22) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(AppLanguage.copy("织诗", "Woven Verse").poemScript(script))
                                    .font(typeface.titleFont)
                                    .foregroundStyle(Color.ink)
                                Text(AppLanguage.copy("以今日心緒，生成一首可收藏的古詩。", "Create a classical Chinese poem from what is on your mind today.").poemScript(script))
                                    .font(typeface.smallFont)
                                    .foregroundStyle(Color.mutedInk)
                            }
                            .padding(.bottom, 4)

                            aboutStaticRow(title: AppLanguage.copy("版本", "Version"), value: appVersionText, mark: "版")

                            aboutRow(title: AppLanguage.copy("用戶協議", "Terms of use"), mark: "約") {
                                legalDocument = .terms
                            }

                            aboutRow(title: AppLanguage.copy("隱私政策", "Privacy policy"), mark: "隱") {
                                legalDocument = .privacy
                            }

                            aboutRow(title: AppLanguage.copy("聯繫我們", "Contact us"), mark: "信") {
                                showsContact = true
                            }

                            aboutRow(title: AppLanguage.copy("評價", "Rate the app"), mark: "評") {
                                AppReviewPrompt.request()
                            }

                            ShareLink(item: AppLanguage.copy("我在用织诗，以今日心绪生成一首古诗。", "I'm using Woven Verse to create classical Chinese poetry.")) {
                                rowContent(title: AppLanguage.copy("分享給好友", "Share with friends"), value: nil, mark: "享")
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 30)
                        .padding(.bottom, 50)
                    }
                }
            }
            .navigationBarHidden(true)
            .navigationDestination(item: $legalDocument) { document in
                LegalDocumentView(document: document)
            }
            .navigationDestination(isPresented: $showsContact) {
                ContactSettingsView()
            }
        }
    }

    private var appVersionText: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    private func aboutRow(title: String, mark: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            rowContent(title: title, value: nil, mark: mark)
        }
        .buttonStyle(.plain)
    }

    private func aboutStaticRow(title: String, value: String, mark: String) -> some View {
        rowContent(title: title, value: value, mark: mark)
    }

    private func rowContent(title: String, value: String?, mark: String) -> some View {
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

            if let value {
                Text(value.poemScript(script))
                    .font(typeface.tinySealFont)
                    .foregroundStyle(Color.mutedInk)
            } else {
                Text("›")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(Color.cinnabar.opacity(0.78))
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
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
                    contactRow(title: AppLanguage.copy("郵箱", "Email"), value: "raowenjieszu@gmail.com", mark: "郵") {
                        if let url = URL(string: "mailto:raowenjieszu@gmail.com?subject=织诗") {
                            openURL(url)
                        }
                    }

                    contactRow(title: AppLanguage.copy("小紅書", "Xiaohongshu"), value: "织诗", mark: "書") {
                        if let url = URL(string: "https://www.xiaohongshu.com/user/profile/608e5e7500000000010050c2") {
                            openURL(url)
                        }
                    }
                }
                .padding(.horizontal, 30)

                Spacer()
            }
        }
        .navigationBarHidden(true)
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
                Welcome to Woven Verse. By downloading, installing, or using the app, you agree to these terms.

                Woven Verse helps you create classical Chinese poetry. You choose imagery and select AI-generated candidate lines to shape a poem.

                You own the poems you create in the app and may use, share, or publish them. AI-generated lines may resemble other works, so we do not guarantee that a poem is unique.

                Do not use the app to create unlawful content or content that infringes another person's rights. Do not reverse engineer, decompile, or disassemble the app.

                The app relies on third-party AI services to generate candidate lines. Those services are provided as is, without express or implied warranties.

                We may update these terms. Continued use after an update means you accept the revised terms.

                Full terms: https://jackyrwj.github.io/Poetry/terms-en.html

                Contact: raowenjieszu@gmail.com
                """
            case .privacy:
                return """
                Woven Verse respects your privacy.

                With your permission, the app uses only your city name to add a place to a poem's inscription. It does not record precise coordinates or keep location history. You can turn off location access in Settings at any time.

                Your poems, preferences, and saved work are stored on your device. They are not uploaded to our servers.

                To generate candidate lines or AI commentary, the app sends the relevant imagery, poem text, and author information to a third-party AI service. These requests do not include your name, location, or other direct identifiers.

                The app does not collect advertising identifiers and does not include advertising, analytics, or social-media SDKs. We do not sell personal information.

                Full privacy policy: https://jackyrwj.github.io/Poetry/privacy-en.html

                Contact: raowenjieszu@gmail.com
                """
            }
        }

        switch self {
        case .terms:
            return """
            歡迎使用「織詩」。下載、安裝或使用本應用即表示你同意以下條款。

            本應用是一款古典中文詩歌創作輔助工具，用戶通過選擇意境，借助 AI 技術生成候選詩句，逐句擇選完成詩歌創作。

            你通過本應用創作的詩歌作品歸你所有，可自由使用、分享和發佈。但 AI 輔助生成的詩句可能與其他用戶的創作存在相似之處，本應用不對內容的獨創性作出保證。

            使用本應用時，請勿生成違反法律法規或侵犯他人權益的內容，不得對本應用進行逆向工程、反編譯或反匯編。

            本應用依賴第三方 AI 服務生成詩句內容，按「現狀」提供，不作任何明示或暗示的保證。

            我們可能會不時更新本協議。更新後繼續使用，即表示你接受更新內容。

            完整協議：https://jackyrwj.github.io/Poetry/terms.html

            聯繫郵箱：raowenjieszu@gmail.com
            """
        case .privacy:
            return """
            「織詩」重視你的隱私。

            經你明確授權後，本應用僅獲取你所在城市的名稱，用於在詩歌落款處顯示創作地點。我們不會記錄你的精確地理坐標，也不會存儲你的位置歷史。你可以隨時在系統設置中關閉位置權限。

            你在應用內的所有創作數據均存儲在設備本地，不會上傳至任何伺服器。我們無法訪問你的創作內容。

            為生成候選詩句，本應用會將你選擇的意境描述發送至第三方 AI 服務（阿里雲百煉／通義千問）。這些請求不包含你的姓名、位置或其他個人身份信息。

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

private struct ShadowStylePicker: View {
    @Environment(\.poemTypeface) private var typeface
    @Environment(\.poemScript) private var script
    @AppStorage(ShadowStyle.storageKey) private var selectedShadowRaw = ShadowStyle.morning.rawValue
    @AppStorage(PoemBackground.storageKey) private var selectedBgRaw = PoemBackground.defaultBackground.rawValue
    @ObservedObject private var store = StoreManager.shared
    let requestPremium: (PaywallReason) -> Void

    /// Is the current selection a shadow effect (vs a background image)?
    private var isShadowSelected: Bool {
        let background = PoemBackground(rawValue: selectedBgRaw)
        return background == PoemBackground.none || background == nil
    }

    private var selectedBackground: PoemBackground? {
        PoemBackground(rawValue: selectedBgRaw)
    }

    private var hasPremiumAccess: Bool {
        store.isPremium
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text(AppLanguage.copy("紙面", "Paper").poemScript(script))
                    .font(typeface.smallFont)
                    .foregroundStyle(Color.mutedInk)

                // Show premium badge for image backgrounds
                if selectedBackground?.isPremium == true {
                    Text("雅".poemScript(script))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.cinnabar.opacity(0.75)))
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    // Shadow effects
                    ForEach(ShadowStyle.visibleCases) { style in
                        Button {
                            withAnimation(.easeOut(duration: 0.25)) {
                                selectedShadowRaw = style.rawValue
                                selectedBgRaw = PoemBackground.none.rawValue
                            }
                            SensoryFeedback.lightTap()
                        } label: {
                            let isActive = isShadowSelected && selectedShadowRaw == style.rawValue
                            VStack(spacing: 8) {
                                ZStack(alignment: .bottomTrailing) {
                                    ShadowPreviewTile(style: style)
                                        .frame(width: 52, height: 72)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .stroke(
                                                    isActive ? Color.cinnabar : Color.mutedInk.opacity(0.3),
                                                    lineWidth: isActive ? 1.5 : 0.8
                                                )
                                        )

                                    if isActive {
                                        SelectionIndicator(size: 18)
                                            .offset(x: 5, y: 5)
                                            .transition(.scale(scale: 0.75).combined(with: .opacity))
                                    }
                                }
                                Text(style.displayName.poemScript(script))
                                    .font(typeface.tinySealFont)
                                    .foregroundStyle(isActive ? Color.ink : Color.mutedInk)
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    // Divider
                    Rectangle()
                        .fill(Color.mutedInk.opacity(0.2))
                        .frame(width: 0.5, height: 60)

                    // Background images
                    ForEach(PoemBackground.imageBackgrounds) { bg in
                        Button {
                            guard hasPremiumAccess || !bg.isPremium else {
                                requestPremium(.background)
                                return
                            }
                            withAnimation(.easeOut(duration: 0.25)) {
                                selectedBgRaw = bg.rawValue
                            }
                            SensoryFeedback.lightTap()
                        } label: {
                            let isActive = selectedBgRaw == bg.rawValue
                            VStack(spacing: 8) {
                                ZStack(alignment: .bottomTrailing) {
	                                    if let imageName = bg.imageName {
	                                        Image(imageName)
	                                            .resizable()
	                                            .scaledToFill()
		                                            .frame(width: 52, height: 72)
		                                            .clipShape(RoundedRectangle(cornerRadius: 6))
	                                    }

                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(
                                            isActive ? Color.cinnabar : Color.mutedInk.opacity(0.3),
                                            lineWidth: isActive ? 1.5 : 0.8
                                        )
                                        .frame(width: 52, height: 72)

                                    if isActive {
                                        SelectionIndicator(size: 18)
                                            .offset(x: bg.isPremium ? -27 : 5, y: 5)
                                            .transition(.scale(scale: 0.75).combined(with: .opacity))
                                    }

                                    if bg.isPremium {
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
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 2)
            }
        }
        .onAppear {
            PoemBackground.migrateDefaultToBoatIfNeeded(selectedBgRaw: &selectedBgRaw)
            if selectedShadowRaw == ShadowStyle.none.rawValue {
                selectedShadowRaw = ShadowStyle.morning.rawValue
            }
            if selectedBackground?.isPremium == true && !hasPremiumAccess {
                selectedBgRaw = PoemBackground.freeImageBackgrounds.first?.rawValue ?? PoemBackground.none.rawValue
            }
        }
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

 private struct ShadowPreviewTile: View {
    let style: ShadowStyle

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let previewScale = max(0.12, min(size.width, size.height) / 360)
                ShadowRenderer.draw(style: style, context: &context, size: size, t: t, scale: previewScale)
            }
        }
        .background(Color.white)
    }
}

private enum PoemTextLayout {
    static let storageKey = "poemUsesVerticalText"
}

private struct PoemTextLayoutPicker: View {
    @Environment(\.poemScript) private var script
    @AppStorage(PoemTextLayout.storageKey) private var usesVerticalText = false

    var body: some View {
        Picker(AppLanguage.copy("詩句排版", "Text layout"), selection: $usesVerticalText) {
            Text(AppLanguage.copy("橫排", "Horizontal").poemScript(script)).tag(false)
            Text(AppLanguage.copy("豎排", "Vertical").poemScript(script)).tag(true)
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 240)
        .accessibilityLabel(AppLanguage.copy("詩句排版", "Poem text layout"))
    }
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

struct PoemSharePreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.poemTypeface) private var typeface
    @Environment(\.poemScript) private var script
    @Environment(\.spotlightGuide) private var spotlightGuide
    @AppStorage(SealStampView.storageKey) private var sealName = ""
    @AppStorage(PoemTextLayout.storageKey) private var usesVerticalText = false
    @State private var selectedBgRaw: String
    let imageTitle: String
    let lines: [String]
    let locationMark: String?
    let lunarDateText: String
    let dayPeriodText: String

    init(imageTitle: String, lines: [String], locationMark: String?, lunarDateText: String, dayPeriodText: String) {
        self.imageTitle = imageTitle
        self.lines = lines
        self.locationMark = locationMark
        self.lunarDateText = lunarDateText
        self.dayPeriodText = dayPeriodText
        let stored = UserDefaults.standard.string(forKey: PoemBackground.storageKey) ?? PoemBackground.defaultBackground.rawValue
        self._selectedBgRaw = State(initialValue: stored)
    }

    @State private var preparedShareItems: [String: PreparedShareItem] = [:]
    @State private var previewLayout: ShareArtworkLayout?
    @State private var paywallReason: PaywallReason?

    private var selectedBg: PoemBackground {
        PoemBackground(rawValue: selectedBgRaw) ?? .none
    }

    private var layouts: [ShareArtworkLayout] {
        [.portrait, .landscape]
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack(alignment: .top) {
                    Text(AppLanguage.copy("分享", "Share").poemScript(script))
                        .font(typeface.titleFont)
                        .foregroundStyle(Color.ink)
                    Spacer()
                    QuietBackButton(title: "返回") { dismiss() }
                }
                .padding(.horizontal, 30)
                .padding(.top, 56)
                .padding(.bottom, 18)

                PoemTextLayoutPicker()
                    .padding(.bottom, 14)

                ShareSurfacePicker(selectedBgRaw: $selectedBgRaw) {
                    paywallReason = $0
                }
                    .padding(.bottom, 14)

                ScrollView {
                    VStack(spacing: 28) {
                        ForEach(layouts) { layout in
                            let key = "\(layout.rawValue)-\(selectedBgRaw)-\(usesVerticalText)"
                            let preparedItem = preparedShareItems[key]
                            let ready = preparedItem != nil

                            SharePreviewCard(
                                layout: layout,
                                imageTitle: imageTitle,
                                lines: lines,
                                locationMark: locationMark,
                                lunarDateText: lunarDateText,
                                dayPeriodText: dayPeriodText,
                                background: selectedBg,
                                shareItem: preparedItem,
                                isSpotlightTarget: spotlightGuide.step == .tapShareButton && layout == layouts.first && ready,
                                onTapPreview: { previewLayout = layout }
                            )
                            .opacity(ready ? 1 : 0.55)
                        }
                    }
                    .padding(.horizontal, 30)
                    .padding(.bottom, 36)
                }
            }

            // Fullscreen preview overlay
            if let layout = previewLayout {
                ShareFullscreenPreview(
                    layout: layout,
                    imageTitle: imageTitle,
                    lines: lines,
                    locationMark: locationMark,
                    lunarDateText: lunarDateText,
                    dayPeriodText: dayPeriodText,
                    background: selectedBg,
                    onDismiss: { previewLayout = nil }
                )
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.25), value: previewLayout != nil)
        .task(id: "\(selectedBgRaw)-\(usesVerticalText)") {
            await renderShareImages()
        }
        .sheet(item: $paywallReason) { reason in
            PaywallView(reason: reason) {
                paywallReason = nil
            }
        }
        .spotlightOverlay(for: [.selectBackground, .tapShareButton, .returnFromShare])
    }

    @MainActor
    private func renderShareImages() async {
        for layout in layouts {
            guard !Task.isCancelled else { return }
            await renderShareImage(for: layout)
        }
    }

    @MainActor
    private func renderShareImage(for layout: ShareArtworkLayout) async {
        let size = layout.canvasSize
        let renderer = ImageRenderer(
            content: SharePoemArtwork(
                layout: layout,
                imageTitle: imageTitle,
                lines: lines,
                locationMark: locationMark,
                lunarDateText: lunarDateText,
                dayPeriodText: dayPeriodText,
                sealName: sealName,
                showsLight: true,
                showsSeal: !sealName.isEmpty,
                showsTitle: true,
                background: selectedBg
            )
            .environment(\.poemTypeface, typeface)
            .environment(\.poemScript, script)
            .frame(width: size.width, height: size.height)
        )
        renderer.scale = 1

        guard let image = renderer.uiImage else { return }

        let key = "\(layout.rawValue)-\(selectedBgRaw)-\(usesVerticalText)"
        let url = await Task.detached(priority: .userInitiated) {
            guard let data = image.jpegData(compressionQuality: 0.92) else { return nil as URL? }
            let fileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("poem-share-\(key)-\(UUID().uuidString).jpg")
            do {
                try data.write(to: fileURL, options: .atomic)
                return fileURL
            } catch {
                return nil
            }
        }.value

        guard !Task.isCancelled else { return }
        if let url {
            preparedShareItems[key] = PreparedShareItem(
                url: url,
                controller: SharePresenter.makeController(url: url)
            )
        }
    }
}

private struct PreparedShareItem {
    let url: URL
    let controller: UIActivityViewController
}

/// Unified surface picker for the share page — same design as the settings picker.
private struct ShareSurfacePicker: View {
    @Environment(\.poemTypeface) private var typeface
    @Environment(\.poemScript) private var script
    @Environment(\.spotlightGuide) private var spotlightGuide
    @AppStorage(ShadowStyle.storageKey) private var selectedShadowRaw = ShadowStyle.morning.rawValue
    @ObservedObject private var store = StoreManager.shared
    @Binding var selectedBgRaw: String
    let requestPremium: (PaywallReason) -> Void

    private var isShadowSelected: Bool {
        let background = PoemBackground(rawValue: selectedBgRaw)
        return background == PoemBackground.none || background == nil
    }

    private var hasPremiumAccess: Bool {
        store.isPremium
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(AppLanguage.copy("紙面", "Paper").poemScript(script))
                .font(typeface.smallFont)
                .foregroundStyle(Color.mutedInk)
                .padding(.horizontal, 30)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    // Shadow effects
                    ForEach(ShadowStyle.visibleCases) { style in
                        Button {
                            withAnimation(.easeOut(duration: 0.25)) {
                                selectedShadowRaw = style.rawValue
                                selectedBgRaw = PoemBackground.none.rawValue
                            }
                            SensoryFeedback.lightTap()
                        } label: {
                            let isActive = isShadowSelected && selectedShadowRaw == style.rawValue
                            VStack(spacing: 8) {
                                ZStack(alignment: .bottomTrailing) {
                                    ShadowPreviewTile(style: style)
                                        .frame(width: 52, height: 72)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .stroke(
                                                    isActive ? Color.cinnabar : Color.mutedInk.opacity(0.3),
                                                    lineWidth: isActive ? 1.5 : 0.8
                                                )
                                        )

                                    if isActive {
                                        SelectionIndicator(size: 18)
                                            .offset(x: 5, y: 5)
                                            .transition(.scale(scale: 0.75).combined(with: .opacity))
                                    }
                                }
                                Text(style.displayName.poemScript(script))
                                    .font(typeface.tinySealFont)
                                    .foregroundStyle(isActive ? Color.ink : Color.mutedInk)
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    Rectangle()
                        .fill(Color.mutedInk.opacity(0.2))
                        .frame(width: 0.5, height: 60)

	                    // Background images
	                    ForEach(PoemBackground.imageBackgrounds) { bg in
	                        let isSpotlightTarget = spotlightGuide.step == .selectBackground && bg == PoemBackground.freeImageBackgrounds.first
                        Button {
                            guard hasPremiumAccess || !bg.isPremium else {
                                requestPremium(.background)
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
                            let isActive = selectedBgRaw == bg.rawValue
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

                                    if isActive {
                                        SelectionIndicator(size: 18)
                                            .offset(x: bg.isPremium ? -27 : 5, y: 5)
                                            .transition(.scale(scale: 0.75).combined(with: .opacity))
                                    }

                                    if bg.isPremium {
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
	                    }
                }
                .padding(.horizontal, 30)
                .padding(.vertical, 2)
            }
        }
        .onAppear {
            if selectedShadowRaw == ShadowStyle.none.rawValue {
                selectedShadowRaw = ShadowStyle.morning.rawValue
            }
            if PoemBackground(rawValue: selectedBgRaw)?.isPremium == true && !hasPremiumAccess {
                selectedBgRaw = PoemBackground.freeImageBackgrounds.first?.rawValue ?? PoemBackground.none.rawValue
            }
        }
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
    @Environment(\.poemTypeface) private var typeface
    @Environment(\.poemScript) private var script
    @Environment(\.spotlightGuide) private var spotlightGuide
    @AppStorage(SealStampView.storageKey) private var sealName = ""
    let layout: ShareArtworkLayout
    let imageTitle: String
    let lines: [String]
    let locationMark: String?
    let lunarDateText: String
    let dayPeriodText: String
    var background: PoemBackground = .none
    var shareItem: PreparedShareItem?
    var isSpotlightTarget: Bool = false
    var onTapPreview: (() -> Void)?

    var body: some View {
        let canvasSize = layout.canvasSize
        let maxPreviewWidth: CGFloat = layout == .landscape ? 310 : 260
        let scale = maxPreviewWidth / canvasSize.width
        let previewHeight = canvasSize.height * scale

        VStack(alignment: .leading, spacing: 14) {
            Button {
                onTapPreview?()
            } label: {
                SharePoemArtwork(
                    layout: layout,
                    imageTitle: imageTitle,
                    lines: lines,
                    locationMark: locationMark,
                    lunarDateText: lunarDateText,
                    dayPeriodText: dayPeriodText,
                    sealName: sealName,
                    showsLight: true,
                    showsSeal: !sealName.isEmpty,
                    showsTitle: true,
                    background: background
                )
                .frame(width: canvasSize.width, height: canvasSize.height)
                .scaleEffect(scale)
                .frame(width: maxPreviewWidth, height: previewHeight)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .shadow(color: Color.black.opacity(0.10), radius: 6, x: 0, y: 3)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)

            HStack {
                Text(layout.label.poemScript(script))
                    .font(typeface.bodyFont)
                    .foregroundStyle(Color.ink)

                Spacer()

                if let shareItem {
                    Button {
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
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 16)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.94))
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
    @AppStorage(SealStampView.storageKey) private var sealName = ""
    let layout: ShareArtworkLayout
    let imageTitle: String
    let lines: [String]
    let locationMark: String?
    let lunarDateText: String
    let dayPeriodText: String
    var background: PoemBackground = .none
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
                    SharePoemArtwork(
                        layout: layout,
                        imageTitle: imageTitle,
                        lines: lines,
                        locationMark: locationMark,
                        lunarDateText: lunarDateText,
                        dayPeriodText: dayPeriodText,
                        sealName: sealName,
                        showsLight: true,
                        showsSeal: !sealName.isEmpty,
                        showsTitle: true,
                        background: background
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

    private var usesVerticalText: Bool {
        usesVerticalTextOverride ?? storedUsesVerticalText
    }

    private var poemLineSpacing: CGFloat {
        lines.count > 4 ? 44 : 64
    }

    private var poemFontSize: CGFloat {
        lines.count > 4 ? 42 : 58
    }

    private var poemCharacterSpacing: CGFloat {
        lines.count > 4 ? 15 : 19
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
                DappledShadowView()
                    .opacity(0.64)
            }

            if usesVerticalText {
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
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 36) {
                Spacer()
                HStack(alignment: .top, spacing: 14) {
                    VerticalText(lunarDateText, font: typeface.font(size: 28), color: .mutedInk, spacing: 10)
                    if let locationMark {
                        VerticalText(compactInscriptionText(locationMark), font: typeface.font(size: 28), color: .mutedInk, spacing: 10)
                    }
                }
                if showsSeal && !sealName.isEmpty {
                    SealStampView(name: sealName, size: 104)
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottomLeading)

            Spacer(minLength: 40)

            HStack(alignment: .top, spacing: lines.count > 4 ? 34 : 54) {
                // Traditional Chinese verse is read top-to-bottom, beginning
                // with the rightmost column and continuing toward the left.
                ForEach(Array(lines.indices.reversed()), id: \.self) { index in
                    VerticalText(lines[index], font: typeface.font(size: poemFontSize), spacing: poemCharacterSpacing)
                }
                if showsTitle {
                    // The title is the rightmost, first-read column.
                    VerticalText(imageTitle, font: typeface.font(size: 44), color: .mutedInk, spacing: 16)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, layout == .portrait ? 90 : 110)
        .padding(.vertical, layout == .portrait ? 160 : 130)
    }

    private var portraitBody: some View {
        VStack(alignment: .leading, spacing: lines.count > 4 ? 34 : 52) {
            if showsTitle {
                Text(imageTitle.poemScript(script))
                    .font(typeface.font(size: 68))
                    .foregroundStyle(Color.mutedInk)
                    .padding(.bottom, 28)
            }
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line.poemScript(script))
                    .font(typeface.font(size: lines.count > 4 ? 56 : 72))
                    .foregroundStyle(Color.ink)
            }
            Spacer(minLength: 0)
            HStack(alignment: .bottom) {
                inscription
                Spacer()
                if showsSeal && !sealName.isEmpty {
                    SealStampView(name: sealName, size: 118)
                }
            }
        }
        .padding(.horizontal, 110)
        .padding(.top, 165)
        .padding(.bottom, 125)
    }

    private var landscapeBody: some View {
        VStack(alignment: .leading, spacing: lines.count > 4 ? 17 : 42) {
            if showsTitle {
                Text(imageTitle.poemScript(script))
                    .font(typeface.font(size: 62))
                    .foregroundStyle(Color.mutedInk)
                    .padding(.bottom, 14)
            }
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line.poemScript(script))
                    .font(typeface.font(size: lines.count > 4 ? 48 : 66))
                    .foregroundStyle(Color.ink)
            }
            HStack(alignment: .bottom, spacing: 44) {
                inscription
                if showsSeal && !sealName.isEmpty {
                    SealStampView(name: sealName, size: 104)
                }
            }
        }
        .fixedSize(horizontal: true, vertical: true)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.horizontal, 120)
        .padding(.top, 108)
        .padding(.bottom, 85)
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

private struct SealStampView: View {
    static let storageKey = "sealName"

    @AppStorage(SealStampStyle.storageKey) private var storedStyleRawValue = SealStampStyle.zhuwen.rawValue
    @AppStorage(NameTransliterator.overrideStorageKey) private var transliterationOverride = ""

    let name: String
    var style: SealStampStyle? = nil
    let size: CGFloat

    private var resolvedStyle: SealStampStyle {
        style ?? SealStampStyle(rawValue: storedStyleRawValue) ?? .zhuwen
    }

    private var sealChars: [String] {
        if let glyphs = NameTransliterator.glyphs(for: name, storedOverride: transliterationOverride) {
            return glyphs.map(\.value)
        }
        let chars = Array(Self.simplifiedSealText(name)).map(String.init)
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

private struct ChoiceColumn: View {
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

private struct VerticalText: View {
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

private struct SealButton: View {
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

private struct SealTextButton: View {
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

private enum SensoryFeedback {
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

private struct PoemDateText {
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

private struct PoemInscriptionDate {
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
    @AppStorage(ShadowStyle.storageKey) private var shadowStyleRaw = ShadowStyle.morning.rawValue
    @AppStorage(PoemBackground.storageKey) private var backgroundRawValue = PoemBackground.defaultBackground.rawValue

    private var shadowStyle: ShadowStyle {
        ShadowStyle(rawValue: shadowStyleRaw) ?? .morning
    }

    private var background: PoemBackground {
        PoemBackground(rawValue: backgroundRawValue) ?? PoemBackground.defaultBackground
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
                DappledShadowView()
                    .id(shadowStyleRaw)
                    .opacity(shadowStyle.paperOpacity)
                    .ignoresSafeArea()
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.35), value: shadowStyleRaw)
        .animation(.easeOut(duration: 0.35), value: backgroundRawValue)
    }
}

private extension Color {
    static let paper = Color.white
    static let rice = Color(red: 0.94, green: 0.91, blue: 0.84)
    static let ink = Color(red: 0.08, green: 0.075, blue: 0.07)
    static let mutedInk = Color(red: 0.34, green: 0.32, blue: 0.29)
    static let cinnabar = Color(red: 0.77, green: 0.02, blue: 0.06)
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

private extension CharacterSet {
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

    var displayName: String {
        switch self {
        case .wenyue:
            return AppLanguage.copy("文悦仿宋", "Wenyue FangSong")
        case .wenkai:
            return AppLanguage.copy("霞鹜文楷", "LXGW WenKai")
        case .songti:
            return AppLanguage.copy("思源宋体", "Source Han Serif")
        case .kaiti:
            return AppLanguage.copy("汇文明朝体", "Huiwen Mincho")
        case .mashan:
            return AppLanguage.copy("马善政体", "Ma Shan Zheng")
        case .xiaozhuan:
            return AppLanguage.copy("方正小篆", "FZ Small Seal")
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
