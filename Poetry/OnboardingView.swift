import SwiftUI
import UIKit
import CoreFoundation

private func simplifiedSealText(_ text: String) -> String {
    let mutable = NSMutableString(string: text)
    CFStringTransform(mutable, nil, "Hant-Hans" as CFString, false)
    return mutable as String
}

private struct KeyboardWarmupTextField: UIViewRepresentable {
    @Binding var shouldWarm: Bool

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField(frame: .zero)
        textField.autocorrectionType = .no
        textField.spellCheckingType = .no
        textField.textColor = .clear
        textField.tintColor = .clear
        textField.backgroundColor = .clear
        return textField
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        guard shouldWarm, !context.coordinator.hasWarmed else { return }
        context.coordinator.hasWarmed = true

        DispatchQueue.main.async {
            uiView.becomeFirstResponder()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                uiView.resignFirstResponder()
                shouldWarm = false
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var hasWarmed = false
    }
}

// MARK: - Onboarding Root

struct OnboardingView: View {
    let onFinish: () -> Void
    @State private var currentPage = 0

    private let totalPages = 3

    var body: some View {
        ZStack {
            TabView(selection: $currentPage) {
                OnboardingPoemPage()
                    .tag(0)
                OnboardingSharePage()
                    .tag(1)
                OnboardingSealPage()
                    .tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut(duration: 0.3), value: currentPage)

            // Bottom controls
            VStack {
                Spacer()

                HStack(spacing: 0) {
                    HStack(spacing: 10) {
                        ForEach(0..<totalPages, id: \.self) { i in
                            Circle()
                                .fill(i == currentPage ? Color.cinnabar : Color.mutedInk.opacity(0.25))
                                .frame(width: 7, height: 7)
                                .animation(.easeOut(duration: 0.25), value: currentPage)
                        }
                    }

                    Spacer()

                    Button {
                        if currentPage < totalPages - 1 {
                            withAnimation { currentPage += 1 }
                        } else {
                            onFinish()
                        }
                    } label: {
                        Text(AppLanguage.isEnglish
                            ? (currentPage < totalPages - 1 ? "Continue" : "Get started")
                            : (currentPage < totalPages - 1 ? "續" : "始"))
                            .font(.system(size: AppLanguage.isEnglish ? 12 : 15, weight: .medium, design: .serif))
                            .foregroundStyle(.white)
                            .frame(width: AppLanguage.isEnglish ? 92 : 44, height: 44)
                            .background {
                                if AppLanguage.isEnglish {
                                    Capsule().fill(Color.cinnabar)
                                } else {
                                    Circle().fill(Color.cinnabar)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 30)
                .padding(.bottom, 56)
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Page 1: Poem Generation Demo

private struct OnboardingPoemPage: View {
    @State private var revealedChars = 0
    @State private var showSeal = false
    @State private var showInscription = false
    @State private var revealedEnglishWords = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let demoLines = ["故人西辭黃鶴樓", "煙花三月下揚州", "孤帆遠影碧空盡", "唯見長江天際流"]
    private let demoTitle = "黃鶴樓送孟浩然之廣陵"
    private let englishTitle = "Seeing Meng Haoran Off to Guangling"
    private let englishAuthor = "Li Bai"
    private let translationLines = [
        "My old friend bids farewell at Yellow Crane Tower,",
        "sailing for Yangzhou through the misty blossoms of spring.",
        "His lone sail fades into the far blue sky—",
        "only the Yangtze remains, flowing to the edge of heaven."
    ]
    private let sealName = "青莲居士"
    private let inscriptionDate = "開元十八年\u{2009}暮春"
    private let inscriptionPlace = "於\u{2009}黃鶴樓"

    private let sealFontName = "FZXZTFW--GB1-0"
    /// Resolved Huiwen Mincho font for the poem text
    private let poemFontName: String = {
        let candidates = ["Huiwen-mincho", "汇文明朝体"]
        return candidates.first { UIFont(name: $0, size: 12) != nil } ?? "Huiwen-mincho"
    }()

    private func poemFont(size: CGFloat) -> Font {
        Font.custom(poemFontName, size: size)
    }

    private var totalChars: Int { demoLines.reduce(0) { $0 + $1.count } }

    private func charsForLine(_ lineIndex: Int) -> Int {
        var charsBefore = 0
        for i in 0..<lineIndex {
            charsBefore += demoLines[i].count
        }
        return max(0, min(revealedChars - charsBefore, demoLines[lineIndex].count))
    }

    private var allRevealed: Bool {
        revealedChars >= totalChars
    }

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            Image("bg_boat")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
                .opacity(0.8)

            VStack {
                HStack(alignment: .top) {
                    // Left column: inscription + seal (always occupies space)
                    VStack {
                        Spacer()

                        // Inscription — always present, opacity-controlled
                        HStack(alignment: .top, spacing: 10) {
                            onboardingVerticalText(inscriptionDate, fontSize: 10, color: Color.mutedInk.opacity(0.7), spacing: 5)
                            onboardingVerticalText(inscriptionPlace, fontSize: 11, color: Color.mutedInk.opacity(0.7), spacing: 6)
                        }
                        .opacity(showInscription ? 1 : 0)
                        .padding(.bottom, 16)

                        // Seal — always present, opacity-controlled
                        onboardingSealStamp(name: sealName, size: 44)
                            .opacity(showSeal ? 1 : 0)
                            .scaleEffect(showSeal ? 1 : 0.7)
                            .padding(.bottom, 60)
                    }
                    .padding(.leading, 28)

                    Spacer()

                    // Right: poem body (right-to-left columns)
                    HStack(alignment: .top, spacing: 22) {
                        ForEach(Array(demoLines.enumerated()).reversed(), id: \.offset) { index, line in
                            let count = charsForLine(index)
                            onboardingTypewriterLine(
                                text: line,
                                visibleCount: count,
                                fontSize: 18.5,
                                spacing: 7
                            )
                        }

                        // Title column
                        onboardingVerticalText(demoTitle, fontSize: 11, color: .mutedInk, spacing: 4)
                            .padding(.leading, 12)
                    }
                    .padding(.top, 78)
                    .padding(.trailing, 34)
                }

                Spacer()

                // English readers get the translation beneath the original,
                // mirroring how the reading view pairs the two.
                if AppLanguage.isEnglish {
                    englishTranslation
                        .padding(.horizontal, 30)
                }

                Spacer().frame(height: 120)
            }
        }
        .animation(.easeOut(duration: 0.6), value: showSeal)
        .animation(.easeOut(duration: 0.6), value: showInscription)
        .task { await revealPoem() }
    }

    /// Matches the real FinishedPoemView reveal cadence
    private func revealPoem() async {
        revealedChars = 0
        showSeal = false
        showInscription = false
        revealedEnglishWords = 0

        // Initial pause
        try? await Task.sleep(nanoseconds: 600_000_000)

        // Characters overlap while they come into focus, so a short step
        // keeps the reveal brisk without feeling like a typewriter.
        let lineDelay: UInt64 = 220_000_000
        let characterDelay: UInt64 = 70_000_000

        for lineIndex in demoLines.indices {
            if lineIndex > 0 {
                try? await Task.sleep(nanoseconds: lineDelay)
            }
            guard !Task.isCancelled else { return }

            for _ in demoLines[lineIndex] {
                guard !Task.isCancelled else { return }
                try? await Task.sleep(nanoseconds: characterDelay)
                await MainActor.run {
                    revealedChars += 1
                }
            }
        }

        // Show inscription
        try? await Task.sleep(nanoseconds: 500_000_000)
        guard !Task.isCancelled else { return }
        await MainActor.run {
            showInscription = true
        }

        // Show seal
        try? await Task.sleep(nanoseconds: 500_000_000)
        guard !Task.isCancelled else { return }
        await MainActor.run {
            showSeal = true
        }

        guard AppLanguage.isEnglish else { return }
        try? await Task.sleep(nanoseconds: 400_000_000)
        let wordDelay: UInt64 = 55_000_000
        let englishGroups = [englishTitleWords, [englishAuthor]] + translationLineWords
        for (groupIndex, group) in englishGroups.enumerated() {
            if groupIndex > 0 {
                try? await Task.sleep(nanoseconds: 140_000_000)
            }
            for _ in group {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    revealedEnglishWords += 1
                }
                try? await Task.sleep(nanoseconds: wordDelay)
            }
        }
    }

    private var englishTitleWords: [String] {
        englishTitle.split(separator: " ").map(String.init)
    }

    private var translationLineWords: [[String]] {
        translationLines.map { $0.split(separator: " ").map(String.init) }
    }

    /// Index of a translation line's first word in the overall English reveal
    /// order (title words, then the author, then each line).
    private func englishWordOffset(forLine lineIndex: Int) -> Int {
        englishTitleWords.count + 1 + translationLineWords.prefix(lineIndex).reduce(0) { $0 + $1.count }
    }

    private var englishTranslation: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                OnboardingWordFlow(wordSpacing: 4.5, lineSpacing: 2) {
                    ForEach(Array(englishTitleWords.enumerated()), id: \.offset) { index, word in
                        Text(word)
                            .font(.system(size: 17, weight: .regular, design: .serif))
                            .italic()
                            .foregroundStyle(Color.ink)
                            .modifier(InkReveal(visible: index < revealedEnglishWords, reduceMotion: reduceMotion, blurRadius: 8, startScale: 1.15, startOffset: -4))
                    }
                }
                Text(englishAuthor)
                    .font(.system(size: 12, design: .serif))
                    .foregroundStyle(Color.mutedInk)
                    .modifier(InkReveal(visible: englishTitleWords.count < revealedEnglishWords, reduceMotion: reduceMotion, blurRadius: 6, startScale: 1.05, startOffset: -3))
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(translationLineWords.enumerated()), id: \.offset) { lineIndex, words in
                    let offset = englishWordOffset(forLine: lineIndex)
                    OnboardingWordFlow(wordSpacing: 3.5, lineSpacing: 2) {
                        ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                            Text(word)
                                .font(.system(size: 14, weight: .light, design: .serif))
                                .foregroundStyle(Color.ink.opacity(0.85))
                                .modifier(InkReveal(visible: offset + index < revealedEnglishWords, reduceMotion: reduceMotion, blurRadius: 7, startScale: 1.15, startOffset: -4))
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Onboarding-local view builders

    @ViewBuilder
    private func onboardingTypewriterLine(text: String, visibleCount: Int, fontSize: CGFloat, spacing: CGFloat) -> some View {
        let chars = Array(text.enumerated())
        VStack(spacing: spacing) {
            ForEach(chars, id: \.offset) { index, character in
                Text(String(character))
                    .font(poemFont(size: fontSize))
                    .foregroundStyle(Color.ink)
                    .modifier(InkReveal(visible: index < visibleCount, reduceMotion: reduceMotion, blurRadius: 9, startScale: 1.35, startOffset: -6))
            }
        }
        .fixedSize()
    }

    @ViewBuilder
    private func onboardingVerticalText(_ text: String, fontSize: CGFloat, color: Color = .ink, spacing: CGFloat) -> some View {
        VStack(spacing: spacing) {
            ForEach(Array(text.enumerated()), id: \.offset) { _, char in
                Text(String(char))
                    .font(poemFont(size: fontSize))
                    .foregroundStyle(color)
            }
        }
    }

    @ViewBuilder
    private func onboardingSealStamp(name: String, size: CGFloat) -> some View {
        let allChars = Array(simplifiedSealText(name)).map(String.init)
        let sealChars = Array(allChars.prefix(4))
        let charSize = max(20, size * 0.43)

        ZStack {
            RoundedRectangle(cornerRadius: max(1, size * 0.025))
                .fill(Color.cinnabar)

            RoundedRectangle(cornerRadius: max(1, size * 0.025))
                .stroke(Color.white.opacity(0.96), lineWidth: max(1.4, size * 0.045))
                .padding(size * 0.045)

            // Right-to-left, top-to-bottom: same layout as real SealStampView.stampGrid
            HStack(spacing: size * 0.014) {
                // Left column (read second): chars[2], chars[3]
                VStack(spacing: size * 0.004) {
                    if sealChars.count > 2 {
                        Text(sealChars[2])
                            .font(sealFont(size: charSize))
                            .foregroundStyle(.white)
                            .frame(width: size * 0.40, height: size * 0.40)
                    }
                    if sealChars.count > 3 {
                        Text(sealChars[3])
                            .font(sealFont(size: charSize))
                            .foregroundStyle(.white)
                            .frame(width: size * 0.40, height: size * 0.40)
                    }
                }
                // Right column (read first): chars[0], chars[1]
                VStack(spacing: size * 0.004) {
                    Text(sealChars[0])
                        .font(sealFont(size: charSize))
                        .foregroundStyle(.white)
                        .frame(width: size * 0.40, height: size * 0.40)
                    if sealChars.count > 1 {
                        Text(sealChars[1])
                            .font(sealFont(size: charSize))
                            .foregroundStyle(.white)
                            .frame(width: size * 0.40, height: size * 0.40)
                    }
                }
            }
            .padding(size * 0.072)
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(-5))
    }

    private func sealFont(size: CGFloat) -> Font {
        if UIFont(name: sealFontName, size: 12) != nil {
            return Font.custom(sealFontName, size: size)
        }
        return .system(size: size, weight: .bold, design: .serif)
    }
}

// MARK: - Page 3: Seal Name Setup

/// Condenses a glyph or word out of a soft blur, like ink settling into
/// rice paper, instead of popping it in. Reduce Motion keeps only the fade.
private struct InkReveal: ViewModifier {
    let visible: Bool
    let reduceMotion: Bool
    let blurRadius: CGFloat
    let startScale: CGFloat
    let startOffset: CGFloat

    func body(content: Content) -> some View {
        let settled = visible || reduceMotion
        content
            .opacity(visible ? 1 : 0)
            .blur(radius: settled ? 0 : blurRadius)
            .scaleEffect(settled ? 1 : startScale)
            .offset(y: settled ? 0 : startOffset)
            .animation(.easeOut(duration: 0.75), value: visible)
    }
}

/// Wraps words left-to-right like a paragraph, so each word can animate on
/// its own while the line still reads as ordinary text.
private struct OnboardingWordFlow: Layout {
    var wordSpacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.reduce(0) { $0 + $1.height } + lineSpacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + row.height - size.height), proposal: .unspecified)
                x += size.width + wordSpacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width maxWidth: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + wordSpacing + size.width
            if needed > maxWidth, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + wordSpacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

private struct OnboardingSealPage: View {
    @AppStorage(SealStampView.storageKey) private var sealName = ""
    @State private var editingName = ""
    @State private var suggestions: [String] = []
    @State private var shouldWarmKeyboard = false
    @FocusState private var nameFieldFocused: Bool

    private let suggestionRowID = "suggestionRow"

    /// Pre-built default names shown on first load. English readers get given
    /// names, which the seal transliterates into Chinese (Emily → 艾米莉).
    private var defaultSuggestions: [String] {
        AppLanguage.isEnglish ? ["Emily", "Oliver", "Sophia"] : ["聽松居士", "半山散人", "夜雨書生"]
    }

    /// Offline pool for the dice button; users can always type their own.
    private var penNamePool: [String] {
        AppLanguage.isEnglish ? englishNamePool : chinesePenNamePool
    }

    private let englishNamePool = [
        "Emily", "Oliver", "Sophia",
        "James", "Grace", "Henry",
        "Lucy", "Daniel", "Olivia",
        "William", "Chloe", "Samuel",
        "Hannah", "Thomas", "Lily",
        "Noah", "Rose", "Owen"
    ]

    private let chinesePenNamePool = [
        "聽松居士", "半山散人", "夜雨書生",
        "松間隱客", "雲水閒人", "青山居士",
        "抱朴軒主", "枕流齋主", "梅溪釣叟",
        "竹窗客", "漱玉山人", "觀瀾居士",
        "樵歌唱晚", "臨池散人", "採薇山人",
        "聽雪齋主", "滄浪釣客", "溪雲野鶴"
    ]

    private var fullName: String {
        editingName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            DappledShadowView()
                .opacity(0.2)
                .ignoresSafeArea()

            KeyboardWarmupTextField(shouldWarm: $shouldWarmKeyboard)
                .frame(width: 1, height: 1)
                .opacity(0.001)
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                // Title
                VStack(alignment: .leading, spacing: 8) {
                    Text(AppLanguage.copy("客官貴姓", "What should your seal say?"))
                        .font(.system(size: 28, weight: .light, design: .serif))
                    Text(AppLanguage.copy("留個名號，好為你刻一方印", "Type your name and we'll carve it in Chinese."))
                        .font(.system(size: 14, design: .serif))
                        .foregroundStyle(Color.mutedInk)
                        .tracking(AppLanguage.isEnglish ? 0 : 1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 100)
                .padding(.leading, 30)

                Spacer().frame(height: 40)

                // Seal preview — always visible (default name pre-filled)
                sealPreview
                    .padding(.bottom, 28)

                // Input area
                VStack(spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 12) {
                            TextField("", text: $editingName, prompt: Text(AppLanguage.copy("姓名或雅號", "Your name"))
                                .font(.system(size: 15, design: .serif))
                                .foregroundStyle(Color.mutedInk.opacity(0.4)))
                                .font(.system(size: 16, design: .serif))
                                .foregroundStyle(Color.ink)
                                .focused($nameFieldFocused)
                                .submitLabel(.done)
                                .onSubmit {
                                    nameFieldFocused = false
                                    saveName()
                                }

                            // Dice / random button
                            Button {
                                nameFieldFocused = false
                                suggestPenNames()
                            } label: {
                                Image(systemName: "dice.fill")
                                    .font(.system(size: 16))
                                    .foregroundStyle(Color.cinnabar)
                                    .frame(width: 40, height: 32)
                                    .background {
                                        RoundedRectangle(cornerRadius: 7)
                                            .stroke(Color.cinnabar.opacity(0.6), lineWidth: 0.9)
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(AppLanguage.copy("生成雅號", "Suggest a name"))
                        }

                        Rectangle()
                            .fill(Color.mutedInk.opacity(0.25))
                            .frame(height: 0.5)
                    }
                    .padding(.horizontal, 30)

                    if !fullName.isEmpty {
                        SealTransliterationChips(name: fullName)
                            .padding(.top, 10)
                            .padding(.horizontal, 30)
                            .transition(.opacity.combined(with: .offset(y: 6)))
                    }

                    // Suggestion pills
                    if !suggestions.isEmpty {
                        ScrollViewReader { proxy in
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(suggestions, id: \.self) { suggestion in
                                        Button {
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                                editingName = suggestion
                                                saveName()
                                            }
                                        } label: {
                                            Text(suggestion)
                                                .font(.system(size: 14, design: .serif))
                                                .foregroundStyle(editingName == suggestion ? .white : Color.ink)
                                                .padding(.horizontal, 14)
                                                .padding(.vertical, 9)
                                                .background {
                                                    Capsule()
                                                        .fill(editingName == suggestion ? Color.cinnabar : Color.white.opacity(0.7))
                                                        .stroke(editingName == suggestion ? Color.cinnabar : Color.mutedInk.opacity(0.3), lineWidth: 0.8)
                                                }
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 30)
                                // Swap a new batch in place; animating it makes every
                                // pill slide to its new position and the row jumps.
                                .animation(nil, value: suggestions)
                                .id(suggestionRowID)
                            }
                            .onChange(of: suggestions) {
                                proxy.scrollTo(suggestionRowID, anchor: .leading)
                            }
                        }
                        .transition(.opacity.combined(with: .offset(y: 8)))
                    }
                }

                Spacer()
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: fullName)
        .onAppear {
            // Pre-fill: use saved name, or pick a random default
            if sealName.isEmpty {
                let pick = defaultSuggestions.randomElement() ?? defaultSuggestions[0]
                editingName = pick
                sealName = pick
                suggestions = defaultSuggestions
            } else {
                editingName = sealName
                suggestions = defaultSuggestions
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                shouldWarmKeyboard = true
            }
        }
        .onTapGesture {
            nameFieldFocused = false
        }
    }

    // MARK: - Seal Preview

    /// The same stamp the app renders on saved poems, so the transliteration
    /// and seal style shown here match what the reader will get later.
    private var sealPreview: some View {
        SealStampView(name: fullName, size: 80)
            .opacity(fullName.isEmpty ? 0 : 1)
    }

    // MARK: - Actions

    private func saveName() {
        let trimmed = editingName.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasCJK = trimmed.contains { $0.isCJK }
        sealName = String(trimmed.prefix(hasCJK ? 4 : 24))
    }

    private func suggestPenNames() {
        let current = fullName
        let pick = penNamePool.filter { $0 != current }.randomElement() ?? current
        let rest = penNamePool.filter { $0 != pick }.shuffled().prefix(5)
        // Keep the chosen name first so the selected pill is always in view.
        suggestions = [pick] + rest
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            editingName = pick
            saveName()
        }
    }
}

// MARK: - Page 3: Share Page Demo

private struct OnboardingSharePage: View {
    @State private var currentBgIndex = 0
    @State private var animating = false

    private let demoLines = ["故人西辭黃鶴樓", "煙花三月下揚州", "孤帆遠影碧空盡", "唯見長江天際流"]
    private let demoTitle = "黃鶴樓送孟浩然之廣陵"
    private let demoSealName = "青莲居士"
    private let demoDate = "開元十八年\u{2009}暮春"
    private let demoColophon = "錄李白詩於黃鶴樓"
    private let backgrounds: [PoemBackground] = [.boat, .bamboo, .moon, .lotus, .plum]

    private var currentBg: PoemBackground { backgrounds[currentBgIndex] }

    /// The same style a fresh share sheet opens with — vertical verse, the
    /// default typeface and seal — so the demo matches what users will share.
    private var demoStyle: ShareArtworkStyle {
        let defaults = ShareArtworkStyle.defaultPreferences
        return ShareArtworkStyle(
            background: currentBg,
            typeface: defaults.typeface,
            script: .traditional,
            usesVerticalText: true,
            sealName: demoSealName,
            sealStyle: defaults.sealStyle,
            transliteration: "",
            shadow: defaults.shadow
        )
    }

    private var demoTranslation: ShareTranslation? {
        guard AppLanguage.isEnglish else { return nil }
        return ShareTranslation(
            title: "Seeing Meng Haoran Off to Guangling",
            byline: "Li Bai",
            text: [
                "My old friend bids farewell at Yellow Crane Tower,",
                "sailing for Yangzhou through the misty blossoms of spring.",
                "His lone sail fades into the far blue sky—",
                "only the Yangtze remains, flowing to the edge of heaven."
            ].joined(separator: "\n")
        )
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                HStack(alignment: .top) {
                    Text(AppLanguage.copy("分享", "Share"))
                        .font(.system(size: 28, weight: .light, design: .serif))
                        .foregroundStyle(Color.ink)
                    Spacer()
                }
                .padding(.horizontal, 30)
                .padding(.top, 82)
                .padding(.bottom, 16)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(Array(backgrounds.enumerated()), id: \.element.id) { index, bg in
                            let isActive = currentBgIndex == index
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
                                        Group {
                                            if AppLanguage.isEnglish {
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 9, weight: .bold))
                                            } else {
                                                Text("擇")
                                                    .font(.system(size: 10, weight: .medium, design: .serif))
                                            }
                                        }
                                            .foregroundStyle(.white)
                                            .frame(width: 18, height: 18)
                                            .background(Circle().fill(Color.cinnabar))
                                            .offset(x: 5, y: 5)
                                            .transition(.scale(scale: 0.75).combined(with: .opacity))
                                    }
                                }
                                Text(bg.displayName)
                                    .font(.system(size: 11, design: .serif))
                                    .foregroundStyle(isActive ? Color.ink : Color.mutedInk)
                            }
                        }
                    }
                    .padding(.horizontal, 30)
                    .padding(.vertical, 2)
                }
                .padding(.bottom, 14)

                VStack(spacing: 14) {
                    let maxPreviewW: CGFloat = min(UIScreen.main.bounds.width - 92, 320)
                    let artworkW: CGFloat = 1080
                    let artworkH: CGFloat = 1620
                    let previewScale = maxPreviewW / artworkW
                    let previewH = artworkH * previewScale

                    ConfiguredShareArtwork(
                        layout: .portrait,
                        imageTitle: demoTitle,
                        lines: demoLines,
                        locationMark: demoColophon,
                        lunarDateText: demoDate,
                        dayPeriodText: "",
                        style: demoStyle,
                        translation: demoTranslation
                    )
                    .frame(width: artworkW, height: artworkH)
                    .scaleEffect(previewScale, anchor: .center)
                    .frame(width: maxPreviewW, height: previewH)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .shadow(color: Color.black.opacity(0.10), radius: 10, x: 0, y: 5)

                    Text(AppLanguage.copy("換一張底紙，詩便有了不同氣息", "Change the paper to give your poem a different mood."))
                        .font(.system(size: 14, weight: .light, design: .serif))
                        .foregroundStyle(Color.mutedInk)
                        .tracking(AppLanguage.isEnglish ? 0 : 1)
                }
                .padding(.horizontal, 30)
                .animation(.easeOut(duration: 0.3), value: currentBgIndex)

                Spacer()
            }
        }
        .onAppear { startCycling() }
        .onDisappear { animating = false }
    }

    private func startCycling() {
        animating = true
        cycleBg()
    }

    private func cycleBg() {
        guard animating else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            guard animating else { return }
            withAnimation(.easeInOut(duration: 0.3)) {
                currentBgIndex = (currentBgIndex + 1) % backgrounds.count
            }
            cycleBg()
        }
    }
}

// MARK: - Color extensions (scoped to this file)

private extension Color {
    static let paper = Color.white
    static let rice = Color(red: 0.94, green: 0.91, blue: 0.84)
    static let ink = Color(red: 0.08, green: 0.075, blue: 0.07)
    static let mutedInk = Color(red: 0.34, green: 0.32, blue: 0.29)
    static let cinnabar = Color(red: 0.77, green: 0.02, blue: 0.06)
}
