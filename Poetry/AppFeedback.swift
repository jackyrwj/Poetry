import AVFoundation
import MessageUI
import SwiftUI
import UIKit
import WidgetKit

private extension Color {
    static let ink = Color(red: 0.08, green: 0.075, blue: 0.07)
    static let mutedInk = Color(red: 0.34, green: 0.32, blue: 0.29)
    static let cinnabar = Color(red: 0.77, green: 0.02, blue: 0.06)
}

enum AppStoreLinks {
    static let appID = "6777856347"
    static let appPage = "https://apps.apple.com/app/id\(appID)"
    static let writeReview = "\(appPage)?action=write-review"

    static func openWriteReview() {
        guard let url = URL(string: writeReview) else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - Developer Letter

/// 設置裡「開發者的一封信」：先讀開發者的一封信，再由讀者自己決定去 App Store 評價或寫信。
/// 兩個入口對所有人都一樣顯示，不按滿意度分流（App Store 審核指南 5.6.1）。
struct DeveloperLetterView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.poemTypeface) private var typeface
    @Environment(\.poemScript) private var script
    @State private var showsMailComposer = false

    private var paragraphs: [String] {
        AppLanguage.isEnglish
            ? [
                "Hi, I'm Jacky, the developer of Ink & Verse. I build and maintain it on my own, in my spare time.",
                "If a poem here has kept you company, would you spend ten seconds leaving a few words on the App Store? I read every review, and each one helps someone else find these poems.",
                "Thank you for reading with me, and for reading this far."
            ]
            : [
                "你好，我是 Jacky，诗客的开发者。这个 App 是我一个人利用业余时间做的。",
                "如果某一首诗曾在某个时刻陪过你，能不能花十秒在 App Store 留一句话？每一条评价我都会认真看，也能让更多人读到这些诗。",
                "谢谢你愿意在这里读诗，也谢谢你读到这里。"
            ]
    }

    var body: some View {
        ZStack {
            PaperBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    HStack(alignment: .top) {
                        Text(AppLanguage.copy("致讀者的一封信", "A letter to readers").poemScript(script))
                            .font(typeface.titleFont)
                            .foregroundStyle(Color.ink)
                        Spacer()
                        QuietBackButton(title: "關閉") { dismiss() }
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(Array(paragraphs.enumerated()), id: \.offset) { index, paragraph in
                            Text(paragraph.poemScript(script))
                                .font(typeface.bodyFont)
                                .foregroundStyle(index == paragraphs.count - 1 ? Color.cinnabar : Color.ink)
                                .lineSpacing(7)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Text(AppLanguage.copy("—— Jacky", "— Jacky").poemScript(script))
                            .font(typeface.smallFont)
                            .foregroundStyle(Color.mutedInk)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .padding(.top, 4)
                    }
                    .padding(22)
                    .background {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.white.opacity(0.62))
                            .stroke(Color.mutedInk.opacity(0.18), lineWidth: 0.8)
                    }

                    Button(action: AppStoreLinks.openWriteReview) {
                        Label(AppLanguage.copy("去 App Store 評價", "Review on the App Store").poemScript(script), systemImage: "star.fill")
                            .font(typeface.bodyFont)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Color.cinnabar, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)

                    VStack(spacing: 6) {
                        Text(AppLanguage.copy("有不滿意的地方？", "Something not quite right?").poemScript(script))
                            .foregroundStyle(Color.mutedInk)
                        Button {
                            FeedbackMail.compose(showComposer: $showsMailComposer)
                        } label: {
                            Text(AppLanguage.copy("直接寫信給我，我會親自回覆", "Write to me directly. I reply to every email.").poemScript(script))
                                .foregroundStyle(Color.ink)
                                .underline()
                        }
                        .buttonStyle(.plain)
                    }
                    .font(typeface.smallFont)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 26)
                .padding(.top, 32)
                .padding(.bottom, 40)
            }
        }
        .sheet(isPresented: $showsMailComposer) {
            FeedbackMailComposer()
                .ignoresSafeArea()
        }
    }
}

// MARK: - Feedback Mail

enum FeedbackMail {
    static let recipient = "raowenjieszu@gmail.com"

    static var subject: String {
        AppLanguage.copy("诗客反馈", "Ink & Verse feedback") + " v\(appVersion)"
    }

    /// 留出空行給讀者寫內容，末尾附上排查問題需要的環境信息。
    static var body: String {
        """


        ——
        \(AppLanguage.copy("App 版本", "App version")): \(appVersion) (\(buildNumber))
        iOS: \(UIDevice.current.systemVersion)
        \(AppLanguage.copy("设备", "Device")): \(deviceModel)
        """
    }

    static var mailtoURL: URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = recipient
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body)
        ]
        return components.url
    }

    /// 優先用系統寫信界面；沒配置郵件賬戶時退回 mailto:（可能打開 Gmail 等），都不行就複製地址。
    static func compose(showComposer: Binding<Bool>, onCopied: @escaping () -> Void = {}) {
        if MFMailComposeViewController.canSendMail() {
            showComposer.wrappedValue = true
        } else if let url = mailtoURL {
            UIApplication.shared.open(url) { opened in
                guard !opened else { return }
                UIPasteboard.general.string = recipient
                onCopied()
            }
        } else {
            UIPasteboard.general.string = recipient
            onCopied()
        }
    }

    private static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private static var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    /// 機型標識，如 iPhone17,1。
    private static var deviceModel: String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}

struct FeedbackMailComposer: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(dismiss: dismiss)
    }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients([FeedbackMail.recipient])
        controller.setSubject(FeedbackMail.subject)
        controller.setMessageBody(FeedbackMail.body, isHTML: false)
        return controller
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        private let dismiss: DismissAction

        init(dismiss: DismissAction) {
            self.dismiss = dismiss
        }

        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            dismiss()
        }
    }
}

// MARK: - Widget Guide

/// iOS has no API to add a widget for the reader, so the app shows how:
/// at most twice, starting on the second day the reader opens the app,
/// and any time from Settings.
enum WidgetGuide {
    private static let promptCountKey = "poetry.widgetGuidePromptCount"
    private static let lastPromptKey = "poetry.widgetGuideLastPrompt"
    private static let optOutKey = "poetry.widgetGuideOptOut"
    private static let activeDaysKey = "poetry.activeDayCount"
    private static let lastActiveDayKey = "poetry.lastActiveDay"
    private static let maxPrompts = 2
    private static let minimumActiveDays = 2
    private static let minIntervalBetweenPrompts: TimeInterval = 5 * 24 * 3600

    /// Counts distinct days the app was opened; called when the scene turns active.
    static func recordActiveDay() {
        let defaults = UserDefaults.standard
        let today = Calendar.current.startOfDay(for: .now).timeIntervalSince1970
        guard defaults.double(forKey: lastActiveDayKey) != today else { return }
        defaults.set(today, forKey: lastActiveDayKey)
        defaults.set(defaults.integer(forKey: activeDaysKey) + 1, forKey: activeDaysKey)
    }

    /// Frequency cap for the automatic prompt; does not check installed widgets.
    static var canPrompt: Bool {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: optOutKey),
              defaults.integer(forKey: activeDaysKey) >= minimumActiveDays,
              defaults.integer(forKey: promptCountKey) < maxPrompts,
              !AppReviewPrompt.wasRequestedRecently else { return false }
        let last = defaults.double(forKey: lastPromptKey)
        return last == 0 || Date().timeIntervalSince1970 - last >= minIntervalBetweenPrompts
    }

    static func isInstalled() async -> Bool {
        await withCheckedContinuation { continuation in
            WidgetCenter.shared.getCurrentConfigurations { result in
                let kinds = (try? result.get())?.map(\.kind) ?? []
                continuation.resume(returning: kinds.contains(DailyPoemWidgetStore.widgetKind))
            }
        }
    }

    static func recordPrompt() {
        let defaults = UserDefaults.standard
        defaults.set(defaults.integer(forKey: promptCountKey) + 1, forKey: promptCountKey)
        defaults.set(Date().timeIntervalSince1970, forKey: lastPromptKey)
    }

    static func optOut() {
        UserDefaults.standard.set(true, forKey: optOutKey)
    }
}

struct WidgetGuideView: View {
    /// Shown automatically (offers "don't show again") rather than opened from Settings.
    var isPrompt = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.poemTypeface) private var typeface
    @Environment(\.poemScript) private var script

    var body: some View {
        ZStack {
            PaperBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(AppLanguage.copy("桌面小組件", "Home Screen widget").poemScript(script))
                                .font(typeface.titleFont)
                                .foregroundStyle(Color.ink)
                            Text(AppLanguage.copy("不必打開 App，每天在桌面讀一首詩。", "A new poem on your Home Screen every day, no need to open the app.").poemScript(script))
                                .font(typeface.smallFont)
                                .foregroundStyle(Color.mutedInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        QuietBackButton(title: "關閉") { dismiss() }
                    }

                    preview

                    VStack(alignment: .leading, spacing: 16) {
                        Text(AppLanguage.copy("添加方法", "How to add it").poemScript(script))
                            .font(typeface.bodyFont)
                            .foregroundStyle(Color.ink)
                        // Framed like a phone so the zoomed-in shots still read as a screen.
                        LoopingVideo(resource: "WidgetGuide")
                            .aspectRatio(640.0 / 1386.0, contentMode: .fit)
                            .frame(height: 380)
                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                            .padding(5)
                            .background(Color.ink, in: RoundedRectangle(cornerRadius: 27, style: .continuous))
                            .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                            .accessibilityHidden(true)
                        step(1, AppLanguage.copy("回到桌面，長按空白處，直到圖標開始晃動", "On your Home Screen, touch and hold an empty area until the apps jiggle"))
                        step(2, AppLanguage.copy("點左上角的「編輯」，再點「添加小組件」", "Tap Edit in the top-left corner, then Add Widget"))
                        step(3, AppLanguage.copy("搜索「诗客」，選好尺寸後添加", "Search for Ink & Verse, choose a size, and add it"))
                        VStack(alignment: .leading, spacing: 8) {
                            Text(AppLanguage.copy("添加後長按小組件，點「編輯小組件」，可以固定顯示一首你收藏的詩。", "Once added, touch and hold the widget and tap Edit Widget to pin one of your saved poems.").poemScript(script))
                            Text(AppLanguage.copy("想每天讀新詩、又想留著最愛的那首？添加兩個诗客小組件，一個每日一首、一個固定收藏，把一個拖到另一個上面疊在一起，上下滑動就能切換。", "Want both a daily poem and a favorite? Add two Ink & Verse widgets, one daily and one pinned, then drag one onto the other to stack them and swipe up or down to switch.").poemScript(script))
                            Text(AppLanguage.copy("鎖定畫面也可以添加，同樣在「自定」裡找到诗客。", "It also works on the Lock Screen: look for Ink & Verse under Customize.").poemScript(script))
                        }
                        .font(typeface.tinySealFont)
                        .foregroundStyle(Color.mutedInk)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(20)
                    .background {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.white.opacity(0.55))
                            .stroke(Color.mutedInk.opacity(0.18), lineWidth: 0.8)
                    }

                    VStack(spacing: 4) {
                        Button {
                            dismiss()
                        } label: {
                            Text(AppLanguage.copy("知道了", "Got it").poemScript(script))
                                .font(typeface.bodyFont)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(Color.cinnabar, in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)

                        if isPrompt {
                            Button {
                                WidgetGuide.optOut()
                                dismiss()
                            } label: {
                                Text(AppLanguage.copy("不再提示", "Don't show again").poemScript(script))
                                    .font(typeface.smallFont)
                                    .foregroundStyle(Color.mutedInk)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 44)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 26)
                .padding(.top, 32)
                .padding(.bottom, 40)
            }
        }
    }

    /// The real medium widget, drawn with today's poem and the reader's settings.
    @ViewBuilder
    private var preview: some View {
        if let entry = previewEntry {
            DailyPoemWidgetView(entry: entry, family: .systemMedium)
                .padding(16)
                .frame(width: 338, height: 158)
                .background {
                    DailyPoemWidgetBackground(entry: entry, family: .systemMedium)
                }
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .shadow(color: .black.opacity(0.1), radius: 14, y: 6)
                .frame(maxWidth: .infinity)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private var previewEntry: DailyPoemEntry? {
        guard let poem = DailyPoemWidgetStore.read().flatMap({ DailyPoemWidgetStore.poem(on: .now, in: $0) }) else {
            return nil
        }
        let font = typeface == .xiaozhuan ? PoemTypeface.kaiti : typeface
        return DailyPoemEntry(
            date: .now,
            poem: poem,
            fontName: font.resolvedFontName,
            isEnglish: AppLanguage.isEnglish,
            background: poem.landscapeBackground.flatMap { UIImage(named: $0) },
            avatar: poem.avatar.flatMap { UIImage(named: $0) }
        )
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.cinnabar))
                .accessibilityHidden(true)
            Text(text.poemScript(script))
                .font(typeface.smallFont)
                .foregroundStyle(Color.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A silent, looping clip from the app bundle, without playback controls.
private struct LoopingVideo: UIViewRepresentable {
    let resource: String

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        guard let url = Bundle.main.url(forResource: resource, withExtension: "mp4") else { return view }
        let player = AVQueuePlayer()
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        view.looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        player.play()
        return view
    }

    func updateUIView(_ uiView: PlayerView, context: Context) {}

    static func dismantleUIView(_ uiView: PlayerView, coordinator: ()) {
        uiView.playerLayer.player?.pause()
        uiView.looper = nil
    }

    final class PlayerView: UIView {
        var looper: AVPlayerLooper?
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}
