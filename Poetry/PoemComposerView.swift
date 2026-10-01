import SwiftUI
import UIKit
import CoreFoundation
import StoreKit

private extension Color {
    static let paper = Color.white
    static let rice = Color(red: 0.94, green: 0.91, blue: 0.84)
    static let ink = Color(red: 0.08, green: 0.075, blue: 0.07)
    static let mutedInk = Color(red: 0.34, green: 0.32, blue: 0.29)
    static let cinnabar = Color(red: 0.77, green: 0.02, blue: 0.06)
}

struct PoemComposerView: View {
    /// A completed poem belongs in the archive. Once the composer is out of view
    /// (archive pushed or another tab selected), start a fresh composing session
    /// rather than replaying the completion reveal on return.
    var isActive: Bool = true
    var onOpenArchive: () -> Void = {}

    @AppStorage(PoemTypeface.storageKey) private var typefaceRawValue = PoemTypeface.kaiti.rawValue
    @AppStorage(PoemScript.storageKey) private var scriptRawValue = PoemScript.simplified.rawValue
    @AppStorage(PoemStructure.storageKey) private var structureRawValue = PoemStructure.jueju.rawValue
    @AppStorage(PoemMeter.storageKey) private var meterRawValue = PoemMeter.five.rawValue
    @AppStorage(SealStampStyle.storageKey) private var sealStyleRawValue = SealStampStyle.zhuwen.rawValue
    @AppStorage(SealStampView.storageKey) private var sealName = ""
    @AppStorage(PoemTextLayout.storageKey) private var usesVerticalText = true
    @AppStorage("poemTypefaceMigratedToHuiwenDefault") private var migratedToHuiwenDefault = false
    @AppStorage("poemScriptMigratedToSimplifiedDefault") private var migratedToSimplifiedDefault = false
    @AppStorage(AppReviewPrompt.completedFirstPoemKey) private var completedFirstPoem = false
    @AppStorage(AppReviewPrompt.requestedAfterFirstPoemKey) private var requestedReviewAfterFirstPoem = false
    @ObservedObject private var store = StoreManager.shared
    @StateObject private var locationProvider = PoemLocationProvider()
    @State private var stage: ComposeStage = .heart
    @State private var selectedMood = PoetrySeed.themeBatches[0][0]
    @State private var selectedSetting = PoetrySeed.settings[0]
    @State private var selectedFeeling = PoetrySeed.feelings[0]
    @State private var selectedImage = PoetrySeed.images[0]
    @State private var homeImages = PoetrySeed.images
    @State private var selectedLines: [String] = []
    @State private var currentLineIndex = 0
    @State private var savedPoems = PoemArchiveStore.load()
    @State private var isRefreshingImages = false
    @State private var recentHomeImageTitles: [String] = PoetrySeed.images.map(\.title)
    @State private var selectedPoemForPreview: SavedPoem?
    @State private var hasCompletedCurrentPoem = false
    @State private var currentSavedPoem: SavedPoem?

    private var poemForm: PoemFormSpec {
        PoemFormSpec(
            structure: PoemStructure(rawValue: structureRawValue) ?? .jueju,
            meter: PoemMeter(rawValue: meterRawValue) ?? .five
        )
    }

    /// Downstream image and verse matching expects a single mood value. Keep the
    /// theme and feeling independent in the UI, then combine their semantic tags
    /// here so both choices shape the rest of the composition flow.
    private var compositionMood: MoodSeed {
        MoodSeed(
            id: selectedFeeling.lineFamily,
            title: "\(selectedMood.title) · \(selectedFeeling.title)",
            englishTitle: "\(selectedMood.englishTitle ?? selectedMood.title) · \(selectedFeeling.englishTitle)",
            tags: selectedMood.tags + selectedFeeling.tags
        )
    }

    private var hasPremiumAccess: Bool {
        store.isPremium
    }

    private var completedPoemBackground: PoemBackground {
        suggestedBackground(for: selectedLines)
    }

    private var stageBackgroundOverride: PoemBackground? {
        guard case .finish = stage else { return nil }
        return completedPoemBackground
    }

    var body: some View {
        ZStack {
            PaperBackground(backgroundOverride: stageBackgroundOverride)

            switch stage {
            case .heart:
                HeartQuestionView(
                    selectedTheme: $selectedMood,
                    selectedSetting: $selectedSetting,
                    selectedFeeling: $selectedFeeling,
                    structureRawValue: $structureRawValue,
                    meterRawValue: $meterRawValue,
                    onNext: {
                        let mood = compositionMood
                        let fallback = PoetrySeed.images(for: mood, setting: selectedSetting)
                        homeImages = []
                        isRefreshingImages = true
                        stage = .image
                        loadHomeImages(for: mood, fallback: fallback)
                    }
                )
            case .image:
                ImagePickingView(
                    mood: compositionMood,
                    setting: selectedSetting,
                    images: homeImages,
                    selectedImage: $selectedImage,
                    onNext: {
                        startPoem()
                    },
                    onBack: {
                        isRefreshingImages = false
                        stage = .heart
                    },
                    onRefresh: refreshHomeImages,
                    isRefreshing: isRefreshingImages
                )
            case .line:
                LinePickingView(
                    mood: compositionMood,
                    setting: selectedSetting,
                    image: selectedImage,
                    poemForm: poemForm,
                    lineIndex: currentLineIndex,
                    selectedLines: selectedLines,
                    onPick: pickLine,
                    onBackToImage: backToImagePicking,
                    onBackLine: backToPreviousLine
                )
            case .finish:
                FinishedPoemView(
                    mood: compositionMood,
                    image: selectedImage,
                    lines: selectedLines,
                    background: completedPoemBackground,
                    onReviseLine: { index, text in
                        // Editing only rewrites the text in place; it never
                        // returns to the line-picking step.
                        guard selectedLines.indices.contains(index) else { return }
                        // The finished poem was auto-saved; drop it so the
                        // revised version replaces it instead of duplicating.
                        if let currentSavedPoem {
                            savedPoems = PoemArchiveStore.delete(currentSavedPoem)
                            self.currentSavedPoem = nil
                        }
                        selectedLines[index] = text
                        archiveCompletedPoem(lines: selectedLines)
                    },
                    onSave: { poem in
                        savedPoems = PoemArchiveStore.save(poem)
                        currentSavedPoem = poem
                        hasCompletedCurrentPoem = true
                    },
                    onOpenArchive: {
                        // The composer resets itself when this tab becomes active again.
                        onOpenArchive()
                        requestReviewAfterFirstPoemIfNeeded()
                    },
                    onDelete: {
                        // Finished poems are saved during their reveal so they
                        // survive an interrupted transition. Deleting here
                        // explicitly discards that temporary saved copy.
                        if let currentSavedPoem {
                            savedPoems = PoemArchiveStore.delete(currentSavedPoem)
                        }
                        restartPoem()
                    }
                )
            }

            if stage == .heart {
                ArchiveEntryButton(count: savedPoems.count)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.trailing, 22)
                .padding(.top, 20)
            }
        }
        .foregroundStyle(Color.ink)
        .environment(\.poemTypeface, PoemTypeface(rawValue: typefaceRawValue) ?? .kaiti)
        .environment(\.poemScript, PoemScript(rawValue: scriptRawValue) ?? .simplified)
        .environmentObject(locationProvider)
        .fullScreenCover(item: $selectedPoemForPreview) { poem in
            PoemSharePreviewView(
                imageTitle: poem.imageTitle,
                lines: poem.lines,
                locationMark: PoemLocationPreference.visible(poem.locationText),
                lunarDateText: poem.lunarDateText,
                dayPeriodText: poem.dayPeriodText
            )
        }
        .onAppear {
            // Chinese composition is intentionally presented as traditional vertical verse.
            usesVerticalText = true
            migrateDefaultTypefaceIfNeeded()
            migrateDefaultScriptIfNeeded()
            resetPremiumSelectionsIfNeeded()
        }
        .onChange(of: isActive) { _, isNowActive in
            if isNowActive {
                savedPoems = PoemArchiveStore.load()
                return
            }
            guard hasCompletedCurrentPoem, stage == .finish else { return }
            // Wait out the push / tab transition so the reset happens off screen.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                restartPoem()
            }
        }
    }

    private func migrateDefaultTypefaceIfNeeded() {
        guard !migratedToHuiwenDefault else { return }
        if typefaceRawValue == PoemTypeface.wenyue.rawValue || typefaceRawValue == PoemTypeface.wenkai.rawValue {
            typefaceRawValue = PoemTypeface.kaiti.rawValue
        }
        migratedToHuiwenDefault = true
    }

    private func migrateDefaultScriptIfNeeded() {
        guard !migratedToSimplifiedDefault else { return }
        if scriptRawValue == PoemScript.traditional.rawValue {
            scriptRawValue = PoemScript.simplified.rawValue
        }
        migratedToSimplifiedDefault = true
    }

    private func resetPremiumSelectionsIfNeeded() {
        guard !hasPremiumAccess else { return }
        if SealStampStyle(rawValue: sealStyleRawValue)?.isFree == false {
            sealStyleRawValue = SealStampStyle.zhuwen.rawValue
        }
    }

    private func startPoem() {
        selectedLines.removeAll()
        currentLineIndex = 0
        stage = .line
    }

    private func pickLine(_ line: String) {
        if selectedLines.count > currentLineIndex {
            selectedLines[currentLineIndex] = line
        } else {
            selectedLines.append(line)
        }

        if currentLineIndex >= poemForm.lastLineIndex {
            archiveCompletedPoem(lines: selectedLines)
            completedFirstPoem = true
            stage = .finish
        } else {
            currentLineIndex += 1
        }
    }

    private func backToPreviousLine() {
        guard currentLineIndex > 0 else { return }
        let previousIndex = currentLineIndex - 1
        selectedLines = Array(selectedLines.prefix(previousIndex))
        currentLineIndex = previousIndex
    }

    private func backToImagePicking() {
        selectedLines.removeAll()
        currentLineIndex = 0
        stage = .image
    }

    /// The final line is the user's explicit completion action. Persist it before
    /// starting the reveal so a tab switch cannot make a finished poem disappear.
    private func archiveCompletedPoem(lines: [String]) {
        let inscriptionDate = PoemInscriptionDate.current
        let place = locationProvider.inscriptionPlace ?? locationProvider.cityName
        let poem = SavedPoem(
            createdAt: Date(),
            moodTitle: compositionMood.title,
            imageTitle: selectedImage.title,
            lines: lines,
            locationText: place.map { compactInscriptionText("於\($0)") },
            lunarDateText: inscriptionDate.lunarDateText,
            dayPeriodText: inscriptionDate.dayPeriodText,
            typefaceRawValue: typefaceRawValue,
            backgroundRawValue: suggestedBackground(for: lines).rawValue,
            usesVerticalText: usesVerticalText,
            sealName: sealName,
            scriptRawValue: scriptRawValue,
            sealStyleRawValue: UserDefaults.standard.string(forKey: SealStampStyle.storageKey),
            sealTransliteration: UserDefaults.standard.string(forKey: NameTransliterator.overrideStorageKey),
            shadowRawValue: UserDefaults.standard.string(forKey: ShadowStyle.storageKey)
        )

        savedPoems = PoemArchiveStore.save(poem)
        currentSavedPoem = poem
        hasCompletedCurrentPoem = true
    }

    /// The chosen theme and image are part of the poem's intent, so include
    /// them alongside the final lines when selecting its paper. Suggestions
    /// deliberately include member papers; access is checked only when sharing.
    private func suggestedBackground(for lines: [String]) -> PoemBackground {
        let semanticText = ([compositionMood.title, selectedSetting.title, selectedImage.title] + lines)
            .joined(separator: " ")
        return PoemBackground.suggested(for: semanticText)
    }

    private func restartPoem() {
        selectedMood = PoetrySeed.themeBatches[0][0]
        selectedSetting = PoetrySeed.settings[0]
        selectedFeeling = PoetrySeed.feelings[0]
        selectedLines.removeAll()
        currentLineIndex = 0
        homeImages = PoetrySeed.images
        isRefreshingImages = false
        savedPoems = PoemArchiveStore.load()
        hasCompletedCurrentPoem = false
        currentSavedPoem = nil
        stage = .heart
    }

    private func requestReviewAfterFirstPoemIfNeeded() {
        guard completedFirstPoem, !requestedReviewAfterFirstPoem else { return }
        requestedReviewAfterFirstPoem = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            AppReviewPrompt.request()
        }
    }

    private func refreshHomeImages() {
        loadHomeImages(
            for: compositionMood,
            fallback: PoetrySeed.images(for: compositionMood, setting: selectedSetting)
        )
    }

    private func loadHomeImages(for mood: MoodSeed, fallback: [ImageSeed]) {
        if isRefreshingImages && !homeImages.isEmpty { return }
        isRefreshingImages = true
        let freshImages = PoetrySeed.nonRepeatingImages(fallback, excluding: recentHomeImageTitles)
        homeImages = freshImages
        rememberHomeImages(freshImages)
        selectedImage = freshImages.first ?? PoetrySeed.images[0]
        isRefreshingImages = false
    }

    private func rememberHomeImages(_ images: [ImageSeed]) {
        let updated = recentHomeImageTitles + images.map(\.title)
        recentHomeImageTitles = Array(updated.suffix(18))
    }
}


private enum ComposeStage {
    case heart
    case image
    case line
    case finish
}

// MARK: - Home View

private struct HomeView: View {
    @Environment(\.poemTypeface) private var typeface
    @Environment(\.poemScript) private var script
    @AppStorage(SealStampView.storageKey) private var sealName = ""
    let savedPoems: [SavedPoem]
    let onCompose: () -> Void
    let onOpenPoem: (SavedPoem) -> Void

    private var dailyQuote: DailyPoemQuote.Quote {
        DailyPoemQuote.today()
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let timeGreeting: String
        switch hour {
        case 5...7:
            timeGreeting = AppLanguage.copy("晨安", "Good morning")
        case 8...10:
            timeGreeting = AppLanguage.copy("日安", "Good morning")
        case 11...13:
            timeGreeting = AppLanguage.copy("午安", "Good afternoon")
        case 14...16:
            timeGreeting = AppLanguage.copy("日暮將至", "Good afternoon")
        case 17...18:
            timeGreeting = AppLanguage.copy("暮安", "Good evening")
        case 19...22:
            timeGreeting = AppLanguage.copy("夜安", "Good evening")
        default:
            timeGreeting = AppLanguage.copy("夜深了", "It's late")
        }
        if sealName.isEmpty {
            return timeGreeting
        }
        return AppLanguage.isEnglish ? "\(timeGreeting), \(sealName)" : "\(sealName)　\(timeGreeting)"
    }

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14),
    ]

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                // Top spacer for status bar + buttons
                Spacer().frame(height: 140)

                // Greeting
                Text(greeting.poemScript(script))
                    .font(typeface.font(size: 16))
                    .foregroundStyle(Color.mutedInk)
                    .padding(.bottom, 32)

                // Daily poem quote — vertical
                VStack(spacing: 20) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(Array(dailyQuote.lines.enumerated()).reversed(), id: \.offset) { _, line in
                            VerticalText(line.poemScript(script), font: typeface.font(size: 20), color: .ink, spacing: 8)
                        }
                    }

                    Text("\(dailyQuote.author.poemScript(script))《\(dailyQuote.title.poemScript(script))》")
                        .font(typeface.font(size: 11))
                        .foregroundStyle(Color.mutedInk)
                }
                .padding(.bottom, 40)

                // Compose button
                SealTextButton(title: AppLanguage.copy("撰", "Compose"), action: onCompose)
                    .padding(.bottom, 48)

                // Saved poems — two-column grid
                if !savedPoems.isEmpty {
                    VStack(spacing: 18) {
                        Text(AppLanguage.copy("往日詩作", "Past poems").poemScript(script))
                            .font(typeface.font(size: 13))
                            .foregroundStyle(Color.mutedInk)

                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(savedPoems.prefix(10)) { poem in
                                SavedPoemCard(poem: poem)
                                    .onTapGesture { onOpenPoem(poem) }
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                }

                Spacer().frame(height: 60)
            }
        }
    }
}

private struct SavedPoemCard: View {
    @Environment(\.poemTypeface) private var typeface
    @Environment(\.poemScript) private var script
    let poem: SavedPoem

    private var backgroundImage: PoemBackground {
        let images = PoemBackground.imageBackgrounds
        guard !images.isEmpty else { return .none }
        let index = abs(poem.id.hashValue) % images.count
        return images[index]
    }

    var body: some View {
        ZStack {
            // Subtle background image
            if backgroundImage != .none, let uiImage = UIImage(named: backgroundImage.rawValue) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .opacity(0.08)
            }

            VStack(spacing: 0) {
                // Poem lines — vertical, right to left
                HStack(alignment: .top, spacing: 8) {
                    ForEach(Array(poem.lines.enumerated()).reversed(), id: \.offset) { _, line in
                        VerticalText(line, font: typeface.font(size: 12), spacing: 3)
                    }
                }
                .padding(.top, 16)
                .padding(.horizontal, 8)

                Spacer()

                // Image title
                Text(poem.imageTitle)
                    .font(typeface.font(size: 10))
                    .foregroundStyle(Color.mutedInk)
                    .lineLimit(1)
                    .padding(.bottom, 12)
            }
        }
        .frame(height: 200)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.75))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.ink.opacity(0.06), lineWidth: 0.5)
        )
    }
}

// MARK: - Daily Poem Quotes

private enum DailyPoemQuote {
    struct Quote {
        let lines: [String]
        let author: String
        let title: String
    }

    private static let byMonth: [[Quote]] = [
        // 正月
        [
            Quote(lines: ["爆竹聲中一歲除", "春風送暖入屠蘇"], author: "王安石", title: "元日"),
            Quote(lines: ["千門萬戶曈曈日", "總把新桃換舊符"], author: "王安石", title: "元日"),
        ],
        // 二月
        [
            Quote(lines: ["不知細葉誰裁出", "二月春風似剪刀"], author: "賀知章", title: "詠柳"),
            Quote(lines: ["等閒識得東風面", "萬紫千紅總是春"], author: "朱熹", title: "春日"),
        ],
        // 三月
        [
            Quote(lines: ["故人西辭黃鶴樓", "煙花三月下揚州"], author: "李白", title: "送孟浩然之廣陵"),
            Quote(lines: ["春色滿園關不住", "一枝紅杏出牆來"], author: "葉紹翁", title: "遊園不值"),
        ],
        // 四月
        [
            Quote(lines: ["小荷才露尖尖角", "早有蜻蜓立上頭"], author: "楊萬里", title: "小池"),
            Quote(lines: ["接天蓮葉無窮碧", "映日荷花別樣紅"], author: "楊萬里", title: "曉出淨慈寺送林子方"),
        ],
        // 五月
        [
            Quote(lines: ["黃梅時節家家雨", "青草池塘處處蛙"], author: "趙師秀", title: "約客"),
            Quote(lines: ["稻花香裡說豐年", "聽取蛙聲一片"], author: "辛棄疾", title: "西江月"),
        ],
        // 六月
        [
            Quote(lines: ["水光瀲灩晴方好", "山色空濛雨亦奇"], author: "蘇軾", title: "飲湖上初晴後雨"),
            Quote(lines: ["欲把西湖比西子", "淡妝濃抹總相宜"], author: "蘇軾", title: "飲湖上初晴後雨"),
        ],
        // 七月
        [
            Quote(lines: ["銀燭秋光冷畫屏", "輕羅小扇撲流螢"], author: "杜牧", title: "秋夕"),
            Quote(lines: ["金風玉露一相逢", "便勝卻人間無數"], author: "秦觀", title: "鵲橋仙"),
        ],
        // 八月
        [
            Quote(lines: ["但願人長久", "千里共嬋娟"], author: "蘇軾", title: "水調歌頭"),
            Quote(lines: ["舉頭望明月", "低頭思故鄉"], author: "李白", title: "靜夜思"),
        ],
        // 九月
        [
            Quote(lines: ["停車坐愛楓林晚", "霜葉紅於二月花"], author: "杜牧", title: "山行"),
            Quote(lines: ["獨在異鄉為異客", "每逢佳節倍思親"], author: "王維", title: "九月九日憶山東兄弟"),
        ],
        // 十月
        [
            Quote(lines: ["千山鳥飛絕", "萬徑人蹤滅"], author: "柳宗元", title: "江雪"),
            Quote(lines: ["柴門聞犬吠", "風雪夜歸人"], author: "劉長卿", title: "逢雪宿芙蓉山主人"),
        ],
        // 冬月
        [
            Quote(lines: ["牆角數枝梅", "凌寒獨自開"], author: "王安石", title: "梅花"),
            Quote(lines: ["晚來天欲雪", "能飲一杯無"], author: "白居易", title: "問劉十九"),
        ],
        // 臘月
        [
            Quote(lines: ["忽如一夜春風來", "千樹萬樹梨花開"], author: "岑參", title: "白雪歌送武判官歸京"),
            Quote(lines: ["風雨送春歸", "飛雪迎春到"], author: "毛澤東", title: "卜算子詠梅"),
        ],
    ]

    static func today() -> Quote {
        var cal = Calendar(identifier: .chinese)
        cal.timeZone = .current
        let comps = cal.dateComponents([.month, .day], from: Date())
        let month = max(1, min(12, comps.month ?? 1))
        let day = comps.day ?? 1
        let pool = byMonth[month - 1]
        let index = (day - 1) % pool.count
        return pool[index]
    }
}

// MARK: - Heart Question View

private struct PoemFormMenu: View {
    @Environment(\.poemTypeface) private var typeface
    @Environment(\.poemScript) private var script
    @Binding var structureRawValue: String
    @Binding var meterRawValue: String

    private var form: PoemFormSpec {
        PoemFormSpec(
            structure: PoemStructure(rawValue: structureRawValue) ?? .jueju,
            meter: PoemMeter(rawValue: meterRawValue) ?? .five
        )
    }

    private let options = [
        PoemFormSpec(structure: .jueju, meter: .five),
        PoemFormSpec(structure: .jueju, meter: .seven),
        PoemFormSpec(structure: .lushi, meter: .five),
        PoemFormSpec(structure: .lushi, meter: .seven)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(AppLanguage.copy("詩體", "Poem form").poemScript(script))
                    .font(typeface.font(size: 16))
                    .foregroundStyle(Color.ink)

                Spacer(minLength: 12)

                Text(form.displayName.poemScript(script))
                    .font(AppLanguage.isEnglish ? .system(size: 11, weight: .medium) : typeface.font(size: 12))
                    .foregroundStyle(Color.cinnabar)
                    .lineLimit(1)
            }

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
                spacing: 6
            ) {
                ForEach(options) { option in
                    formOption(option)
                }
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.56))
                .strokeBorder(Color.ink.opacity(0.07), lineWidth: 0.8)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(AppLanguage.copy("詩體選項", "Poem form choices").poemScript(script))
    }

    private func formOption(_ option: PoemFormSpec) -> some View {
        let isSelected = option == form

        return Button {
            meterRawValue = option.meter.rawValue
            structureRawValue = option.structure.rawValue
            SensoryFeedback.lightTap()
        } label: {
            VStack(spacing: 2) {
                Text(option.displayName.poemScript(script))
                    .font(AppLanguage.isEnglish ? .system(size: 11, weight: .semibold, design: .serif) : typeface.font(size: 14))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Text(
                    AppLanguage.copy(
                        "\(option.characterCount)字 × \(option.lineCount)句",
                        "\(option.characterCount) × \(option.lineCount)"
                    ).poemScript(script)
                )
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .monospacedDigit()
                .opacity(isSelected ? 0.82 : 0.58)
            }
            .foregroundStyle(isSelected ? .white : Color.ink)
            .frame(maxWidth: .infinity, minHeight: 38)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.cinnabar : Color.white.opacity(0.72))
                    .strokeBorder(
                        isSelected ? Color.cinnabar.opacity(0.52) : Color.ink.opacity(0.08),
                        lineWidth: isSelected ? 1.1 : 0.8
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.displayName.poemScript(script))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct HeartQuestionView: View {
    @Environment(\.poemTypeface) private var typeface
    @Environment(\.poemScript) private var script
    @Binding var selectedTheme: MoodSeed
    @Binding var selectedSetting: SettingSeed
    @Binding var selectedFeeling: FeelingSeed
    @Binding var structureRawValue: String
    @Binding var meterRawValue: String
    let onNext: () -> Void
    var onBack: (() -> Void)? = nil

    private var form: PoemFormSpec {
        PoemFormSpec(
            structure: PoemStructure(rawValue: structureRawValue) ?? .jueju,
            meter: PoemMeter(rawValue: meterRawValue) ?? .five
        )
    }

    private var selectionSummary: String {
        if AppLanguage.isEnglish {
            return "\(selectedTheme.englishTitle ?? selectedTheme.title) · \(selectedSetting.englishTitle) · \(selectedFeeling.englishTitle)"
        }
        return "\(selectedTheme.title) · \(selectedSetting.title) · \(selectedFeeling.title)".poemScript(script)
    }

    var body: some View {
        GeometryReader { proxy in
            // This is the complete first step, rather than a feed. Keeping it in
            // the viewport prevents an accidental vertical drag from hiding the
            // primary action on shorter phones.
            let isCompactHeight = proxy.size.height < 760
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(AppLanguage.copy("成诗", "Compose").poemScript(script))
                            .font(typeface.font(size: 29))
                            .foregroundStyle(Color.ink)
                        Text(AppLanguage.copy("择一题，定一境，观一心", "Choose a theme, setting, and feeling").poemScript(script))
                            .font(AppLanguage.isEnglish ? .system(size: 12, design: .serif) : typeface.font(size: 12))
                            .foregroundStyle(Color.mutedInk)
                    }
                    Spacer()
                    if let onBack {
                        QuietBackButton(title: AppLanguage.copy("返回", "Back"), action: onBack)
                    }
                }
                .frame(minHeight: 48)
                .padding(.horizontal, 22)
                .padding(.top, isCompactHeight ? 12 : 20)

                HStack(spacing: 8) {
                    Text(AppLanguage.copy("已选", "Selected").poemScript(script))
                        .font(typeface.font(size: 12))
                        .foregroundStyle(Color.cinnabar)

                    Text(selectionSummary)
                        .font(typeface.font(size: 13))
                        .foregroundStyle(Color.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    Spacer(minLength: 8)

                    Text(form.displayName.poemScript(script))
                        .font(typeface.font(size: 11))
                        .foregroundStyle(Color.mutedInk)
                        .lineLimit(1)
                }
                .padding(.horizontal, 22)
                .padding(.top, isCompactHeight ? 6 : 10)

                PoemFormMenu(structureRawValue: $structureRawValue, meterRawValue: $meterRawValue)
                    .padding(.horizontal, 22)
                    .padding(.top, isCompactHeight ? 8 : 10)

                ThemePickerSection(
                    selectedTheme: $selectedTheme,
                    selectedSetting: $selectedSetting,
                    selectedFeeling: $selectedFeeling,
                    usesCompactSpacing: isCompactHeight
                )
                    .padding(.horizontal, 22)
                    .padding(.top, isCompactHeight ? 10 : 14)

                Spacer(minLength: isCompactHeight ? 8 : 16)

                SealTextButton(title: AppLanguage.copy("撰", "Compose"), action: onNext)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom, isCompactHeight ? 12 : 24)
            }
            .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .top)
        }
        .spotlightOverlay(for: [.selectMood])
    }
}

private struct SettingOptionButton: View {
    @Environment(\.poemTypeface) private var typeface
    @Environment(\.poemScript) private var script
    let setting: SettingSeed
    let isSelected: Bool
    let action: () -> Void

    private var displayTitle: String {
        guard AppLanguage.isEnglish else { return setting.title.poemScript(script) }
        return setting.englishTitle
    }

    var body: some View {
        Button(action: action) {
            Text(displayTitle)
                .font(AppLanguage.isEnglish ? .system(size: 11, weight: .medium, design: .serif) : typeface.font(size: 13))
                .foregroundStyle(isSelected ? .white : Color.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity, minHeight: 38)
                .background {
                    Capsule()
                        .fill(isSelected ? Color.cinnabar : Color.white.opacity(0.72))
                        .stroke(isSelected ? Color.cinnabar : Color.mutedInk.opacity(0.12), lineWidth: 0.8)
                }
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct ThemePickerSection: View {
    @Environment(\.poemTypeface) private var typeface
    @Environment(\.poemScript) private var script
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var selectedTheme: MoodSeed
    @Binding var selectedSetting: SettingSeed
    @Binding var selectedFeeling: FeelingSeed
    let usesCompactSpacing: Bool
    @State private var themeBatchIndex = 0
    @State private var settingBatchIndex = 0
    @State private var feelingBatchIndex = 0

    // Each picker exposes a complete 2 × 3 grid before cycling to the next batch.
    private let themeBatchSize = 6
    private let settingBatchSize = 6
    private let feelingBatchSize = 6

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)
    }

    private var themes: [MoodSeed] {
        batchItems(from: allThemes, size: themeBatchSize, batchIndex: themeBatchIndex)
    }

    private var settings: [SettingSeed] {
        batchItems(from: PoetrySeed.settings, size: settingBatchSize, batchIndex: settingBatchIndex)
    }

    private var feelings: [FeelingSeed] {
        batchItems(from: PoetrySeed.feelings, size: feelingBatchSize, batchIndex: feelingBatchIndex)
    }

    private var allThemes: [MoodSeed] {
        PoetrySeed.themeBatches.flatMap { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: usesCompactSpacing ? 8 : 14) {
            VStack(alignment: .leading, spacing: usesCompactSpacing ? 4 : 6) {
                optionHeader(
                    AppLanguage.copy("主题", "Theme"),
                    accessibilityLabel: AppLanguage.copy("换一批主题", "Show more themes"),
                    action: showNextThemeBatch
                )
                LazyVGrid(columns: columns, alignment: .leading, spacing: usesCompactSpacing ? 6 : 8) {
                    ForEach(Array(themes.enumerated()), id: \.element.id) { index, theme in
                        ThemeOptionButton(
                            theme: theme,
                            isSelected: selectedTheme.id == theme.id,
                            isSpotlightTarget: index == 0
                        ) {
                            selectedTheme = theme
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: usesCompactSpacing ? 4 : 6) {
                optionHeader(
                    AppLanguage.copy("地点", "Setting"),
                    accessibilityLabel: AppLanguage.copy("换一批地点", "Show more settings"),
                    action: showNextSettingBatch
                )
                LazyVGrid(columns: columns, alignment: .leading, spacing: usesCompactSpacing ? 6 : 8) {
                    ForEach(settings) { setting in
                        SettingOptionButton(
                            setting: setting,
                            isSelected: selectedSetting.id == setting.id
                        ) {
                            selectedSetting = setting
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: usesCompactSpacing ? 4 : 6) {
                optionHeader(
                    AppLanguage.copy("心境", "Feeling"),
                    accessibilityLabel: AppLanguage.copy("换一批心境", "Show more feelings"),
                    action: showNextFeelingBatch
                )
                LazyVGrid(columns: columns, alignment: .leading, spacing: usesCompactSpacing ? 6 : 8) {
                    ForEach(feelings) { feeling in
                        FeelingOptionButton(
                            feeling: feeling,
                            isSelected: selectedFeeling.id == feeling.id
                        ) {
                            selectedFeeling = feeling
                        }
                    }
                }
            }
        }
        .padding(usesCompactSpacing ? 10 : 12)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.46))
                .strokeBorder(Color.ink.opacity(0.07), lineWidth: 0.8)
        }
        .onAppear {
            if let matchingIndex = allThemes.firstIndex(where: { $0.id == selectedTheme.id }) {
                themeBatchIndex = matchingIndex / themeBatchSize
            }
            if let matchingIndex = PoetrySeed.settings.firstIndex(where: { $0.id == selectedSetting.id }) {
                settingBatchIndex = matchingIndex / settingBatchSize
            }
            if let matchingIndex = PoetrySeed.feelings.firstIndex(where: { $0.id == selectedFeeling.id }) {
                feelingBatchIndex = matchingIndex / feelingBatchSize
            }
        }
    }

    private func optionHeader(_ title: String, accessibilityLabel: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Text(title.poemScript(script))
                .font(typeface.font(size: 17))
                .foregroundStyle(Color.ink)

            Spacer()

            BatchRefreshButton(accessibilityLabel: accessibilityLabel, action: action)
        }
    }

    private func batchItems<Item>(from items: [Item], size: Int, batchIndex: Int) -> [Item] {
        guard !items.isEmpty else { return [] }
        let start = (batchIndex * size) % items.count
        return (0..<min(size, items.count)).map { items[(start + $0) % items.count] }
    }

    private func showNextThemeBatch() {
        updateBatch {
            themeBatchIndex = nextBatchIndex(
                current: themeBatchIndex,
                itemCount: allThemes.count,
                batchSize: themeBatchSize
            )
            if let firstTheme = themes.first {
                selectedTheme = firstTheme
            }
        }
    }

    private func showNextSettingBatch() {
        updateBatch {
            settingBatchIndex = nextBatchIndex(
                current: settingBatchIndex,
                itemCount: PoetrySeed.settings.count,
                batchSize: settingBatchSize
            )
            if let firstSetting = settings.first {
                selectedSetting = firstSetting
            }
        }
    }

    private func showNextFeelingBatch() {
        updateBatch {
            feelingBatchIndex = nextBatchIndex(
                current: feelingBatchIndex,
                itemCount: PoetrySeed.feelings.count,
                batchSize: feelingBatchSize
            )
            if let firstFeeling = feelings.first {
                selectedFeeling = firstFeeling
            }
        }
    }

    private func nextBatchIndex(current: Int, itemCount: Int, batchSize: Int) -> Int {
        let count = max(1, (itemCount + batchSize - 1) / batchSize)
        return (current + 1) % count
    }

    private func updateBatch(_ update: @escaping () -> Void) {
        if reduceMotion {
            update()
        } else {
            withAnimation(.easeOut(duration: 0.2)) {
                update()
            }
        }
    }
}

private struct BatchRefreshButton: View {
    @Environment(\.poemTypeface) private var typeface
    @Environment(\.poemScript) private var script
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button {
            SensoryFeedback.lightTap()
            action()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 9, weight: .semibold))
                Text(AppLanguage.copy("换一批", "More").poemScript(script))
                    .font(AppLanguage.isEnglish ? .system(size: 10, weight: .medium) : typeface.font(size: 10))
            }
            .foregroundStyle(Color.cinnabar)
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(.white.opacity(0.72), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(Color.cinnabar.opacity(0.32), lineWidth: 0.8)
            }
            .frame(minHeight: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel.poemScript(script))
    }
}

private struct FeelingOptionButton: View {
    @Environment(\.poemTypeface) private var typeface
    @Environment(\.poemScript) private var script
    let feeling: FeelingSeed
    let isSelected: Bool
    let action: () -> Void

    private var displayTitle: String {
        AppLanguage.isEnglish ? feeling.englishTitle : feeling.title.poemScript(script)
    }

    var body: some View {
        Button(action: action) {
            Text(displayTitle)
                .font(AppLanguage.isEnglish ? .system(size: 11, weight: .medium, design: .serif) : typeface.font(size: 13))
                .foregroundStyle(isSelected ? .white : Color.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity, minHeight: 38)
                .background {
                    Capsule()
                        .fill(isSelected ? Color.cinnabar : Color.white.opacity(0.72))
                        .stroke(isSelected ? Color.cinnabar : Color.mutedInk.opacity(0.12), lineWidth: 0.8)
                }
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct ThemeOptionButton: View {
    @Environment(\.poemTypeface) private var typeface
    @Environment(\.poemScript) private var script
    @Environment(\.spotlightGuide) private var spotlightGuide
    let theme: MoodSeed
    let isSelected: Bool
    let isSpotlightTarget: Bool
    let action: () -> Void

    private var displayTitle: String {
        guard AppLanguage.isEnglish else { return theme.title.poemScript(script) }
        return theme.englishTitle ?? theme.title.poemScript(script)
    }

    var body: some View {
        Button {
            action()
            if spotlightGuide.step == .selectMood && isSpotlightTarget {
                spotlightGuide.advance()
            }
        } label: {
            Text(displayTitle)
                .font(AppLanguage.isEnglish ? .system(size: 11, weight: .medium, design: .serif) : typeface.font(size: 13))
                .foregroundStyle(isSelected ? .white : Color.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity, minHeight: 38)
                .background {
                    Capsule()
                        .fill(isSelected ? Color.cinnabar : Color.white.opacity(0.72))
                        .stroke(isSelected ? Color.cinnabar : Color.mutedInk.opacity(0.12), lineWidth: 0.8)
                }
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
        .spotlightTarget(.selectMood, active: spotlightGuide.step == .selectMood && isSpotlightTarget)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct ImagePickingView: View {
    @Environment(\.poemTypeface) private var typeface
    @Environment(\.poemScript) private var script
    @Environment(\.spotlightGuide) private var spotlightGuide
    let mood: MoodSeed
    let setting: SettingSeed
    let images: [ImageSeed]
    @Binding var selectedImage: ImageSeed
    let onNext: () -> Void
    let onBack: () -> Void
    let onRefresh: () -> Void
    let isRefreshing: Bool

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                VStack(spacing: 0) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(AppLanguage.copy("擇題成詩", "Choose a title").poemScript(script))
                                .font(typeface.font(size: 22))
                                .foregroundStyle(Color.ink)
                            Text(
                                AppLanguage.isEnglish
                                    ? "\(mood.englishTitle ?? mood.title) · \(setting.englishTitle) · choose a title"
                                    : "\(mood.title) · \(setting.title) · 從下方選一題".poemScript(script)
                            )
                            .font(typeface.smallFont)
                            .foregroundStyle(Color.mutedInk)
                            .lineLimit(2)
                        }
                        Spacer()
                        QuietBackButton(title: AppLanguage.copy("返回", "Back"), action: onBack)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 52)
                    .padding(.bottom, 18)

                    Spacer()
                }
                .frame(width: size.width, height: size.height, alignment: .top)

                // Center: image choices
                ZStack {
                    if images.isEmpty && isRefreshing {
                        VerticalText(AppLanguage.copy("取意中", "Finding ideas"), style: .small, color: .mutedInk, spacing: 6)
                            .opacity(0.7)
                            .transition(.opacity)
                    } else {
                        HStack(alignment: .top, spacing: size.width * 0.13) {
                            ForEach(Array(images.enumerated()), id: \.element.id) { index, image in
                                let isSpotlightTarget = spotlightGuide.step == .selectImage && index == 0
                                ChoiceColumn(
                                    title: image.title,
                                    subtitle: image.subtitle,
                                    isSelected: selectedImage.id == image.id,
                                    isSpotlightTarget: isSpotlightTarget,
                                    action: {
                                        selectedImage = image
                                        if isSpotlightTarget {
                                            spotlightGuide.advance()
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                                onNext()
                                            }
                                        }
                                    }
                                )
                            }
                        }
                        .opacity(isRefreshing ? 0.45 : 1)
                        .transition(.opacity.combined(with: .offset(y: 10)))
                    }
                }
                .animation(.easeOut(duration: 0.5), value: images.isEmpty)
                .animation(.easeOut(duration: 0.35), value: images)
                .position(x: size.width * 0.50, y: size.height * 0.43)

                // Below choices: refresh and go share the same baseline.
                HStack(spacing: 28) {
                    SmallCircleButton(title: "換", action: onRefresh)
                        .opacity(isRefreshing ? 0.35 : 1)
                        .disabled(isRefreshing)

                    SmallCircleButton(title: "撰", action: onNext)
                        .opacity(images.isEmpty ? 0.35 : 1)
                        .allowsHitTesting(!images.isEmpty)
                }
                .position(x: size.width * 0.50, y: size.height * 0.64)

            }
            .frame(width: size.width, height: size.height)
        }
        .spotlightOverlay(for: [.selectImage])
    }
}

private enum LegacyPoemTextLayout {
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

private struct PoemLinesStack<Content: View>: View {
    let lines: [String]
    var spacing: CGFloat = 16
    var usesVerticalTextOverride: Bool? = nil
    @ViewBuilder let content: (Int, String) -> Content

    private var usesVerticalText: Bool {
        true
    }

    var body: some View {
        let indices = usesVerticalText ? Array(lines.indices.reversed()) : Array(lines.indices)
        let layout = usesVerticalText
            ? AnyLayout(HStackLayout(alignment: .top, spacing: spacing))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: spacing))
        layout {
            ForEach(indices, id: \.self) { index in
                content(index, lines[index])
            }
        }
    }
}

private struct ComposedPoemLine: View {
    @Environment(\.poemTypeface) private var typeface
    @Environment(\.poemScript) private var script
    let line: String
    var fontSize: CGFloat = 24
    var color: Color = .ink
    var usesVerticalTextOverride: Bool? = nil

    private var usesVerticalText: Bool {
        true
    }

    var body: some View {
        if usesVerticalText {
            VerticalText(line, font: typeface.font(size: fontSize), color: color, spacing: 5)
        } else {
            Text(line.poemScript(script))
                .font(typeface.font(size: fontSize))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

private struct LinePickingView: View {
    @Environment(\.poemTypeface) private var typeface
    @Environment(\.poemScript) private var script
    @Environment(\.spotlightGuide) private var spotlightGuide
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let mood: MoodSeed
    let setting: SettingSeed
    let image: ImageSeed
    let poemForm: PoemFormSpec
    let lineIndex: Int
    let selectedLines: [String]
    let onPick: (String) -> Void
    let onBackToImage: () -> Void
    let onBackLine: () -> Void
    @State private var choicesVisible = false
    @State private var pickedLine: String?
    @State private var cancelPendingPick = false
    @State private var refreshSeed = 0
    @State private var showSelfWrite = false
    @State private var selfWriteText = ""

    private var options: [String] {
        PoetrySeed.lines(
            for: mood,
            image: image,
            form: poemForm,
            index: lineIndex,
            selectedLines: selectedLines,
            refreshSeed: refreshSeed
        )
        .map { $0.poemScript(script) }
    }

    private var stepName: String {
        if poemForm.structure == .jueju {
            return ["起", "承", "轉", "合"][min(lineIndex, 3)]
        }
        switch lineIndex {
        case 0: return "起"
        case 1: return "承"
        case 2, 3: return "頷聯"
        case 4, 5: return "頸聯"
        default: return "合"
        }
    }

    private var artworkName: String {
        let context = "\(mood.title)\(setting.title)\(image.id)\(image.title)"
        if context.contains("雨") { return "bg_rain" }
        if context.contains("雪") || context.contains("寒") { return "bg_snow" }
        if context.contains("月") || context.contains("夜") || context.contains("燈") { return "bg_moon" }
        if context.contains("舟") || context.contains("渡") || context.contains("水") { return "bg_boat" }
        if context.contains("竹") || context.contains("茶") { return "bg_bamboo" }
        if context.contains("橋") || context.contains("巷") || context.contains("城") { return "bg_bridge" }
        if context.contains("春") || context.contains("花") { return "bg_spring" }
        return "bg_peaks"
    }

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(AppLanguage.copy("擇句成詩", "Compose a poem").poemScript(script))
                            .font(typeface.font(size: 22))
                            .foregroundStyle(Color.ink)
                        Text(AppLanguage.isEnglish
                            ? "\(setting.englishTitle) · \(poemForm.displayName) · choose one line at a time"
                            : "\(mood.title) · \(setting.title) · \(image.title) · \(poemForm.displayName)".poemScript(script))
                            .font(typeface.smallFont)
                            .foregroundStyle(Color.mutedInk)
                            .lineLimit(2)
                    }
                    Spacer()
                    QuietBackButton(title: "返回") {
                        cancelPendingPick = true
                        if lineIndex == 0 { onBackToImage() } else { onBackLine() }
                    }
                    .opacity(pickedLine == nil ? 1 : 0.35)
                    .disabled(pickedLine != nil)
                }
                .padding(.horizontal, 24)
                .padding(.top, 52)
                .padding(.bottom, 18)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 22) {
                        ZStack {
                            Image(artworkName)
                                .resizable()
                                .scaledToFill()
                                .opacity(0.2)
                                .accessibilityHidden(true)

                            LinearGradient(
                                colors: [Color.white.opacity(0.84), Color.white.opacity(0.36), Color.white.opacity(0.74)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )

                            VStack(spacing: 18) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(image.title.poemScript(script))
                                        .font(typeface.accentFont)
                                        .foregroundStyle(Color.ink)
                                    Spacer()
                                    Text("\(lineIndex + 1) / \(poemForm.lineCount)")
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .monospacedDigit()
                                        .foregroundStyle(Color.cinnabar)
                                }

                                HStack(alignment: .top, spacing: poemForm.lineCount > 4 ? 8 : 15) {
                                    ForEach(Array((0..<poemForm.lineCount).reversed()), id: \.self) { index in
                                        if index < selectedLines.count {
                                            ComposedPoemLine(
                                                line: selectedLines[index],
                                                fontSize: poemForm.lineCount > 4 ? 16 : 20
                                            )
                                            .transition(.opacity.combined(with: .offset(y: 8)))
                                        } else {
                                            VersePlaceholderColumn(
                                                characterCount: poemForm.characterCount,
                                                isCurrent: index == lineIndex
                                            )
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity, minHeight: poemForm.characterCount == 7 ? 150 : 118)

                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(Color.cinnabar)
                                        .frame(width: 5, height: 5)
                                    Text(poemForm.role(for: lineIndex).poemScript(script))
                                        .font(typeface.tinySealFont)
                                        .foregroundStyle(Color.mutedInk)
                                        .lineLimit(2)
                                    Spacer(minLength: 0)
                                }
                            }
                            .padding(20)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: poemForm.characterCount == 7 ? 286 : 254)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .strokeBorder(Color.ink.opacity(0.08), lineWidth: 0.8)
                        }
                        .shadow(color: Color.ink.opacity(0.07), radius: 14, x: 0, y: 7)
                        .animation(.easeOut(duration: 0.3), value: selectedLines)

                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .firstTextBaseline) {
                                Text((AppLanguage.isEnglish
                                    ? "Line \(lineIndex + 1)"
                                    : "第\(lineIndex + 1)句 · \(stepName)").poemScript(script))
                                    .font(typeface.accentFont)
                                    .foregroundStyle(Color.ink)
                                Spacer()
                                Text(AppLanguage.copy("選一句入詩", "Choose one line").poemScript(script))
                                    .font(typeface.tinySealFont)
                                    .foregroundStyle(Color.mutedInk)
                            }

                            VStack(spacing: 10) {
                                let guidedIndex = options.count > 1 ? 1 : 0
                                ForEach(Array(options.enumerated()), id: \.offset) { index, line in
                                    let isSpotlightTarget = spotlightGuide.step == .selectLine && index == guidedIndex
                                    CandidateLineRow(
                                        line: line,
                                        isPicked: pickedLine == line,
                                        isVisible: choicesVisible || pickedLine == line,
                                        isSpotlightTarget: isSpotlightTarget
                                    ) {
                                        if isSpotlightTarget { spotlightGuide.advance() }
                                        choose(line)
                                    }
                                }
                            }

                            HStack(spacing: 12) {
                                ComposerActionButton(
                                    title: AppLanguage.copy("換一批", "More lines").poemScript(script),
                                    systemName: "arrow.triangle.2.circlepath",
                                    action: refreshCandidates
                                )
                                .disabled(pickedLine != nil)

                                ComposerActionButton(
                                    title: AppLanguage.copy("自己寫", "Write my own").poemScript(script),
                                    systemName: "pencil.line"
                                ) {
                                    selfWriteText = ""
                                    showSelfWrite = true
                                }
                                .disabled(pickedLine != nil)
                            }
                            .padding(.top, 2)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, max(28, proxy.safeAreaInsets.bottom + 16))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .onAppear(perform: revealChoices)
        .onChange(of: lineIndex) {
            refreshSeed = 0
            revealChoices()
        }
        .sheet(isPresented: $showSelfWrite) {
            SelfWriteSheet(
                charCount: poemForm.characterCount,
                lineIndex: lineIndex,
                text: $selfWriteText
            ) { line in
                showSelfWrite = false
                choose(line)
            }
        }
        .spotlightOverlay(for: [.selectLine])
    }

    private func revealChoices() {
        choicesVisible = false
        pickedLine = nil
        cancelPendingPick = false
        if reduceMotion {
            choicesVisible = true
        } else {
            withAnimation(.easeOut(duration: 0.45).delay(0.08)) {
                choicesVisible = true
            }
        }
    }

    private func refreshCandidates() {
        guard pickedLine == nil else { return }
        SensoryFeedback.lightTap()
        withAnimation(.easeOut(duration: 0.22)) {
            refreshSeed += 1
        }
    }

    private func choose(_ line: String) {
        guard pickedLine == nil else { return }

        pickedLine = line
        choicesVisible = false
        SensoryFeedback.lightTap()

        DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0.05 : 0.42)) {
            guard !cancelPendingPick else { return }
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) {
                onPick(line)
            }
        }
    }
}

private struct VersePlaceholderColumn: View {
    let characterCount: Int
    let isCurrent: Bool

    var body: some View {
        VStack(spacing: 8) {
            ForEach(0..<characterCount, id: \.self) { _ in
                Circle()
                    .fill(isCurrent ? Color.cinnabar.opacity(0.34) : Color.mutedInk.opacity(0.14))
                    .frame(width: 3.5, height: 3.5)
            }
        }
        .frame(width: 20)
        .padding(.top, 5)
        .accessibilityHidden(true)
    }
}

private struct CandidateLineRow: View {
    @Environment(\.poemTypeface) private var typeface
    let line: String
    let isPicked: Bool
    let isVisible: Bool
    let isSpotlightTarget: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: isPicked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(isPicked ? Color.cinnabar : Color.mutedInk.opacity(0.35))
                Text(line)
                    .font(typeface.bodyFont)
                    .tracking(1.5)
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
            .padding(.horizontal, 14)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isPicked ? Color.cinnabar.opacity(0.1) : Color.white.opacity(0.68))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(
                                isPicked ? Color.cinnabar.opacity(0.72) : Color.ink.opacity(0.08),
                                lineWidth: isPicked ? 1.2 : 0.8
                            )
                    }
            }
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isPicked)
        .opacity(isVisible ? 1 : 0)
        .offset(y: isVisible ? 0 : 8)
        .spotlightTarget(.selectLine, active: isSpotlightTarget && isVisible, offset: CGSize(width: 0, height: 4))
        .accessibilityLabel(line)
        .accessibilityAddTraits(isPicked ? .isSelected : [])
    }
}

private struct ComposerActionButton: View {
    @Environment(\.poemTypeface) private var typeface
    let title: String
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemName)
                .font(typeface.smallFont)
                .foregroundStyle(Color.ink)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background {
                    Capsule()
                        .fill(Color.white.opacity(0.58))
                        .overlay {
                            Capsule().strokeBorder(Color.ink.opacity(0.1), lineWidth: 0.8)
                        }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct SelfWriteSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.poemTypeface) private var typeface
    @Environment(\.poemScript) private var script
    let charCount: Int
    let lineIndex: Int
    @Binding var text: String
    var editsExistingLine = false
    let onConfirm: (String) -> Void

    @FocusState private var isFocused: Bool

    private var cleanText: String {
        String(text.unicodeScalars.filter { CharacterSet.cjk.contains($0) }.prefix(charCount))
    }

    private var isValid: Bool {
        cleanText.count == charCount
    }

    private var roleHint: String {
        switch lineIndex {
        case 0: return AppLanguage.copy("取景，先立意象", "Begin with an image")
        case 1: return AppLanguage.copy("入情，把景转为心事", "Turn the scene toward feeling")
        case 2: return AppLanguage.copy("转折，让情绪有微妙变化", "Let the feeling shift")
        default: return AppLanguage.copy("收束，留下余味", "Close with a lingering note")
        }
    }

    var body: some View {
        ZStack {
            PaperBackground()

            VStack(spacing: 0) {
                // Header
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text((editsExistingLine
                            ? AppLanguage.copy("改第\(lineIndex + 1)句", "Edit line \(lineIndex + 1)")
                            : AppLanguage.copy("自書第\(lineIndex + 1)句", "Write line \(lineIndex + 1)")).poemScript(script))
                            .font(typeface.titleFont)
                            .foregroundStyle(Color.ink)
                        Text(roleHint.poemScript(script))
                            .font(typeface.smallFont)
                            .foregroundStyle(Color.mutedInk)
                    }
                    Spacer()
                    QuietBackButton(title: "返回") { dismiss() }
                }
                .padding(.horizontal, 30)
                .padding(.top, 32)

                Spacer()

                // Vertical writing area
                GeometryReader { geo in
                    let totalSpacing = CGFloat(charCount - 1) * 10
                    let boxSize = min(44, (geo.size.width - 48 - totalSpacing) / CGFloat(charCount))
                    let fontSize = boxSize * 0.6
                    HStack(spacing: 10) {
                        ForEach(0..<charCount, id: \.self) { i in
                            let char = i < cleanText.count
                                ? String(cleanText[cleanText.index(cleanText.startIndex, offsetBy: i)])
                                : ""
                            let isCaretBox = isFocused && i == cleanText.count
                            Text(char)
                                .font(typeface.font(size: fontSize))
                                .foregroundStyle(Color.ink)
                                .frame(width: boxSize, height: boxSize)
                                .overlay {
                                    if isCaretBox {
                                        BlinkingCaret(height: fontSize)
                                    }
                                }
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(
                                            i < cleanText.count || isCaretBox ? Color.cinnabar.opacity(0.5) : Color.mutedInk.opacity(0.2),
                                            lineWidth: i < cleanText.count ? 1.2 : 0.8
                                        )
                                )
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: geo.size.height)
                }
                .frame(height: 44)
                .padding(.horizontal, 24)

                // Hidden text field
                TextField("", text: $text)
                    .focused($isFocused)
                    .font(typeface.font(size: 1))
                    .foregroundStyle(.clear)
                    .tint(.clear)
                    .frame(width: 1, height: 1)
                    .opacity(0.01)

                Spacer()

                // Character count hint + confirm
                VStack(spacing: 16) {
                    Text("\(cleanText.count)/\(charCount)".poemScript(script))
                        .font(typeface.smallFont)
                        .foregroundStyle(isValid ? Color.cinnabar : Color.mutedInk)

                    Button {
                        SensoryFeedback.lightTap()
                        onConfirm(cleanText)
                    } label: {
                        Text(AppLanguage.copy("落筆", "Use line").poemScript(script))
                            .font(AppLanguage.isEnglish ? .system(size: 12, weight: .semibold) : typeface.sealFont)
                            .foregroundStyle(.white)
                            .frame(width: AppLanguage.isEnglish ? 92 : 60, height: 60)
                            .background {
                                if AppLanguage.isEnglish {
                                    Capsule().fill(isValid ? Color.cinnabar : Color.mutedInk.opacity(0.3))
                                } else {
                                    Circle().fill(isValid ? Color.cinnabar : Color.mutedInk.opacity(0.3))
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .disabled(!isValid)
                }
                .padding(.bottom, 48)
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
        .onAppear { isFocused = true }
        .onTapGesture { isFocused = true }
        .onChange(of: text) {
            let cjk = text.unicodeScalars.filter { CharacterSet.cjk.contains($0) }
            if cjk.count > charCount {
                text = String(cjk.prefix(charCount))
            }
        }
    }
}

/// A thin cinnabar caret that blinks like a system text cursor; stays solid when Reduce Motion is on.
private struct BlinkingCaret: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let height: CGFloat

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.53)) { context in
            let visible = reduceMotion
                || Int(context.date.timeIntervalSinceReferenceDate / 0.53) % 2 == 0
            Capsule()
                .fill(Color.cinnabar)
                .frame(width: 1.5, height: height)
                .opacity(visible ? 1 : 0)
        }
        .accessibilityHidden(true)
    }
}

private struct TypewriterLine: View {
    private let usesVerticalText = true
    @Environment(\.poemTypeface) private var typeface
    @Environment(\.poemScript) private var script
    let text: String
    let visibleCount: Int
    var fontSize: CGFloat = PoemTypeface.bodyFontSize
    var spacing: CGFloat = 6

    var body: some View {
        let chars = Array(text.poemScript(script).enumerated())
        let layout = usesVerticalText
            ? AnyLayout(VStackLayout(spacing: spacing))
            : AnyLayout(HStackLayout(spacing: spacing))
        layout {
            ForEach(chars, id: \.offset) { index, character in
                Text(String(character))
                    .font(typeface.font(size: fontSize))
                    .foregroundStyle(Color.ink)
                    .opacity(index < visibleCount ? 1 : 0)
            }
        }
        .fixedSize()
    }
}

private struct RevisionLineButton: View {
    @Environment(\.poemTypeface) private var typeface
    @Environment(\.poemScript) private var script
    private let usesVerticalText = true
    let line: String
    var fontSize: CGFloat = PoemTypeface.bodyFontSize
    var spacing: CGFloat = 6
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            let layout = usesVerticalText
                ? AnyLayout(VStackLayout(spacing: 10))
                : AnyLayout(HStackLayout(spacing: 10))
            layout {
                ComposedPoemLine(line: line, fontSize: fontSize)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 7)
                    .background {
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(Color.cinnabar.opacity(0.32), lineWidth: 0.8)
                    }

                if AppLanguage.isEnglish {
                    Image(systemName: "pencil")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color.cinnabar))
                } else {
                    Text("改".poemScript(script))
                        .font(typeface.tinySealFont)
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color.cinnabar))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private func compactInscriptionText(_ text: String) -> String {
    text
        .replacingOccurrences(of: "\u{2009}", with: "")
        .replacingOccurrences(of: "\u{00A0}", with: "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

private struct FinishedPoemView: View {
    @Environment(\.poemTypeface) private var typeface
    @Environment(\.poemScript) private var script
    @EnvironmentObject private var locationProvider: PoemLocationProvider
    @AppStorage(SealStampView.storageKey) private var sealName = ""
    @AppStorage(PoemTypeface.storageKey) private var typefaceRawValue = PoemTypeface.kaiti.rawValue
    private let usesVerticalText = true
    let mood: MoodSeed
    let image: ImageSeed
    let lines: [String]
    let background: PoemBackground
    let onReviseLine: (Int, String) -> Void
    let onSave: (SavedPoem) -> Void
    let onOpenArchive: () -> Void
    let onDelete: () -> Void
    @State private var revealedChars = 0
    @State private var showSeal = false
    @State private var showActions = false
    @State private var isRevisingPoem = false
    @State private var isSaved = false
    @State private var editingLine: EditingLine?
    @State private var editingText = ""
    @State private var showsDeleteConfirmation = false

    private struct EditingLine: Identifiable {
        let index: Int
        var id: Int { index }
    }

    private func characterCount(of line: String) -> Int {
        line.unicodeScalars.filter { CharacterSet.cjk.contains($0) }.count
    }

    private func charsForLine(_ lineIndex: Int) -> Int {
        var charsBefore = 0
        for i in 0..<lineIndex {
            charsBefore += lines[i].count
        }
        return max(0, min(revealedChars - charsBefore, lines[lineIndex].count))
    }

    private var allRevealed: Bool {
        revealedChars >= lines.reduce(0) { $0 + $1.count }
    }

    private var locationMark: String? {
        let place = locationProvider.inscriptionPlace ?? locationProvider.cityName
        guard let place, !place.isEmpty else { return nil }
        return compactInscriptionText("於\(place)").poemScript(script)
    }

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                let scale = geometry.size.width / ShareArtworkLayout.portrait.canvasSize.width
                let fontSize = (lines.count > 4 ? 42.0 : 58.0) * scale
                let characterSpacing = (lines.count > 4 ? 15.0 : 19.0) * scale
                let columnSpacing = (lines.count > 4 ? 34.0 : 54.0) * scale

                ScrollView(.vertical, showsIndicators: false) {
                    VerticalPoemComposition(columnSpacing: columnSpacing, minimumGap: 40 * scale) {
                        PoemInscriptionView(locationMark: locationMark)
                            .opacity(allRevealed ? 1 : 0)
                    } seal: {
                        if !sealName.isEmpty {
                            SealStampView(name: sealName, size: 104 * scale)
                                .opacity(showSeal ? 1 : 0)
                                .scaleEffect(showSeal ? 1 : 0.7)
                        }
                    } verses: {
                        ForEach(Array(lines.indices.reversed()), id: \.self) { index in
                            if isRevisingPoem {
                                RevisionLineButton(
                                    line: lines[index],
                                    fontSize: fontSize,
                                    spacing: characterSpacing,
                                    action: {
                                        editingText = lines[index]
                                        editingLine = EditingLine(index: index)
                                    }
                                )
                            } else {
                                // Reserve every column from the first frame so
                                // revealing characters never moves the poem.
                                TypewriterLine(
                                    text: lines[index],
                                    visibleCount: charsForLine(index),
                                    fontSize: fontSize,
                                    spacing: characterSpacing
                                )
                            }
                        }
                    } title: {
                        VerticalText(image.title, font: typeface.font(size: 44 * scale), color: .mutedInk, spacing: 16 * scale)
                    }
                    .frame(minHeight: max(0, geometry.size.height - 64 * scale))
                    .padding(.horizontal, 90 * scale)
                    .padding(.vertical, 32 * scale)
                }
            }

            VStack(spacing: 16) {
                if isRevisingPoem {
                    Text(AppLanguage.copy("點一句修改文字", "Tap a line to edit its text").poemScript(script))
                        .font(.system(size: 12))
                        .foregroundStyle(Color.mutedInk.opacity(0.72))
                }

                HStack(spacing: 24) {
                    SealButton(
                        title: isRevisingPoem ? AppLanguage.copy("完成", "Done") : AppLanguage.copy("修改", "Edit"),
                        isSelected: !isRevisingPoem,
                        action: { isRevisingPoem.toggle() }
                    )
                    SealButton(
                        title: AppLanguage.copy("保存", "Save"),
                        isSelected: true,
                        action: onOpenArchive
                    )
                    SealButton(
                        title: AppLanguage.copy("删除", "Delete"),
                        isSelected: false,
                        action: { showsDeleteConfirmation = true }
                    )
                }
            }
            .opacity(showActions ? 1 : 0)
            .scaleEffect(showActions ? 1 : 0.92)
            .allowsHitTesting(showActions)
            .accessibilityHidden(!showActions)
            .frame(height: 100)
        }
        .padding(.bottom, 24)
        .animation(.easeOut(duration: 0.3), value: revealedChars)
        .animation(.easeOut(duration: 0.6), value: showSeal)
        .animation(.easeOut(duration: 0.45), value: showActions)
        .animation(.easeOut(duration: 0.5), value: locationProvider.inscriptionPlace)
        // Reveal once; in-place text edits must not replay the animation.
        .task {
            await revealPoem()
        }
        .sheet(item: $editingLine) { editing in
            SelfWriteSheet(
                charCount: characterCount(of: lines[editing.index]),
                lineIndex: editing.index,
                text: $editingText,
                editsExistingLine: true
            ) { newLine in
                if newLine != lines[editing.index] {
                    onReviseLine(editing.index, newLine)
                }
                editingLine = nil
            }
        }
        .alert(
            AppLanguage.copy("确定删除此诗？", "Delete this poem?").poemScript(script),
            isPresented: $showsDeleteConfirmation
        ) {
            Button(AppLanguage.copy("取消", "Cancel").poemScript(script), role: .cancel) {}
            Button(AppLanguage.copy("删除", "Delete").poemScript(script), role: .destructive) {
                onDelete()
            }
        } message: {
            Text(AppLanguage.copy("删除后将不会保存，且无法恢复。", "This poem will not be saved and cannot be recovered.").poemScript(script))
        }
    }

    private func revealPoem() async {
        revealedChars = 0
        showSeal = false
        showActions = false
        isRevisingPoem = false
        isSaved = false

        try? await Task.sleep(nanoseconds: 500_000_000)
        let lineDelay: UInt64 = lines.count > 4 ? 320_000_000 : 500_000_000
        let characterDelay: UInt64 = lines.count > 4 ? 115_000_000 : 160_000_000

        for lineIndex in lines.indices {
            if lineIndex > 0 {
                try? await Task.sleep(nanoseconds: lineDelay)
            }
            guard !Task.isCancelled else { return }

            for _ in lines[lineIndex] {
                guard !Task.isCancelled else { return }
                try? await Task.sleep(nanoseconds: characterDelay)
                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.3)) {
                        revealedChars += 1
                    }
                }
            }

            if lineIndex == lines.indices.last {
                SensoryFeedback.lightTap()
            }
        }

        await MainActor.run {
            locationProvider.requestCityIfNeeded()
        }

        if !sealName.isEmpty {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                showSeal = true
            }
            try? await Task.sleep(nanoseconds: 650_000_000)
        } else {
            try? await Task.sleep(nanoseconds: 450_000_000)
        }

        guard !Task.isCancelled else { return }
        await MainActor.run {
            savePoem()
            showActions = true
        }
    }

    private func savePoem() {
        guard !isSaved else { return }
        let inscriptionDate = PoemInscriptionDate.current
        let place = locationProvider.inscriptionPlace ?? locationProvider.cityName
        let poem = SavedPoem(
            createdAt: Date(),
            moodTitle: mood.title,
            imageTitle: image.title,
            lines: lines,
            locationText: place.map { compactInscriptionText("於\($0)") },
            lunarDateText: inscriptionDate.lunarDateText,
            dayPeriodText: inscriptionDate.dayPeriodText,
            typefaceRawValue: typefaceRawValue,
            backgroundRawValue: background.rawValue,
            usesVerticalText: usesVerticalText,
            sealName: sealName,
            scriptRawValue: script.rawValue,
            sealStyleRawValue: UserDefaults.standard.string(forKey: SealStampStyle.storageKey),
            sealTransliteration: UserDefaults.standard.string(forKey: NameTransliterator.overrideStorageKey),
            shadowRawValue: UserDefaults.standard.string(forKey: ShadowStyle.storageKey)
        )

        onSave(poem)
        isSaved = true
    }
}

private struct PoemInscriptionView: View {
    @Environment(\.poemTypeface) private var typeface
    @Environment(\.poemScript) private var script
    let locationMark: String?

    var body: some View {
        HStack(alignment: .top, spacing: 5) {
            VerticalText(PoemInscriptionDate.current.lunarDateText, font: typeface.tinySealFont, color: .mutedInk, spacing: 3)
            if let locationMark {
                VerticalText(compactInscriptionText(locationMark), font: typeface.tinySealFont, color: .mutedInk, spacing: 3)
            }
        }
    }
}

#if false // Shared share-preview implementation lives in PoetryDesignSystem.swift.
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
    @State private var showsPaywall = false

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
                    showsPaywall = true
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
        .sheet(isPresented: $showsPaywall) {
            PaywallView {
                showsPaywall = false
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
    @AppStorage(ShadowStyle.storageKey) private var selectedShadowRaw = ShadowStyle.defaultStyle.rawValue
    @ObservedObject private var store = StoreManager.shared
    @Binding var selectedBgRaw: String
    let requestPremium: () -> Void

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
	                    // Background images
	                    ForEach(PoemBackground.imageBackgrounds) { bg in
	                        let isSpotlightTarget = spotlightGuide.step == .selectBackground && bg == PoemBackground.freeImageBackgrounds.first
                        Button {
                            guard hasPremiumAccess || !bg.isPremium else {
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

                    Rectangle()
                        .fill(Color.mutedInk.opacity(0.2))
                        .frame(width: 0.5, height: 60)

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
                }
                .padding(.horizontal, 30)
                .padding(.vertical, 2)
            }
        }
        .onAppear {
            // Legacy cleanup: an image background with the "none" shadow style
            // predates selectable shadows — move it to the default texture.
            // 素紙 (no background) keeps whatever shadow the reader chose.
            if selectedShadowRaw == ShadowStyle.none.rawValue && selectedBgRaw != PoemBackground.none.rawValue {
                selectedShadowRaw = ShadowStyle.defaultStyle.rawValue
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

#endif

struct SavedPoem: Codable, Identifiable, Equatable {
    let id: UUID
    let createdAt: Date
    let moodTitle: String
    let imageTitle: String
    let lines: [String]
    let locationText: String?
    let lunarDateText: String
    let dayPeriodText: String
    /// Optional so archives saved by older app versions keep decoding correctly.
    var typefaceRawValue: String?
    var backgroundRawValue: String?
    var usesVerticalText: Bool?
    var sealName: String?
    var scriptRawValue: String?
    var sealStyleRawValue: String?
    var sealTransliteration: String?
    var shadowRawValue: String?

    init(
        id: UUID = UUID(),
        createdAt: Date,
        moodTitle: String,
        imageTitle: String,
        lines: [String],
        locationText: String?,
        lunarDateText: String,
        dayPeriodText: String,
        typefaceRawValue: String? = nil,
        backgroundRawValue: String? = nil,
        usesVerticalText: Bool? = nil,
        sealName: String? = nil,
        scriptRawValue: String? = nil,
        sealStyleRawValue: String? = nil,
        sealTransliteration: String? = nil,
        shadowRawValue: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.moodTitle = moodTitle
        self.imageTitle = imageTitle
        self.lines = lines
        self.locationText = locationText
        self.lunarDateText = lunarDateText
        self.dayPeriodText = dayPeriodText
        self.typefaceRawValue = typefaceRawValue
        self.backgroundRawValue = backgroundRawValue
        self.usesVerticalText = usesVerticalText
        self.sealName = sealName
        self.scriptRawValue = scriptRawValue
        self.sealStyleRawValue = sealStyleRawValue
        self.sealTransliteration = sealTransliteration
        self.shadowRawValue = shadowRawValue
    }
}

enum PoemArchiveStore {
    private static let storageKey = "savedPoems"
    private static let maxCount = 60

    static func load() -> [SavedPoem] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let poems = try? JSONDecoder().decode([SavedPoem].self, from: data) else {
            return []
        }
        return poems.sorted { $0.createdAt > $1.createdAt }
    }

    @discardableResult
    static func save(_ poem: SavedPoem) -> [SavedPoem] {
        var poems = load()
        poems.removeAll { $0.lines == poem.lines && $0.imageTitle == poem.imageTitle }
        poems.insert(poem, at: 0)
        poems = Array(poems.prefix(maxCount))

        persist(poems)
        return poems
    }

    /// Replace by identity so editing never duplicates or reorders a work.
    @discardableResult
    static func update(_ poem: SavedPoem) -> [SavedPoem] {
        var poems = load()
        guard let index = poems.firstIndex(where: { $0.id == poem.id }) else { return poems }
        poems[index] = poem
        persist(poems)
        return poems
    }

    @discardableResult
    static func delete(_ poem: SavedPoem) -> [SavedPoem] {
        let poems = load().filter { $0.id != poem.id }
        persist(poems)
        return poems
    }

    private static func persist(_ poems: [SavedPoem]) {
        if let data = try? JSONEncoder().encode(poems) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}

/// Top-right entry on the composer's first page; pushes 藏詩 onto the tab's stack.
private struct ArchiveEntryButton: View {
    @Environment(\.poemTypeface) private var typeface
    @Environment(\.poemScript) private var script
    @Environment(\.spotlightGuide) private var spotlightGuide
    let count: Int

    private var isSpotlightTarget: Bool {
        spotlightGuide.step == .openHistory
    }

    var body: some View {
        NavigationLink(value: ComposeRoute.archive) {
            HStack(spacing: 6) {
                Image(systemName: "books.vertical")
                    .font(.system(size: 13, weight: .medium))
                Text("藏詩".poemScript(script))
                    .font(typeface.tinySealFont)
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(Color.mutedInk)
                }
            }
            .foregroundStyle(Color.ink)
            .padding(.horizontal, 14)
            .frame(height: 38)
            .background(.ultraThinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            TapGesture().onEnded {
                if isSpotlightTarget {
                    spotlightGuide.advance()
                }
            }
        )
        .spotlightTarget(.openHistory, active: isSpotlightTarget)
        .accessibilityLabel(count > 0 ? "藏詩，\(count)首".poemScript(script) : "藏詩".poemScript(script))
    }
}

/// 藏詩: poems saved from 擇句成詩, pushed onto the composer tab's navigation stack.
struct PoemArchiveView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.poemTypeface) private var typeface
    @Environment(\.poemScript) private var script
    @Environment(\.spotlightGuide) private var spotlightGuide
    @State private var poems = PoemArchiveStore.load()
    @State private var poemPendingDeletion: SavedPoem?

    var body: some View {
        ZStack {
            PaperBackground()

            VStack(spacing: 0) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(AppLanguage.copy("藏詩", "Saved poems").poemScript(script))
                            .font(typeface.titleFont)
                            .foregroundStyle(Color.ink)

                        if !poems.isEmpty {
                            Text((AppLanguage.isEnglish
                                ? "\(poems.count) saved · Tap a card to read"
                                : "\(poems.count)首 · 輕觸詩箋重讀").poemScript(script))
                                .font(.system(size: 12))
                                .foregroundStyle(Color.mutedInk.opacity(0.72))
                        }
                    }
                    Spacer()
                    QuietBackButton(title: "返回") { dismiss() }
                }
                .padding(.horizontal, 22)
                .padding(.top, 20)
                .padding(.bottom, 22)

                if poems.isEmpty {
                    Spacer()
                    VerticalText(AppLanguage.copy("尚無藏詩", "No saved poems yet").poemScript(script), style: .small, color: .mutedInk, spacing: 7)
                    Spacer()
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVGrid(
                            columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)],
                            spacing: 18
                        ) {
                            ForEach(Array(poems.enumerated()), id: \.element.id) { index, poem in
                                let isSpotlightTarget = spotlightGuide.step == .openHistoryPoem && index == 0
                                ZStack(alignment: .topTrailing) {
                                    NavigationLink(value: poem.id) {
                                        SavedPoemArchiveCard(poem: poem)
                                    }
                                    .buttonStyle(.plain)
                                    .spotlightTarget(.openHistoryPoem, active: isSpotlightTarget)
                                    .simultaneousGesture(
                                        TapGesture().onEnded {
                                            if isSpotlightTarget {
                                                spotlightGuide.advance()
                                            }
                                        }
                                    )

                                    Button {
                                        poemPendingDeletion = poem
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(Color.cinnabar)
                                            .frame(width: 28, height: 28)
                                            .background(.white.opacity(0.88), in: Circle())
                                            .overlay {
                                                Circle()
                                                    .stroke(Color.cinnabar.opacity(0.45), lineWidth: 0.8)
                                            }
                                    }
                                    .buttonStyle(.plain)
                                    .padding(7)
                                    .accessibilityLabel(AppLanguage.copy("刪除此詩", "Delete this poem").poemScript(script))
                                }
                                .transition(.opacity.combined(with: .offset(y: 8)))
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 50)
                    }
                }
            }
        }
        .navigationBarHidden(true)
        .navigationDestination(for: SavedPoem.ID.self) { id in
            if let poem = poems.first(where: { $0.id == id }) {
                SavedPoemDetailView(poem: poem) { updated in
                    poems = PoemArchiveStore.update(updated)
                }
            }
        }
        .spotlightOverlay(for: [.openHistoryPoem])
        .alert(
            AppLanguage.copy("確定刪除此詩？", "Delete this poem?").poemScript(script),
            isPresented: Binding(
                get: { poemPendingDeletion != nil },
                set: { isPresented in
                    if !isPresented {
                        poemPendingDeletion = nil
                    }
                }
            ),
        ) {
            Button(AppLanguage.copy("取消", "Cancel").poemScript(script), role: .cancel) {
                poemPendingDeletion = nil
            }

            Button(AppLanguage.copy("刪除", "Delete poem").poemScript(script), role: .destructive) {
                if let poem = poemPendingDeletion {
                    delete(poem)
                }
                poemPendingDeletion = nil
            }
        } message: {
            Text(AppLanguage.copy("刪除後不可恢復", "This action cannot be undone.").poemScript(script))
        }
        .onAppear {
            poems = PoemArchiveStore.load()
        }
    }

    private func delete(_ poem: SavedPoem) {
        SensoryFeedback.lightTap()
        withAnimation(.easeOut(duration: 0.25)) {
            poems = PoemArchiveStore.delete(poem)
        }
    }
}

private struct SavedPoemListRow: View {
    @Environment(\.poemTypeface) private var typeface
    @Environment(\.poemScript) private var script
    let poem: SavedPoem

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text(poem.imageTitle.poemScript(script))
                    .font(typeface.font(size: 18))
                    .foregroundStyle(Color.ink)

                Text(poem.lines.first?.poemScript(script) ?? "")
                    .font(typeface.smallFont)
                    .foregroundStyle(Color.mutedInk)
                    .lineLimit(1)

                Text(Self.createdAtText(for: poem.createdAt).poemScript(script))
                    .font(.system(size: 11))
                    .foregroundStyle(Color.mutedInk.opacity(0.72))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VerticalText(AppLanguage.copy("閱", "Read").poemScript(script), style: .tinySeal, color: .cinnabar.opacity(0.86), spacing: 4)
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 18)
        .background {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.white.opacity(0.54))
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.mutedInk.opacity(0.12))
                .frame(height: 0.7)
                .padding(.horizontal, 8)
        }
    }

    static func createdAtText(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.isEnglish ? Locale(identifier: "en_US") : Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = AppLanguage.isEnglish ? "MMM d, yyyy, HH:mm" : "yyyy年M月d日 HH:mm"
        return formatter.string(from: date)
    }
}

/// A lightweight, live rendition of the saved share artwork. Keeping the visual
/// ingredients with the poem avoids storing large image blobs in UserDefaults.
private struct SavedPoemArchiveCard: View {
    @Environment(\.poemScript) private var script
    let poem: SavedPoem

    var body: some View {
        PoemArchiveCard(
            title: poem.imageTitle.poemScript(script),
            subtitle: SavedPoemListRow.createdAtText(for: poem.createdAt).poemScript(script)
        ) {
            SavedPoemArtworkThumbnail(poem: poem)
        }
    }
}

private struct SavedPoemArtworkThumbnail: View {
    let poem: SavedPoem
    private let canvasSize = ShareArtworkLayout.portrait.canvasSize

    var body: some View {
        GeometryReader { geometry in
            let scale = geometry.size.width / canvasSize.width
            ConfiguredShareArtwork(
                layout: .portrait,
                imageTitle: poem.imageTitle,
                lines: poem.lines,
                locationMark: PoemLocationPreference.visible(poem.locationText),
                lunarDateText: poem.lunarDateText,
                dayPeriodText: poem.dayPeriodText,
                style: poem.artworkStyle
            )
            .frame(width: canvasSize.width, height: canvasSize.height)
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            .clipped()
        }
        .aspectRatio(ShareArtworkLayout.portrait.aspectRatio, contentMode: .fit)
    }
}

private struct SavedPoemDetailView: View {
    @State private var poem: SavedPoem
    let onSave: (SavedPoem) -> Void
    @State private var showsEditor = false

    init(poem: SavedPoem, onSave: @escaping (SavedPoem) -> Void) {
        _poem = State(initialValue: poem)
        self.onSave = onSave
    }

    private var artworkStyle: ShareArtworkStyle { poem.artworkStyle }

    var body: some View {
        // Read the insets outside the full-bleed artwork: the tab bar's inset
        // is only reported to views that stay inside the safe area.
        GeometryReader { container in
            ZStack(alignment: .top) {
                PaperBackground(backgroundOverride: artworkStyle.background, shadowStyleOverride: artworkStyle.shadow)

                // The artwork fills the whole screen, under the status bar, the
                // quiet buttons and the tab bar, so the page reads as one sheet.
                GeometryReader { geometry in
                    let canvasWidth = ShareArtworkLayout.portrait.canvasSize.width
                    let scale = geometry.size.width / canvasWidth

                    ConfiguredShareArtwork(
                        layout: .portrait,
                        imageTitle: poem.imageTitle,
                        lines: poem.lines,
                        locationMark: PoemLocationPreference.visible(poem.locationText),
                        lunarDateText: poem.lunarDateText,
                        dayPeriodText: poem.dayPeriodText,
                        style: artworkStyle,
                        extraTopPadding: (container.safeAreaInsets.top + 56) / scale,
                        extraBottomPadding: (container.safeAreaInsets.bottom + 12) / scale
                    )
                    .frame(width: canvasWidth, height: geometry.size.height / scale)
                    .scaleEffect(scale, anchor: .topLeading)
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
                }
                .ignoresSafeArea()

                PaperDetailTopBar {
                    QuietBackButton(title: AppLanguage.copy("分享", "Share")) {
                        showsEditor = true
                    }
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(isPresented: $showsEditor) {
            PoemArtworkEditorView(poem: poem) { updated in
                onSave(updated)
                poem = updated
            }
        }
    }
}

#if false // Shared typography, paper, and seal components live in PoetryDesignSystem.swift.
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
    @AppStorage(ShadowStyle.storageKey) private var shadowStyleRaw = ShadowStyle.defaultStyle.rawValue
    @AppStorage(PoemBackground.storageKey) private var backgroundRawValue = PoemBackground.defaultBackground.rawValue

    private var shadowStyle: ShadowStyle {
        ShadowStyle(rawValue: shadowStyleRaw) ?? .defaultStyle
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
}

enum PoemFontStyle {
    case title
    case body
    case small
    case accent
    case seal
    case tinySeal
}

#endif

enum PoemStructure: String, CaseIterable, Identifiable {
    static let storageKey = "poemStructure"

    case jueju
    case lushi

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .jueju:
            return AppLanguage.copy("絕句", "Quatrain")
        case .lushi:
            return AppLanguage.copy("律詩", "Regulated verse")
        }
    }

    var lineCount: Int {
        switch self {
        case .jueju:
            return 4
        case .lushi:
            return 8
        }
    }
}

enum PoemMeter: String, CaseIterable, Identifiable {
    static let storageKey = "poemMeter"

    case five
    case seven

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .five:
            return AppLanguage.copy("五言", "Five-character")
        case .seven:
            return AppLanguage.copy("七言", "Seven-character")
        }
    }

    var characterCount: Int {
        switch self {
        case .five:
            return 5
        case .seven:
            return 7
        }
    }
}

struct PoemFormSpec: Hashable, Identifiable {
    let structure: PoemStructure
    let meter: PoemMeter

    var id: String { "\(meter.rawValue)-\(structure.rawValue)" }
    var lineCount: Int { structure.lineCount }
    var lastLineIndex: Int { lineCount - 1 }
    var characterCount: Int { meter.characterCount }
    var displayName: String {
        AppLanguage.isEnglish
            ? "\(meter.displayName) \(structure.displayName.lowercased())"
            : "\(meter.displayName)\(structure.displayName)"
    }

    func role(for lineIndex: Int) -> String {
        if structure == .jueju {
            switch lineIndex {
            case 0:
                return AppLanguage.copy("第一句：取景，先立意象", "Line 1: Begin with an image")
            case 1:
                return AppLanguage.copy("第二句：入情，把景转为心事", "Line 2: Turn the scene toward feeling")
            case 2:
                return AppLanguage.copy("第三句：转折，让情绪有微妙变化", "Line 3: Let the feeling shift")
            default:
                return AppLanguage.copy("第四句：收束，留下余味", "Line 4: Close with a lingering note")
            }
        }

        switch lineIndex {
        case 0:
            return AppLanguage.copy("第一句：起，先立意象", "Line 1: Begin with an image")
        case 1:
            return AppLanguage.copy("第二句：承，补足景与情", "Line 2: Develop the scene and feeling")
        case 2, 3:
            return AppLanguage.copy("颔联：展开景物与心事，略有对仗感", "Lines 3–4: Expand the scene with a sense of balance")
        case 4, 5:
            return AppLanguage.copy("颈联：转入深一层情绪，略有对仗感", "Lines 5–6: Deepen the feeling with a sense of balance")
        case 6:
            return AppLanguage.copy("第七句：准备收束", "Line 7: Prepare to close")
        default:
            return AppLanguage.copy("第八句：收束全诗，留下余味", "Line 8: Close with a lingering note")
        }
    }
}

#if false // Shared script and typeface definitions live in PoetryDesignSystem.swift.
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

#endif

struct MoodSeed: Identifiable, Equatable {
    let id: String
    let title: String
    let englishTitle: String?
    let tags: [String]

    init(id: String, title: String, englishTitle: String? = nil, tags: [String]? = nil) {
        self.id = id
        self.title = title
        self.englishTitle = englishTitle
        self.tags = tags ?? [title]
    }

}

struct SettingSeed: Identifiable, Equatable {
    let id: String
    let title: String
    let englishTitle: String
    let images: [ImageSeed]
}

struct FeelingSeed: Identifiable, Equatable {
    let id: String
    let title: String
    let englishTitle: String
    let tags: [String]
    let lineFamily: String
}

struct ImageSeed: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
}

enum PoetrySeed {
    private static var rotatingIndex = 0

    static let feelings: [FeelingSeed] = [
        FeelingSeed(id: "feeling-serene", title: "安然", englishTitle: "Serene", tags: ["安", "放下"], lineFamily: "relief"),
        FeelingSeed(id: "feeling-joyful", title: "欣然", englishTitle: "Joyful", tags: ["喜", "樂"], lineFamily: "default"),
        FeelingSeed(id: "feeling-still", title: "澄静", englishTitle: "Still", tags: ["靜", "夜"], lineFamily: "quiet"),
        FeelingSeed(id: "feeling-wistful", title: "惆怅", englishTitle: "Wistful", tags: ["哀", "離"], lineFamily: "part"),
        FeelingSeed(id: "feeling-longing", title: "思念", englishTitle: "Longing", tags: ["相思", "別"], lineFamily: "part"),
        FeelingSeed(id: "feeling-free", title: "洒脱", englishTitle: "Free", tags: ["放下", "釋"], lineFamily: "relief"),
        FeelingSeed(id: "feeling-resolute", title: "激越", englishTitle: "Resolute", tags: ["不甘", "志向"], lineFamily: "resolve"),
        FeelingSeed(id: "feeling-tender", title: "温柔", englishTitle: "Tender", tags: ["柔", "喜"], lineFamily: "default"),
        FeelingSeed(id: "feeling-lonely", title: "孤寂", englishTitle: "Lonely", tags: ["孤", "夜"], lineFamily: "quiet")
    ]

    static let themeBatches: [[MoodSeed]] = [
        [
            MoodSeed(id: "theme-distance", title: "远方", englishTitle: "Afar", tags: ["遠", "離"]),
            MoodSeed(id: "theme-longing", title: "相思", englishTitle: "Longing", tags: ["相思", "哀"]),
            MoodSeed(id: "theme-autumn", title: "秋日", englishTitle: "Autumn", tags: ["秋", "孤"]),
            MoodSeed(id: "theme-landscape", title: "山水", englishTitle: "Landscape", tags: ["山水", "放下"]),
            MoodSeed(id: "theme-friendship", title: "友情", englishTitle: "Friendship", tags: ["友情", "喜"]),
            MoodSeed(id: "theme-city", title: "城市", englishTitle: "City", tags: ["城市", "夜"]),
            MoodSeed(id: "theme-festival", title: "节日", englishTitle: "Festival", tags: ["節日", "喜"]),
            MoodSeed(id: "theme-life", title: "人生", englishTitle: "Life", tags: ["人生", "放下"]),
            MoodSeed(id: "theme-nature", title: "自然", englishTitle: "Nature", tags: ["自然", "樂"]),
            MoodSeed(id: "theme-homecoming", title: "归乡", englishTitle: "Home", tags: ["歸鄉", "離"])
        ],
        [
            MoodSeed(id: "theme-spring", title: "春日", englishTitle: "Spring", tags: ["春", "喜"]),
            MoodSeed(id: "theme-moonnight", title: "月夜", englishTitle: "Moon", tags: ["月", "夜"]),
            MoodSeed(id: "theme-parting", title: "离别", englishTitle: "Parting", tags: ["離", "別"]),
            MoodSeed(id: "theme-reunion", title: "重逢", englishTitle: "Reunion", tags: ["重逢", "喜"]),
            MoodSeed(id: "theme-solitude", title: "独处", englishTitle: "Solitude", tags: ["孤", "夜"]),
            MoodSeed(id: "theme-aspiration", title: "志向", englishTitle: "Resolve", tags: ["志向", "不甘"]),
            MoodSeed(id: "theme-oldhome", title: "故园", englishTitle: "Homeland", tags: ["故鄉", "離"]),
            MoodSeed(id: "theme-leisure", title: "闲居", englishTitle: "Leisure", tags: ["閒居", "放下"]),
            MoodSeed(id: "theme-journey", title: "旅途", englishTitle: "Journey", tags: ["旅途", "樂"]),
            MoodSeed(id: "theme-family", title: "家人", englishTitle: "Family", tags: ["家人", "喜"])
        ],
        [
            MoodSeed(id: "theme-rain", title: "雨天", englishTitle: "Rain", tags: ["雨", "孤"]),
            MoodSeed(id: "theme-olddream", title: "旧梦", englishTitle: "Dreams", tags: ["舊夢", "夜"]),
            MoodSeed(id: "theme-rivers", title: "江湖", englishTitle: "Rivers", tags: ["江湖", "不甘"]),
            MoodSeed(id: "theme-reflection", title: "感怀", englishTitle: "Reflection", tags: ["感懷", "孤"]),
            MoodSeed(id: "theme-newyear", title: "新岁", englishTitle: "New Year", tags: ["新歲", "喜"]),
            MoodSeed(id: "theme-confidant", title: "知己", englishTitle: "Kindred", tags: ["知己", "喜"]),
            MoodSeed(id: "theme-release", title: "放下", englishTitle: "Release", tags: ["放下", "釋"]),
            MoodSeed(id: "theme-retreat", title: "归隐", englishTitle: "Retreat", tags: ["歸隱", "放下"]),
            MoodSeed(id: "theme-reunion-family", title: "团圆", englishTitle: "Together", tags: ["團圓", "喜"]),
            MoodSeed(id: "theme-farewell", title: "送别", englishTitle: "Farewell", tags: ["送別", "離"])
        ]
    ]

    static let settings: [SettingSeed] = [
        SettingSeed(
            id: "riverbank",
            title: "江边",
            englishTitle: "Riverside",
            images: [
                ImageSeed(id: "riverbank-moon", title: "江月无声", subtitle: ""),
                ImageSeed(id: "riverbank-reeds", title: "芦花映水", subtitle: ""),
                ImageSeed(id: "riverbank-tide", title: "潮声入夜", subtitle: "")
            ]
        ),
        SettingSeed(
            id: "mountain",
            title: "山中",
            englishTitle: "Mountains",
            images: [
                ImageSeed(id: "mountain-pine", title: "松间月白", subtitle: ""),
                ImageSeed(id: "mountain-rain", title: "山雨初歇", subtitle: ""),
                ImageSeed(id: "mountain-cloud", title: "云出远岫", subtitle: "")
            ]
        ),
        SettingSeed(
            id: "courtyard",
            title: "庭院",
            englishTitle: "Courtyard",
            images: [
                ImageSeed(id: "courtyard-moon", title: "月落空庭", subtitle: ""),
                ImageSeed(id: "courtyard-flower", title: "海棠照影", subtitle: ""),
                ImageSeed(id: "courtyard-step", title: "石阶微露", subtitle: "")
            ]
        ),
        SettingSeed(
            id: "pavilion",
            title: "长亭",
            englishTitle: "Pavilion",
            images: [
                ImageSeed(id: "pavilion-grass", title: "长亭草色", subtitle: ""),
                ImageSeed(id: "pavilion-willow", title: "柳岸风轻", subtitle: ""),
                ImageSeed(id: "pavilion-sunset", title: "斜阳送客", subtitle: "")
            ]
        ),
        SettingSeed(
            id: "window",
            title: "窗前",
            englishTitle: "Window",
            images: [
                ImageSeed(id: "window-curtain", title: "疏帘风动", subtitle: ""),
                ImageSeed(id: "window-moon", title: "一窗新月", subtitle: ""),
                ImageSeed(id: "window-rain", title: "檐雨未停", subtitle: "")
            ]
        ),
        SettingSeed(
            id: "boat",
            title: "舟上",
            englishTitle: "Aboard",
            images: [
                ImageSeed(id: "boat-sail", title: "孤帆入暮", subtitle: ""),
                ImageSeed(id: "boat-fire", title: "渔火隔江", subtitle: ""),
                ImageSeed(id: "boat-sky", title: "水天一色", subtitle: "")
            ]
        ),
        SettingSeed(
            id: "old-road",
            title: "古道",
            englishTitle: "Old Road",
            images: [
                ImageSeed(id: "old-road-wind", title: "古道西风", subtitle: ""),
                ImageSeed(id: "old-road-dust", title: "驿尘初起", subtitle: ""),
                ImageSeed(id: "old-road-sunset", title: "残阳照马", subtitle: "")
            ]
        ),
        SettingSeed(
            id: "woods",
            title: "林间",
            englishTitle: "Woods",
            images: [
                ImageSeed(id: "woods-bamboo", title: "竹影扫阶", subtitle: ""),
                ImageSeed(id: "woods-bird", title: "鸟鸣深树", subtitle: ""),
                ImageSeed(id: "woods-pine", title: "松风满袖", subtitle: "")
            ]
        ),
        SettingSeed(
            id: "lamplight",
            title: "灯下",
            englishTitle: "Lamplight",
            images: [
                ImageSeed(id: "lamplight-late", title: "残灯照夜", subtitle: ""),
                ImageSeed(id: "lamplight-tea", title: "茶烟欲散", subtitle: ""),
                ImageSeed(id: "lamplight-book", title: "书页微黄", subtitle: "")
            ]
        ),
        SettingSeed(
            id: "city",
            title: "城中",
            englishTitle: "City",
            images: [
                ImageSeed(id: "city-after-rain", title: "城雨初歇", subtitle: ""),
                ImageSeed(id: "city-street", title: "长街灯晚", subtitle: ""),
                ImageSeed(id: "city-tower", title: "高楼望月", subtitle: "")
            ]
        )
    ]

    static let images = [
        ImageSeed(id: "worry", title: "怎麼不憂傷", subtitle: ""),
        ImageSeed(id: "wind", title: "季風氣候", subtitle: ""),
        ImageSeed(id: "light", title: "鹿柴", subtitle: "")
    ]

    static func rotatingImages(excluding recentTitles: [String] = []) -> [ImageSeed] {
        let groups = [
            [
                ImageSeed(id: "rain-alley", title: "雨後舊巷", subtitle: ""),
                ImageSeed(id: "late-wind", title: "半窗晚風", subtitle: ""),
                ImageSeed(id: "un-sleep", title: "人間未眠", subtitle: "")
            ],
            [
                ImageSeed(id: "moon-letter", title: "月下未書", subtitle: ""),
                ImageSeed(id: "old-ferry", title: "舊渡無人", subtitle: ""),
                ImageSeed(id: "spring-dust", title: "春塵微起", subtitle: "")
            ],
            [
                ImageSeed(id: "far-mountain", title: "遠山有信", subtitle: ""),
                ImageSeed(id: "thin-snow", title: "薄雪照燈", subtitle: ""),
                ImageSeed(id: "cloud-home", title: "雲歸何處", subtitle: "")
            ],
            [
                ImageSeed(id: "city-rain", title: "城雨初歇", subtitle: ""),
                ImageSeed(id: "late-train", title: "末班車遠", subtitle: ""),
                ImageSeed(id: "light-window", title: "一窗微明", subtitle: "")
            ],
            [
                ImageSeed(id: "cold-sleeve", title: "袖底微寒", subtitle: ""),
                ImageSeed(id: "old-dream", title: "舊夢不來", subtitle: ""),
                ImageSeed(id: "quiet-cup", title: "茶煙欲散", subtitle: "")
            ],
            [
                ImageSeed(id: "river-moon", title: "江月無聲", subtitle: ""),
                ImageSeed(id: "wild-goose", title: "雁過空庭", subtitle: ""),
                ImageSeed(id: "bamboo-shadow", title: "竹影掃心", subtitle: "")
            ],
            [
                ImageSeed(id: "unfinished", title: "未寄之書", subtitle: ""),
                ImageSeed(id: "after-farewell", title: "別後春深", subtitle: ""),
                ImageSeed(id: "old-name", title: "故人名字", subtitle: "")
            ],
            [
                ImageSeed(id: "work-night", title: "案上殘燈", subtitle: ""),
                ImageSeed(id: "deadline", title: "明日將至", subtitle: ""),
                ImageSeed(id: "thin-courage", title: "一點微勇", subtitle: "")
            ],
            [
                ImageSeed(id: "body-tired", title: "身似浮舟", subtitle: ""),
                ImageSeed(id: "heart-heavy", title: "心有微塵", subtitle: ""),
                ImageSeed(id: "sleep-late", title: "夜久難眠", subtitle: "")
            ],
            [
                ImageSeed(id: "release", title: "放下春山", subtitle: ""),
                ImageSeed(id: "new-wind", title: "新風吹袖", subtitle: ""),
                ImageSeed(id: "quiet-return", title: "歸來無語", subtitle: "")
            ]
        ]

        for offset in 0..<groups.count {
            let group = groups[(rotatingIndex + offset) % groups.count]
            if group.allSatisfy({ !recentTitles.contains($0.title) }) {
                rotatingIndex += offset + 1
                return group
            }
        }

        let group = groups[rotatingIndex % groups.count]
        rotatingIndex += 1
        return group
    }

    static func nonRepeatingImages(_ images: [ImageSeed], excluding recentTitles: [String]) -> [ImageSeed] {
        let filtered = images.filter { !recentTitles.contains($0.title) }
        if filtered.count >= 3 {
            return Array(filtered.prefix(3))
        }

        let fallback = rotatingImages(excluding: recentTitles + filtered.map(\.title))
        return Array((filtered + fallback).prefix(3))
    }

    static func images(for mood: MoodSeed, setting: SettingSeed) -> [ImageSeed] {
        let moodImages = images(for: mood)
        let count = max(setting.images.count, moodImages.count)
        var result: [ImageSeed] = []
        for index in 0..<count {
            if setting.images.indices.contains(index) {
                result.append(setting.images[index])
            }
            if moodImages.indices.contains(index) {
                result.append(moodImages[index])
            }
        }
        return result
    }

    static func images(for mood: MoodSeed) -> [ImageSeed] {
        switch mood.id {
        case "part":
            return [
                ImageSeed(id: "ferry", title: "渡口", subtitle: "人已远"),
                ImageSeed(id: "rain", title: "春雨", subtitle: "濕歸程"),
                ImageSeed(id: "road", title: "長亭", subtitle: "草色新")
            ]
        case "quiet":
            return [
                ImageSeed(id: "lamp", title: "孤燈", subtitle: "守長夜"),
                ImageSeed(id: "snow", title: "微雪", subtitle: "落空庭"),
                ImageSeed(id: "wind", title: "季風氣候", subtitle: "過舊城")
            ]
        case "relief":
            return [
                ImageSeed(id: "cloud", title: "流雲", subtitle: "出遠山"),
                ImageSeed(id: "river", title: "春水", subtitle: "自東流"),
                ImageSeed(id: "bamboo", title: "竹影", subtitle: "掃塵心")
            ]
        default:
            return images(matching: mood.tags)
        }
    }

    private static func images(matching tags: [String]) -> [ImageSeed] {
        let joined = tags.joined(separator: " ")
        let banks: [(matches: [String], images: [ImageSeed])] = [
            (
                ["雨", "潮湿", "梅雨", "阴天", "泪"],
                [
                    ImageSeed(id: "rain-window", title: "雨打空窗", subtitle: ""),
                    ImageSeed(id: "wet-sleeve", title: "袖上微潮", subtitle: ""),
                    ImageSeed(id: "late-rain", title: "夜雨未歇", subtitle: "")
                ]
            ),
            (
                ["倦", "困", "疲", "乏", "加班", "会议", "截止"],
                [
                    ImageSeed(id: "tired-lamp", title: "燈下微倦", subtitle: ""),
                    ImageSeed(id: "desk-night", title: "案上殘更", subtitle: ""),
                    ImageSeed(id: "thin-dream", title: "夢淺人遲", subtitle: "")
                ]
            ),
            (
                ["别", "離", "远", "归", "故乡", "长亭", "渡口"],
                [
                    ImageSeed(id: "far-ferry", title: "遠渡無聲", subtitle: ""),
                    ImageSeed(id: "return-road", title: "歸路生煙", subtitle: ""),
                    ImageSeed(id: "farewell-grass", title: "別後芳草", subtitle: "")
                ]
            ),
            (
                ["恋", "想念", "重逢", "冷战", "和解", "歉意"],
                [
                    ImageSeed(id: "old-letter", title: "舊信微溫", subtitle: ""),
                    ImageSeed(id: "name-moon", title: "月照其名", subtitle: ""),
                    ImageSeed(id: "after-meet", title: "相逢又晚", subtitle: "")
                ]
            ),
            (
                ["安", "释", "放下", "松弛", "看淡", "自由"],
                [
                    ImageSeed(id: "free-cloud", title: "雲開一寸", subtitle: ""),
                    ImageSeed(id: "light-sleeve", title: "袖有清風", subtitle: ""),
                    ImageSeed(id: "quiet-mountain", title: "山色忽輕", subtitle: "")
                ]
            ),
            (
                ["空", "惘", "低落", "无眠", "夜", "孤"],
                [
                    ImageSeed(id: "empty-city", title: "空城月白", subtitle: ""),
                    ImageSeed(id: "no-sleep", title: "人醒三更", subtitle: ""),
                    ImageSeed(id: "one-lamp", title: "一燈如豆", subtitle: "")
                ]
            )
        ]

        for bank in banks where bank.matches.contains(where: { joined.contains($0) }) {
            return bank.images
        }

        let all = banks.flatMap(\.images) + images
        let seed = abs(tags.joined().hashValue)
        return (0..<3).map { all[(seed + $0 * 5) % all.count] }
    }

    static func lines(
        for mood: MoodSeed,
        image: ImageSeed,
        form: PoemFormSpec,
        index: Int,
        selectedLines: [String] = [],
        refreshSeed: Int = 0
    ) -> [String] {
        let sevenDefault: [[String]] = [
            ["一夜春风入小楼", "新晴携客上高台", "灯暖归舟近故园", "春日归来花满衣"],
            ["笑语隔帘盈绣栊", "满城花色为君开", "门前灯火照团圆", "小院新茶待客来"],
            ["旧愿今朝随燕到", "新题小字上花笺", "一杯新酿待君尝", "笑把新诗写上笺"],
            ["两袖清香带晚风", "一川春水映云开", "席间笑语暖心田", "一帘晴色到樽前"],
            ["且向芳园寻好景", "闲看柳色过长堤", "窗前新月如眉好", "踏遍芳洲意未阑"],
            ["故人相见意无穷", "清歌一曲入晴空", "今夕人间分外圆", "满座清欢夜未央"],
            ["莫问归程迟与早", "便将欢意题红叶", "愿把家书重细看", "且将好景收心底"],
            ["人间此刻正情浓", "携手同归花影中", "明朝仍共看春山", "来岁花时再并肩"]
        ]

        let sevenResolve: [[String]] = [
            ["疾雨敲窗夜未休", "长街风紧压危楼", "寒灯照壁影如钩", "朔气横空动客愁"],
            ["世事纷纷意未酬", "一纸难平旧日忧", "欲将心火问来由", "几番隐忍到今秋"],
            ["不肯低眉随俗语", "且凭直气对横流", "偏教冷眼看沉浮", "不向人前说罢休"],
            ["胸中尚有千层浪", "笔底还藏一寸秋", "此念从来不肯收", "一腔孤勇逆风舟"],
            ["忍看浮云遮远目", "独持清醒立汀洲", "拂去尘埃再举头", "看尽炎凉志未酬"],
            ["任他风雨过荒丘", "自有青山在上游", "且将孤愤付吴钩", "磨剑十年刃未钝"],
            ["待到天明云自散", "回身已越最高丘", "莫令初心逐水流", "守得长空月一钩"],
            ["此心无改更登楼", "明朝仗剑向神州", "一身正气度春秋", "从今昂首任行游"]
        ]

        let sevenParting: [[String]] = [
            ["长亭草色又逢春", "渡口斜阳照别身", "春雨无声湿旧尘", "驿路风回草色新"],
            ["一程山水一程人", "回首烟波不见君", "落花吹满去年门", "旧城灯火送行人"],
            ["欲把离愁藏袖底", "忽闻归雁过江津", "此后相逢应有期", "临歧欲语还无语"],
            ["愿君前路有晴云", "莫向天涯问旧痕", "各自人间各自春", "惟愿重逢在早春"],
            ["远树含烟遮旧渡", "孤帆带雨入寒津", "客路逢春春更晚", "暮云低处见归帆"],
            ["江声不管离人意", "柳色偏牵昨日心", "一笛斜阳吹未尽", "一夜江潮到客心"],
            ["他年若问归来处", "应记今宵月满身", "别后山河各自深", "若得来年同看月"],
            ["愿从云外寄平安", "莫将清泪湿征衫", "天涯回首有春山", "休教别泪损芳辰"]
        ]

        let sevenQuiet: [[String]] = [
            ["孤灯照我到三更", "微雪无声落空庭", "旧城风起夜初沉", "一帘疏雨近黄昏"],
            ["万籁归来心未平", "半窗月色冷如冰", "一盏清茶坐到明", "石阶露冷月无痕"],
            ["不知梦去何方宿", "偶有钟声穿薄雾", "尘世喧哗隔一城", "独倚小窗听叶落"],
            ["且听风声过短檐", "只留清影在衣襟", "明朝醒处是新晴", "任由夜色满柴门"],
            ["深巷无人灯自白", "残书有味夜偏长", "檐花滴破三更梦", "远寺钟声穿竹径"],
            ["一榻清寒容我坐", "半生尘事向谁明", "月在窗前人不语", "茶烟一缕绕书痕"],
            ["忽有微风翻旧页", "暗香轻过小帘栊", "此身暂与夜同清", "坐到星河低枕畔"],
            ["天明仍是寻常日", "且把孤心寄晓钟", "雪后空庭见月生", "晓风吹白旧苔痕"]
        ]

        let sevenRelief: [[String]] = [
            ["流云出岫不知愁", "春水无声自向东", "竹影扫阶尘渐空", "白鹭横江天欲晴"],
            ["旧事随风过小楼", "一身轻似晚来风", "心上青山月正中", "往事回看已觉轻"],
            ["回看人间多聚散", "从今不问归何处", "万般滋味入茶中", "不将得失留心上"],
            ["且把余生付远游", "花开花落两从容", "清风明月与人同", "一任松风过此生"],
            ["雨后青山如洗过", "闲云不系旧时愁", "小径无人花自落", "新荷出水香初动"],
            ["一念放开天地阔", "半窗风月入怀清", "从此眉间少旧尘", "小坐溪边听鸟鸣"],
            ["人间得失皆流水", "杯底浮沉看晚晴", "回身已是万山轻", "行到云开山尽处"],
            ["明日春风仍到门", "且留新梦在松阴", "心随白鹭过前溪", "人随春色共徐行"]
        ]

        let fiveDefault: [[String]] = [
            ["春风入小楼", "新晴上高台", "灯暖近家山", "归来花满衣"],
            ["笑语盈帘栊", "花色为君开", "灯火照团圆", "新茶待客来"],
            ["旧愿随燕到", "小字上花笺", "新酿待君尝", "新诗写上笺"],
            ["两袖带清风", "春水映云开", "笑语暖心田", "晴色到樽前"],
            ["芳园寻好景", "柳色过长堤", "新月照窗前", "芳洲意未阑"],
            ["故友意无穷", "清歌入晴空", "今夕分外圆", "清欢夜未央"],
            ["莫问归来晚", "欢情题红叶", "家书重细看", "好景收心底"],
            ["此刻正情浓", "携手花影中", "明朝看春山", "花时再并肩"]
        ]

        let fiveResolve: [[String]] = [
            ["疾雨夜未休", "长风压危楼", "寒灯影如钩", "朔气动客愁"],
            ["世事意未酬", "一纸难平忧", "心火问来由", "隐忍到今秋"],
            ["不肯随俗语", "直气对横流", "冷眼看沉浮", "不肯说罢休"],
            ["胸中千层浪", "笔底一寸秋", "此念不肯收", "孤勇逆风舟"],
            ["浮云遮远目", "清醒立汀洲", "拂尘再举头", "炎凉志未酬"],
            ["风雨过荒丘", "青山在上游", "孤愤付吴钩", "磨剑刃未钝"],
            ["天明云自散", "回身越高丘", "初心莫逐流", "长空月一钩"],
            ["此心更登楼", "仗剑向神州", "正气度春秋", "昂首任行游"]
        ]

        let fiveParting: [[String]] = [
            ["长亭又逢春", "渡口照斜阳", "春雨湿旧尘", "驿路草色新"],
            ["山水又一程", "烟波不见君", "落花满旧门", "旧城送行人"],
            ["离愁藏袖底", "归雁过江津", "相逢应有期", "临歧还无语"],
            ["前路有晴云", "天涯问旧痕", "人间各有春", "重逢在早春"],
            ["远树含春烟", "孤帆带夜雨", "客路春将晚", "暮云见归帆"],
            ["江声不管愁", "柳色牵旧心", "斜阳笛未尽", "江潮到客心"],
            ["他年问归处", "今宵月满身", "山河别后深", "来年同看月"],
            ["云外寄平安", "清泪莫沾衫", "回首见春山", "别泪莫伤春"]
        ]

        let fiveQuiet: [[String]] = [
            ["孤灯到三更", "微雪落空庭", "旧城夜色沉", "疏雨近黄昏"],
            ["万籁心未平", "月色冷如冰", "清茶坐到明", "露冷月无痕"],
            ["梦去知何方", "钟声穿薄雾", "尘世隔孤城", "小窗听叶落"],
            ["且听过檐风", "清影在衣襟", "醒处是新晴", "夜色满柴门"],
            ["深巷孤灯白", "残书伴夜长", "檐花惊旧梦", "钟声穿竹径"],
            ["清寒容我坐", "尘事向谁明", "月前人不语", "茶烟绕书痕"],
            ["微风翻旧页", "暗香过小帘", "此身与夜清", "星河低枕畔"],
            ["天明仍如常", "孤心寄晓钟", "雪后月初生", "晓风白苔痕"]
        ]

        let fiveRelief: [[String]] = [
            ["流云自出岫", "春水自向东", "竹影扫心尘", "白鹭天欲晴"],
            ["旧事已随风", "此身似晚风", "心上有青山", "往事已觉轻"],
            ["回看多聚散", "从今不问归", "滋味尽入茶", "得失不留心"],
            ["余生付远游", "花落亦从容", "明月与人同", "松风过此生"],
            ["雨后青山净", "闲云不系愁", "小径花自落", "新荷香初动"],
            ["一念天地阔", "风月入我怀", "眉间少旧尘", "溪边听鸟鸣"],
            ["得失皆流水", "杯底看晚晴", "回身万山轻", "云开山尽处"],
            ["春风又到门", "新梦在松阴", "心随白鹭行", "春色共徐行"]
        ]

        let table: [[String]]
        let context = ([mood.id] + mood.tags + [image.id, image.title]).joined(separator: " ")
        let family: String
        if ["part", "resolve", "quiet", "relief", "default"].contains(mood.id) {
            // A separately chosen feeling is an explicit creative direction and
            // should take precedence when its tone conflicts with the theme.
            family = mood.id
        } else if context.contains("哀") || context.contains("別") || context.contains("离") || context.contains("遠") {
            family = "part"
        } else if context.contains("怒") || context.contains("不平") || context.contains("委屈") || context.contains("不甘") {
            family = "resolve"
        } else if context.contains("乐") || context.contains("樂") || context.contains("放下") || context.contains("鬆弛") {
            family = "relief"
        } else if context.contains("夜") || context.contains("孤") {
            family = "quiet"
        } else {
            family = "default"
        }

        switch (family, form.meter) {
        case ("part", .five):
            table = fiveParting
        case ("resolve", .five):
            table = fiveResolve
        case ("quiet", .five):
            table = fiveQuiet
        case ("relief", .five):
            table = fiveRelief
        case (_, .five):
            table = fiveDefault
        case ("part", .seven):
            table = sevenParting
        case ("resolve", .seven):
            table = sevenResolve
        case ("quiet", .seven):
            table = sevenQuiet
        case ("relief", .seven):
            table = sevenRelief
        default:
            table = sevenDefault
        }

        let rowIndex = ((index % table.count) + table.count) % table.count
        let row = table[rowIndex]
        let canonicalPrevious = selectedLines.last?.poemScript(.simplified)
        let routeFromPrevious: Int? = {
            guard rowIndex > 0, let canonicalPrevious else { return nil }
            return table[rowIndex - 1].firstIndex { $0.poemScript(.simplified) == canonicalPrevious }
        }()
        let stableSeed = (mood.title + image.id).unicodeScalars.reduce(0) { $0 + Int($1.value) }
        let preferredRoute = routeFromPrevious ?? (stableSeed % row.count)
        let start = (preferredRoute + refreshSeed) % row.count
        return (0..<min(3, row.count)).map { row[(start + $0) % row.count] }
    }
}

#Preview {
    PoemComposerView()
}
