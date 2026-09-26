import SwiftUI

// MARK: - Spotlight Step

enum SpotlightStep: Int, Equatable {
    case selectMood        // 心境页：点"喜"
    case selectImage       // 意境页：选第一个题目
    case selectLine        // 诗句页：选一句
    case tapShare          // 完成页：点分享
    case selectBackground  // 分享页：选底纸
    case tapShareButton    // 分享页：点分享按钮
    case returnFromShare   // 分享完成后：返回诗页
    case returnHome        // 诗页：回到首页
    case openHistory       // 首页：打开历史
    case openHistoryPoem   // 历史页：查看一首诗

    var next: SpotlightStep? {
        switch self {
        case .selectMood:       .selectImage
        case .selectImage:      .selectLine
        case .selectLine:       .tapShare
        case .tapShare:         .selectBackground
        case .selectBackground: .tapShareButton
        case .tapShareButton:   .returnFromShare
        case .returnFromShare:  .returnHome
        case .returnHome:       .openHistory
        case .openHistory:      .openHistoryPoem
        case .openHistoryPoem:  nil
        }
    }

    var message: String {
        switch self {
        case .selectMood:       AppLanguage.copy("點擊選一種心情", "Choose a feeling")
        case .selectImage:      AppLanguage.copy("選一個意境題目", "Choose an image")
        case .selectLine:       AppLanguage.copy("選一句最合心意的", "Choose a line")
        case .tapShare:         AppLanguage.copy("點擊分享詩作", "Share your poem")
        case .selectBackground: AppLanguage.copy("選一張底紙試試", "Choose a paper")
        case .tapShareButton:   AppLanguage.copy("點擊分享給朋友", "Share with friends")
        case .returnFromShare:  AppLanguage.copy("分享完成後返回", "Return after sharing")
        case .returnHome:       AppLanguage.copy("回到首頁", "Return home")
        case .openHistory:      AppLanguage.copy("查看往日詩作", "View past poems")
        case .openHistoryPoem:  AppLanguage.copy("點開一首詩作", "Open a poem")
        }
    }

    var title: String {
        switch self {
        case .selectMood:       AppLanguage.copy("先選一種心情", "Choose a feeling")
        case .selectImage:      AppLanguage.copy("選一個意境題目", "Choose an image")
        case .selectLine:       AppLanguage.copy("挑一句入詩", "Choose a line")
        case .tapShare:         AppLanguage.copy("把詩分享出去", "Share your poem")
        case .selectBackground: AppLanguage.copy("換一張底紙", "Choose a paper")
        case .tapShareButton:   AppLanguage.copy("生成分享圖", "Create a share image")
        case .returnFromShare:  AppLanguage.copy("回到詩頁", "Return to poem")
        case .returnHome:       AppLanguage.copy("回到首頁", "Return home")
        case .openHistory:      AppLanguage.copy("查看往日詩作", "View past poems")
        case .openHistoryPoem:  AppLanguage.copy("打開一首舊作", "Open a past poem")
        }
    }

    var detail: String {
        switch self {
        case .selectMood:
            return AppLanguage.copy("點擊高亮的「喜」，讓詩先有一個情緒起點。", "Tap the highlighted Chinese character to begin with a feeling.")
        case .selectImage:
            return AppLanguage.copy("從題目中選一個最有畫面的，它會成為這首詩的方向。", "Choose the image that speaks to you; it will guide the poem.")
        case .selectLine:
            return AppLanguage.copy("候選詩句可以逐句挑選，先點一個最合心意的。", "Choose one Chinese line at a time.")
        case .tapShare:
            return AppLanguage.copy("詩已完成，可以進入分享頁預覽不同版式。", "Your poem is complete. Preview it in different layouts.")
        case .selectBackground:
            return AppLanguage.copy("先試一張免費底紙，看看詩和畫面是否相稱。", "Try a free paper to see how it suits the poem.")
        case .tapShareButton:
            return AppLanguage.copy("點擊高亮的分享按鈕，呼出系統分享面板。", "Tap the highlighted Share button to open the system share sheet.")
        case .returnFromShare:
            return AppLanguage.copy("分享完成後，先返回到詩歌完成頁。", "After sharing, return to the completed poem.")
        case .returnHome:
            return AppLanguage.copy("回到首頁，下一步看看剛才保存的詩。", "Return home, then view the poem you just saved.")
        case .openHistory:
            return AppLanguage.copy("右上角可以打開歷史，查看以前生成的詩作。", "Open History in the upper-right corner to view earlier poems.")
        case .openHistoryPoem:
            return AppLanguage.copy("點開第一首詩，教程就完成了。", "Open the first poem to finish the tutorial.")
        }
    }
}

// MARK: - Guide State

@Observable
final class SpotlightGuide {
    var step: SpotlightStep?
    var showsCompletionAlert = false

    func startIfNeeded() {
        guard step == nil, !UserDefaults.standard.bool(forKey: Self.storageKey) else { return }
        step = .selectMood
    }

    func advance() {
        guard let current = step else { return }
        step = current.next
        if step == nil {
            finish(showAlert: true)
        }
    }

    func skip() {
        finish(showAlert: false)
    }

    private func finish(showAlert: Bool) {
        step = nil
        UserDefaults.standard.set(true, forKey: Self.storageKey)
        showsCompletionAlert = showAlert
    }

    static let storageKey = "spotlight_guide_done"
}

// MARK: - Environment

private struct SpotlightGuideKey: EnvironmentKey {
    static let defaultValue = SpotlightGuide()
}

extension EnvironmentValues {
    var spotlightGuide: SpotlightGuide {
        get { self[SpotlightGuideKey.self] }
        set { self[SpotlightGuideKey.self] = newValue }
    }
}

// MARK: - Preference Key (for reporting target frame)

struct SpotlightFramePreference: PreferenceKey {
    static let defaultValue: [SpotlightStep: CGRect] = [:]
    static func reduce(value: inout [SpotlightStep: CGRect], nextValue: () -> [SpotlightStep: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

// MARK: - View Extensions

extension View {
    /// Tag this view as the spotlight target for a specific step.
    func spotlightTarget(
        _ step: SpotlightStep,
        active: Bool,
        offset: CGSize = .zero,
        insetBy inset: CGSize = .zero
    ) -> some View {
        overlay(
            GeometryReader { geo in
                let frame = geo.frame(in: .named("spotlightSpace"))
                    .offsetBy(dx: offset.width, dy: offset.height)
                    .insetBy(dx: inset.width, dy: inset.height)
                Color.clear.preference(
                    key: SpotlightFramePreference.self,
                    value: active ? [step: frame] : [:]
                )
            }
        )
    }

    /// Add a spotlight overlay that activates for the given steps.
    func spotlightOverlay(for steps: Set<SpotlightStep>, cornerRadius: CGFloat = 28) -> some View {
        modifier(SpotlightContainerModifier(steps: steps, cornerRadius: cornerRadius))
    }
}

// MARK: - Container Modifier

private struct SpotlightContainerModifier: ViewModifier {
    @Environment(\.spotlightGuide) private var guide
    let steps: Set<SpotlightStep>
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .coordinateSpace(name: "spotlightSpace")
            .overlayPreferenceValue(SpotlightFramePreference.self) { frames in
                if let step = guide.step, steps.contains(step), let frame = frames[step], frame != .zero {
                    SpotlightOverlayView(step: step, frame: frame, cornerRadius: cornerRadius)
                }
            }
    }
}

// MARK: - Overlay View

private struct SpotlightOverlayView: View {
    @Environment(\.poemScript) private var script
    @Environment(\.spotlightGuide) private var guide
    let step: SpotlightStep
    let frame: CGRect
    let cornerRadius: CGFloat

    private var cardWidth: CGFloat {
        min(UIScreen.main.bounds.width - 48, 336)
    }

    private var highlightFrame: CGRect {
        switch step {
        case .selectMood:
            let side = min(max(frame.width, frame.height), 58)
            return CGRect(
                x: frame.midX - side / 2,
                y: frame.midY - side / 2 - 3,
                width: side,
                height: side
            )
        case .selectImage:
            return frame
                .offsetBy(dx: 0, dy: 4)
                .insetBy(dx: 2, dy: 2)
        case .selectLine:
            return frame
                .offsetBy(dx: 0, dy: 6)
        case .selectBackground:
            return frame.insetBy(dx: 0, dy: 0)
        default:
            return frame
        }
    }

    private var highlightCornerRadius: CGFloat {
        switch step {
        case .selectMood:
            return 34
        case .selectBackground:
            return 10
        default:
            return cornerRadius
        }
    }

    private var cardY: CGFloat {
        let screenHeight = UIScreen.main.bounds.height
        let target = highlightFrame
        if target.midY > screenHeight * 0.60 {
            return max(170, target.minY - 128)
        }
        return min(screenHeight - 170, target.maxY + 118)
    }

    var body: some View {
        let target = highlightFrame
        let targetCornerRadius = highlightCornerRadius

        ZStack {
            Color.black.opacity(0.50)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            RoundedRectangle(cornerRadius: targetCornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.18))
                .frame(width: target.width + 14, height: target.height + 14)
                .position(x: target.midX, y: target.midY)
                .blur(radius: 2)
                .allowsHitTesting(false)

            RoundedRectangle(cornerRadius: targetCornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.94), lineWidth: 3)
                .frame(width: target.width + 14, height: target.height + 14)
                .position(x: target.midX, y: target.midY)
                .shadow(color: Color.white.opacity(0.28), radius: 8, x: 0, y: 0)
                .allowsHitTesting(false)

            SpotlightBubble(
                title: step.title.poemScript(script),
                detail: step.detail.poemScript(script),
                nextTitle: step.next == nil
                    ? AppLanguage.copy("完成", "Done")
                    : AppLanguage.copy("下一条", "Next")
            ) {
                guide.skip()
            } onNext: {
                guide.advance()
            }
                .frame(width: cardWidth)
                .position(
                    x: UIScreen.main.bounds.width / 2,
                    y: cardY
                )
        }
        .animation(.easeOut(duration: 0.35), value: target.origin.x)
        .animation(.easeOut(duration: 0.35), value: target.origin.y)
    }
}

private struct SpotlightBubble: View {
    let title: String
    let detail: String
    let nextTitle: String
    let onSkip: () -> Void
    let onNext: () -> Void

    private let paper = Color(red: 0.99, green: 0.96, blue: 0.89)
    private let ink = Color(red: 0.18, green: 0.14, blue: 0.10)
    private let secondaryInk = Color(red: 0.48, green: 0.41, blue: 0.35)
    private let cinnabar = Color(red: 0.68, green: 0.07, blue: 0.05)

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 9) {
                Text(title)
                    .font(.system(size: 22, weight: .semibold, design: .serif))
                    .foregroundStyle(ink)

                Text(detail)
                    .font(.system(size: 16, weight: .regular, design: .serif))
                    .foregroundStyle(secondaryInk)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button(AppLanguage.copy("跳过", "Skip")) {
                    onSkip()
                }
                .font(.system(size: 16, weight: .semibold, design: .serif))
                .foregroundStyle(secondaryInk)

                Spacer()

                Button(nextTitle) {
                    onNext()
                }
                .font(.system(size: 16, weight: .semibold, design: .serif))
                .foregroundStyle(cinnabar)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 22)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(paper)
                .stroke(Color.white.opacity(0.78), lineWidth: 1.4)
        )
        .shadow(color: Color.black.opacity(0.24), radius: 22, x: 0, y: 12)
    }
}
