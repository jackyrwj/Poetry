import SwiftUI
import UIKit
import CoreFoundation
import StoreKit


struct PoemComposerView: View {
    @Environment(\.spotlightGuide) private var spotlightGuide
    @AppStorage(PoemTypeface.storageKey) private var typefaceRawValue = PoemTypeface.kaiti.rawValue
    @AppStorage(PoemScript.storageKey) private var scriptRawValue = PoemScript.simplified.rawValue
    @AppStorage(PoemBackground.storageKey) private var backgroundRawValue = PoemBackground.defaultBackground.rawValue
    @AppStorage(PoemStructure.storageKey) private var structureRawValue = PoemStructure.jueju.rawValue
    @AppStorage(PoemMeter.storageKey) private var meterRawValue = PoemMeter.five.rawValue
    @AppStorage(SealStampStyle.storageKey) private var sealStyleRawValue = SealStampStyle.zhuwen.rawValue
    @AppStorage("poemTypefaceMigratedToHuiwenDefault") private var migratedToHuiwenDefault = false
    @AppStorage("poemScriptMigratedToSimplifiedDefault") private var migratedToSimplifiedDefault = false
    @AppStorage(AppReviewPrompt.completedFirstPoemKey) private var completedFirstPoem = false
    @AppStorage(AppReviewPrompt.requestedAfterFirstPoemKey) private var requestedReviewAfterFirstPoem = false
    @StateObject private var locationProvider = PoemLocationProvider()
    @State private var stage: ComposeStage = .heart
    @State private var selectedMood = PoetrySeed.moods[0]
    @State private var moodLevel1: String? = nil
    @State private var moodLevel2: String? = nil
    @State private var moodLevel3: String? = nil
    @State private var selectedImage = PoetrySeed.images[0]
    @State private var homeImages = PoetrySeed.images
    @State private var selectedLines: [String] = []
    @State private var currentLineIndex = 0
    @State private var showsFontSettings = false
    @State private var showsArchive = false
    @State private var savedPoems = PoemArchiveStore.load()
    @State private var isRefreshingImages = false
    @State private var recentHomeImageTitles: [String] = PoetrySeed.images.map(\.title)
    @State private var selectedPoemForPreview: SavedPoem?

    private var poemForm: PoemFormSpec {
        PoemFormSpec(
            structure: PoemStructure(rawValue: structureRawValue) ?? .jueju,
            meter: PoemMeter(rawValue: meterRawValue) ?? .five
        )
    }

    var body: some View {
        ZStack {
            PaperBackground()

            switch stage {
            case .heart:
                HeartQuestionView(
                    level1: $moodLevel1,
                    level2: $moodLevel2,
                    level3: $moodLevel3,
                    onNext: {
                        selectedMood = MoodSeed(tags: [moodLevel1, moodLevel2, moodLevel3].compactMap { $0 })
                        let fallback = PoetrySeed.images(for: selectedMood)
                        homeImages = []
                        isRefreshingImages = true
                        stage = .image
                        loadHomeImages(for: selectedMood, fallback: fallback)
                    }
                )
            case .image:
                ImagePickingView(
                    mood: selectedMood,
                    images: homeImages,
                    selectedImage: $selectedImage,
                    onNext: {
                        startPoemIfAllowed()
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
                    mood: selectedMood,
                    image: selectedImage,
                    poemForm: poemForm,
                    lineIndex: currentLineIndex,
                    selectedLines: selectedLines,
                    onPick: pickLine,
                    onBackToImage: backToImagePicking,
                    onBackLine: backToPreviousLine
                )
                .id("line-\(poemForm.id)-\(currentLineIndex)-\(selectedLines.count)")
            case .finish:
                FinishedPoemView(
                    mood: selectedMood,
                    image: selectedImage,
                    lines: selectedLines,
                    onReviseLine: { index in
                        let safeIndex = min(max(index, 0), selectedLines.count)
                        currentLineIndex = safeIndex
                        selectedLines = Array(selectedLines.prefix(safeIndex))
                        stage = .line
                    },
                    onSave: { poem in
                        savedPoems = PoemArchiveStore.save(poem)
                    },
                    onRestart: {
                        returnHomeFromFinishedPoem()
                    }
                )
            }

            if stage == .heart {
                HStack(spacing: 10) {
                    SmallCircleButton(systemName: "clock.arrow.circlepath", spotlightStep: .openHistory) {
                        savedPoems = PoemArchiveStore.load()
                        showsArchive = true
                    }
                    SmallCircleButton(systemName: "gearshape.fill") {
                        showsFontSettings = true
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.trailing, 24)
                .padding(.top, 76)
            }
        }
        .spotlightOverlay(for: [.openHistory])
        .foregroundStyle(Color.ink)
        .environment(\.poemTypeface, PoemTypeface(rawValue: typefaceRawValue) ?? .kaiti)
        .environment(\.poemScript, PoemScript(rawValue: scriptRawValue) ?? .simplified)
        .environmentObject(locationProvider)
        .sheet(isPresented: $showsFontSettings) {
            FontSettingsView()
        }
        .fullScreenCover(isPresented: $showsArchive) {
            PoemArchiveView(poems: $savedPoems)
        }
        .fullScreenCover(item: $selectedPoemForPreview) { poem in
            PoemSharePreviewView(
                imageTitle: poem.imageTitle,
                lines: poem.lines,
                locationMark: poem.locationText,
                lunarDateText: poem.lunarDateText,
                dayPeriodText: poem.dayPeriodText
            )
        }
        .onAppear {
            migrateDefaultTypefaceIfNeeded()
            migrateDefaultScriptIfNeeded()
            PoemBackground.migrateAppPaperDefaultToBoatIfNeeded(selectedBgRaw: &backgroundRawValue)
            spotlightGuide.startIfNeeded()
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

    private func startPoemIfAllowed() {
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

    private func restartPoem() {
        moodLevel1 = nil
        moodLevel2 = nil
        moodLevel3 = nil
        selectedLines.removeAll()
        currentLineIndex = 0
        homeImages = PoetrySeed.images
        isRefreshingImages = false
        savedPoems = PoemArchiveStore.load()
        stage = .heart
    }

    private func returnHomeFromFinishedPoem() {
        let shouldContinueGuide = spotlightGuide.step == .returnHome
        restartPoem()

        if shouldContinueGuide {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                spotlightGuide.advance()
            }
        } else {
            requestReviewAfterFirstPoemIfNeeded()
        }
    }

    private func requestReviewAfterFirstPoemIfNeeded() {
        guard completedFirstPoem, !requestedReviewAfterFirstPoem else { return }
        requestedReviewAfterFirstPoem = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            AppReviewPrompt.request()
        }
    }

    private func refreshHomeImages() {
        loadHomeImages(for: selectedMood, fallback: PoetrySeed.rotatingImages(excluding: recentHomeImageTitles))
    }

    private func loadHomeImages(for mood: MoodSeed, fallback: [ImageSeed]) {
        if isRefreshingImages && !homeImages.isEmpty { return }
        isRefreshingImages = true

        Task {
            let images: [ImageSeed]
            do {
                images = try await BailianPoetryClient().generateImageSeeds(
                    mood: mood,
                    fallback: fallback,
                    excluding: recentHomeImageTitles,
                    script: PoemScript(rawValue: scriptRawValue) ?? .simplified
                )
            } catch {
                images = fallback
            }

            await MainActor.run {
                guard selectedMood == mood else {
                    isRefreshingImages = false
                    return
                }
                let freshImages = PoetrySeed.nonRepeatingImages(images, excluding: recentHomeImageTitles)
                homeImages = freshImages
                rememberHomeImages(freshImages)
                selectedImage = freshImages.first ?? PoetrySeed.images[0]
                isRefreshingImages = false
            }
        }
    }

    private func rememberHomeImages(_ images: [ImageSeed]) {
        let updated = recentHomeImageTitles + images.map(\.title)
        recentHomeImageTitles = Array(updated.suffix(18))
    }
}

private struct FontSettingsButton: View {
    @Environment(\.poemTypeface) private var typeface
    @Environment(\.poemScript) private var script
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("設".poemScript(script))
                .font(typeface.sealFont)
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.cinnabar))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .padding(.trailing, 24)
        .padding(.top, 76)
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
                } else if let title {
                    Text(title.poemScript(script))
                        .font(typeface.font(size: 17))
                }
            }
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
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
                    .frame(width: 1, height: 34)
                VerticalText(title.poemScript(script), font: typeface.tinySealFont, color: .mutedInk, spacing: 3)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .spotlightTarget(spotlightStep ?? .selectMood, active: isSpotlightTarget)
    }
}

private struct FontSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.poemTypeface) private var typeface
    @Environment(\.poemScript) private var script
    @AppStorage(PoemTypeface.storageKey) private var selectedRawValue = PoemTypeface.kaiti.rawValue
    @AppStorage(PoemScript.storageKey) private var selectedScriptRawValue = PoemScript.simplified.rawValue
    @AppStorage(PoemStructure.storageKey) private var selectedStructureRawValue = PoemStructure.jueju.rawValue
    @AppStorage(PoemMeter.storageKey) private var selectedMeterRawValue = PoemMeter.five.rawValue
    @AppStorage(SealStampView.storageKey) private var sealName = ""
    @AppStorage(SealStampStyle.storageKey) private var selectedSealStyleRawValue = SealStampStyle.zhuwen.rawValue
    @State private var editingSealName = ""
    @State private var showsAbout = false
    @FocusState private var sealNameFocused: Bool

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
                        Text("設置".poemScript(script))
                            .font(typeface.titleFont)
                            .foregroundStyle(Color.ink)
                        Spacer()
                        QuietBackButton(title: "返回") { dismiss() }
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        Text("朱印".poemScript(script))
                            .font(typeface.smallFont)
                            .foregroundStyle(Color.mutedInk)

                        HStack(alignment: .top, spacing: 24) {
                            VStack(alignment: .leading, spacing: 14) {
                                VStack(alignment: .leading, spacing: 8) {
                                    TextField("", text: $editingSealName, prompt: Text("姓名".poemScript(script)).foregroundStyle(Color.mutedInk.opacity(0.5)))
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

                                HStack(spacing: 12) {
                                    ForEach(SealStampStyle.allCases) { style in
                                        Button {
                                            sealNameFocused = false
                                            selectedSealStyleRawValue = style.rawValue
                                        } label: {
                                            Text(style.displayName.poemScript(script))
                                                .font(typeface.tinySealFont)
                                                .foregroundStyle(selectedSealStyleRawValue == style.rawValue ? Color.cinnabar : Color.mutedInk)
                                                .frame(width: 48, height: 28)
                                                .background {
                                                    RoundedRectangle(cornerRadius: 7)
                                                        .stroke(selectedSealStyleRawValue == style.rawValue ? Color.cinnabar.opacity(0.85) : Color.mutedInk.opacity(0.25), lineWidth: 0.9)
                                                }
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .frame(maxWidth: 142)

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
                        Text("字體".poemScript(script))
                            .font(typeface.smallFont)
                            .foregroundStyle(Color.mutedInk)

                        HStack(alignment: .top, spacing: 28) {
                            ForEach(PoemTypeface.allCases) { typeface in
                                Button {
                                    selectedRawValue = typeface.rawValue
	                                } label: {
	                                    VStack(spacing: 14) {
	                                        VerticalText(typeface.displayName, font: typeface.previewFont(size: 17), spacing: 6, forceVertical: true)

	                                        Text(selectedRawValue == typeface.rawValue ? "擇".poemScript(script) : " ")
	                                            .font(typeface.previewFont(size: 12))
	                                            .foregroundStyle(.white)
	                                            .frame(width: 23, height: 23)
	                                            .background(Circle().fill(selectedRawValue == typeface.rawValue ? Color.cinnabar : Color.clear))
	                                    }
	                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }

                    ScriptStylePicker(selectedRawValue: $selectedScriptRawValue)

                    PoemFormPicker(
                        selectedStructureRawValue: $selectedStructureRawValue,
                        selectedMeterRawValue: $selectedMeterRawValue
                    )

                    ShadowStylePicker()

                    SettingsNavigationRow(title: "關於", mark: "息") {
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
        .onAppear {
            editingSealName = sealName
        }
        .onDisappear {
            sealName = normalizedSealName
        }
    }

    private var normalizedSealName: String {
        let trimmed = editingSealName.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(4))
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
                        Text("關於".poemScript(script))
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
                                Text("织诗".poemScript(script))
                                    .font(typeface.titleFont)
                                    .foregroundStyle(Color.ink)
                                Text("以今日心緒，生成一首可收藏的古詩。".poemScript(script))
                                    .font(typeface.smallFont)
                                    .foregroundStyle(Color.mutedInk)
                            }
                            .padding(.bottom, 4)

                            aboutStaticRow(title: "版本", value: appVersionText, mark: "版")

                            aboutRow(title: "用戶協議", mark: "約") {
                                legalDocument = .terms
                            }

                            aboutRow(title: "隱私政策", mark: "隱") {
                                legalDocument = .privacy
                            }

                            aboutRow(title: "聯繫我們", mark: "信") {
                                showsContact = true
                            }

                            aboutRow(title: "評價", mark: "評") {
                                AppReviewPrompt.request()
                            }

                            ShareLink(item: "我在用织诗，以今日心绪生成一首古诗。") {
                                rowContent(title: "分享給好友", value: nil, mark: "享")
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
                    Text("聯繫我們".poemScript(script))
                        .font(typeface.titleFont)
                        .foregroundStyle(Color.ink)

                    Spacer()

                    QuietBackButton(title: "返回") { dismiss() }
                }
                .padding(.horizontal, 30)
                .padding(.top, 56)
                .padding(.bottom, 28)

                VStack(alignment: .leading, spacing: 18) {
                    contactRow(title: "郵箱", value: "raowenjieszu@gmail.com", mark: "郵") {
                        if let url = URL(string: "mailto:raowenjieszu@gmail.com?subject=织诗") {
                            openURL(url)
                        }
                    }

                    contactRow(title: "小紅書", value: "织诗", mark: "書") {
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
        case .terms: return "用戶協議"
        case .privacy: return "隱私政策"
        }
    }

    var bodyText: String {
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

    /// Is the current selection a shadow effect (vs a background image)?
    private var isShadowSelected: Bool {
        let background = PoemBackground(rawValue: selectedBgRaw)
        return background == PoemBackground.none || background == nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("紙面".poemScript(script))
                .font(typeface.smallFont)
                .foregroundStyle(Color.mutedInk)

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
                                        Text("擇".poemScript(script))
                                            .font(typeface.tinySealFont)
                                            .foregroundStyle(.white)
                                            .frame(width: 18, height: 18)
                                            .background(Circle().fill(Color.cinnabar))
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
                                        Text("擇".poemScript(script))
                                            .font(typeface.tinySealFont)
                                            .foregroundStyle(.white)
                                            .frame(width: 18, height: 18)
                                            .background(Circle().fill(Color.cinnabar))
                                            .offset(x: 5, y: 5)
                                            .transition(.scale(scale: 0.75).combined(with: .opacity))
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
        }
    }
}

private struct ScriptStylePicker: View {
    @Environment(\.poemTypeface) private var typeface
    @Environment(\.poemScript) private var script
    @Binding var selectedRawValue: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("字形".poemScript(script))
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
                            Text(selectedRawValue == item.rawValue ? "擇".poemScript(script) : " ")
                                .font(typeface.tinySealFont)
                                .foregroundStyle(.white)
                                .frame(width: 22, height: 22)
                                .background(Circle().fill(selectedRawValue == item.rawValue ? Color.cinnabar : Color.clear))
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

private struct PoemFormPicker: View {
    @Environment(\.poemTypeface) private var typeface
    @Environment(\.poemScript) private var script
    @Binding var selectedStructureRawValue: String
    @Binding var selectedMeterRawValue: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("詩式".poemScript(script))
                .font(typeface.smallFont)
                .foregroundStyle(Color.mutedInk)

            VStack(alignment: .leading, spacing: 12) {
                optionRow(
                    items: PoemStructure.allCases,
                    selectedRawValue: selectedStructureRawValue,
                    select: { item in
                        selectedStructureRawValue = item.rawValue
                    }
                )

                optionRow(
                    items: PoemMeter.allCases,
                    selectedRawValue: selectedMeterRawValue,
                    select: { item in
                        selectedMeterRawValue = item.rawValue
                    }
                )
            }
        }
    }

    private func optionRow<Item: PoemFormOption>(
        items: [Item],
        selectedRawValue: String,
        select: @escaping (Item) -> Void
    ) -> some View {
        HStack(spacing: 14) {
            ForEach(items) { item in
                Button {
                    select(item)
                } label: {
                    HStack(spacing: 8) {
                        Text(item.displayName.poemScript(script))
                            .font(typeface.smallFont)
                            .foregroundStyle(selectedRawValue == item.rawValue ? Color.ink : Color.mutedInk)
                        Text(selectedRawValue == item.rawValue ? "擇".poemScript(script) : " ")
                            .font(typeface.tinySealFont)
                            .foregroundStyle(selectedRawValue == item.rawValue ? .white : .clear)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(selectedRawValue == item.rawValue ? Color.cinnabar : Color.clear))
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
            timeGreeting = "晨安"
        case 8...10:
            timeGreeting = "日安"
        case 11...13:
            timeGreeting = "午安"
        case 14...16:
            timeGreeting = "日暮將至"
        case 17...18:
            timeGreeting = "暮安"
        case 19...22:
            timeGreeting = "夜安"
        default:
            timeGreeting = "夜深了"
        }
        if sealName.isEmpty {
            return timeGreeting
        }
        return "\(sealName)　\(timeGreeting)"
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
                SealTextButton(title: "撰", action: onCompose)
                    .padding(.bottom, 48)

                // Saved poems — two-column grid
                if !savedPoems.isEmpty {
                    VStack(spacing: 18) {
                        Text("往日詩作".poemScript(script))
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

private struct HeartQuestionView: View {
    @Environment(\.poemTypeface) private var typeface
    @Environment(\.poemScript) private var script
    @Binding var level1: String?
    @Binding var level2: String?
    @Binding var level3: String?
    let onNext: () -> Void
    var onBack: (() -> Void)? = nil

    @State private var level2Options: [String] = []
    @State private var level3Options: [String] = []
    @State private var isLoadingL2 = false
    @State private var isLoadingL3 = false

    private var currentLevel: Int {
        if level1 == nil { return 1 }
        if level2 == nil { return 2 }
        if level3 == nil { return 3 }
        return 4
    }

    private var canProceed: Bool { currentLevel == 4 }

    private var l2Display: [String] {
        level2Options.isEmpty ? MoodLevels.level2(for: level1 ?? "") : level2Options
    }

    private var l3Display: [String] {
        level3Options.isEmpty ? MoodLevels.level3(for: level1 ?? "", level2 ?? "") : level3Options
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("今日心中".poemScript(script))
                            .font(typeface.titleFont)
                        Text("有什麼放不下".poemScript(script))
                            .font(typeface.bodyFont)
                            .tracking(3)
                    }
                    Spacer()
                    if let onBack {
                        QuietBackButton(title: "返回", action: onBack)
                    }
                }
                .padding(.top, 72)
                .padding(.leading, 30)
                .padding(.trailing, 24)

                Spacer().frame(height: 28)

                VStack(alignment: .leading, spacing: 18) {
                    MoodLevelRow(
                        label: "先择一情",
                        options: MoodLevels.level1,
                        selected: level1,
                        isCurrent: currentLevel == 1,
                        isLoading: false,
                        maxCharacters: 1,
                        onRefresh: nil,
                        onSelect: { pick in
                            if level1 == pick {
                                withAnimation(.easeOut(duration: 0.3)) {
                                    level1 = nil; level2 = nil; level3 = nil
                                    level2Options = []; level3Options = []
                                    isLoadingL2 = false; isLoadingL3 = false
                                }
                                return
                            }

                            withAnimation(.easeOut(duration: 0.3)) {
                                level1 = pick; level2 = nil; level3 = nil
                                level2Options = []; level3Options = []
                            }
                            loadLevel2(for: pick)
                        }
                    )

                    if level1 != nil {
                        MoodLevelRow(
                            label: MoodLevels.level2Label(for: level1 ?? ""),
                            options: l2Display,
                            selected: level2,
                            isCurrent: currentLevel == 2,
                            isLoading: isLoadingL2 && level2Options.isEmpty,
                            maxCharacters: 4,
                            onRefresh: { loadLevel2(for: level1 ?? "", forceLocalRotation: true) },
                            onSelect: { pick in
                                if level2 == pick {
                                    withAnimation(.easeOut(duration: 0.3)) {
                                        level2 = nil; level3 = nil
                                        level3Options = []
                                        isLoadingL3 = false
                                    }
                                    return
                                }

                                withAnimation(.easeOut(duration: 0.3)) {
                                    level2 = pick; level3 = nil
                                    level3Options = []
                                }
                                loadLevel3(for: level1 ?? "", pick)
                            }
                        )
                        .transition(.opacity.combined(with: .offset(y: 10)))
                    }

                    if level2 != nil {
                        MoodLevelRow(
                            label: "身在何處",
                            options: l3Display,
                            selected: level3,
                            isCurrent: currentLevel == 3,
                            isLoading: isLoadingL3 && level3Options.isEmpty,
                            maxCharacters: 4,
                            onRefresh: { loadLevel3(for: level1 ?? "", level2 ?? "", forceLocalRotation: true) },
                            onSelect: { pick in
                                if level3 == pick {
                                    withAnimation(.easeOut(duration: 0.3)) {
                                        level3 = nil
                                    }
                                    return
                                }

                                withAnimation(.easeOut(duration: 0.3)) {
                                    level3 = pick
                                }
                            }
                        )
                        .transition(.opacity.combined(with: .offset(y: 10)))
                    }
                }
                .padding(.horizontal, 30)
                .animation(.easeOut(duration: 0.35), value: currentLevel)

                Spacer(minLength: 16)

                if canProceed {
                    SealTextButton(title: "撰", action: onNext)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.bottom, 30)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
            .clipped()
            .contentShape(Rectangle())
            .onTapGesture {
                dismissKeyboard()
            }
        }
        .animation(.easeOut(duration: 0.35), value: canProceed)
        .spotlightOverlay(for: [.selectMood])
    }

    private func loadLevel2(for l1: String, forceLocalRotation: Bool = false) {
        if forceLocalRotation {
            withAnimation(.easeOut(duration: 0.25)) {
                level2Options = MoodLevels.rotatingLevel2(for: l1)
            }
            return
        }

        isLoadingL2 = true
        Task {
            do {
                let options = try await BailianPoetryClient().generateMoodOptions(
                        level: 2, l1: l1, l2: nil,
                        fallback: MoodLevels.level2(for: l1),
                        maxCharacters: 4,
                        script: PoemScript(rawValue: UserDefaults.standard.string(forKey: PoemScript.storageKey) ?? "") ?? .simplified
                )
                await MainActor.run {
                    guard level1 == l1 else { return }
                    withAnimation(.easeOut(duration: 0.25)) {
                        level2Options = mergeMoodOptions(options, fallback: level2Options.isEmpty ? MoodLevels.level2(for: l1) : level2Options, maxCharacters: 4)
                        isLoadingL2 = false
                    }
                }
            } catch {
                await MainActor.run { isLoadingL2 = false }
            }
        }
    }

    private func loadLevel3(for l1: String, _ l2: String, forceLocalRotation: Bool = false) {
        if forceLocalRotation {
            withAnimation(.easeOut(duration: 0.25)) {
                level3Options = MoodLevels.rotatingLevel3(for: l1, l2)
            }
            return
        }

        isLoadingL3 = true
        Task {
            do {
                let options = try await BailianPoetryClient().generateMoodOptions(
                        level: 3, l1: l1, l2: l2,
                        fallback: MoodLevels.level3(for: l1, l2),
                        maxCharacters: 4,
                        script: PoemScript(rawValue: UserDefaults.standard.string(forKey: PoemScript.storageKey) ?? "") ?? .simplified
                )
                await MainActor.run {
                    guard level1 == l1 && level2 == l2 else { return }
                    withAnimation(.easeOut(duration: 0.25)) {
                        level3Options = mergeMoodOptions(options, fallback: level3Options.isEmpty ? MoodLevels.level3(for: l1, l2) : level3Options, maxCharacters: 4)
                        isLoadingL3 = false
                    }
                }
            } catch {
                await MainActor.run { isLoadingL3 = false }
            }
        }
    }

    private func mergeMoodOptions(_ generated: [String], fallback: [String], maxCharacters: Int) -> [String] {
        var result: [String] = []
        for option in generated + fallback {
            let normalized = normalizedMoodOption(option, maxCharacters: maxCharacters)
            if !normalized.isEmpty && !result.contains(normalized) {
                result.append(normalized)
            }
        }
        return Array(result.prefix(8))
    }

    private func normalizedMoodOption(_ value: String, maxCharacters: Int) -> String {
        let visibleCharacters = value.filter { character in
            !character.isWhitespace && !character.isNewline
        }
        return String(visibleCharacters.prefix(maxCharacters))
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

/// A single level row: label + options. Completed levels show selected option highlighted;
/// tapping a different option in a completed level re-selects it (and resets levels below).
private struct MoodLevelRow: View {
    @Environment(\.poemTypeface) private var typeface
    @Environment(\.poemScript) private var script
    let label: String
    let options: [String]
    let selected: String?
    let isCurrent: Bool
    let isLoading: Bool
    let maxCharacters: Int
    let onRefresh: (() -> Void)?
    var onBeginCustomEdit: (() -> Void)? = nil
    let onSelect: (String) -> Void
    @State private var isAddingCustomOption = false
    @State private var customOption = ""
    @State private var showsLimitHint = false
    @FocusState private var customFocused: Bool

    private var displayedOptions: [String] {
        guard let selected, !options.contains(selected) else { return options }
        return options + [selected]
    }

    private var optionDiameter: CGFloat {
        maxCharacters > 1 ? 62 : 56
    }

    private var customPrompt: String {
        maxCharacters == 1 ? "一字" : "四字"
    }

    private var limitHint: String {
        maxCharacters == 1 ? "最多一字" : "最多四字"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text(label.poemScript(script))
                    .font(typeface.smallFont)
                    .foregroundStyle(Color.mutedInk)

                Spacer()

                if let onRefresh {
                    Button("換".poemScript(script)) {
                        onRefresh()
                    }
                    .font(typeface.tinySealFont)
                    .foregroundStyle(Color.cinnabar)
                    .buttonStyle(.plain)
                }
            }

            if showsLimitHint {
                Text(limitHint.poemScript(script))
                    .font(typeface.tinySealFont)
                    .foregroundStyle(Color.cinnabar.opacity(0.78))
                    .transition(.opacity.combined(with: .offset(y: -3)))
            }

            if isLoading {
                MoodLoadingIndicator(text: "取意中")
                    .padding(.top, 4)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: optionDiameter), spacing: 12)], alignment: .leading, spacing: 10) {
                    ForEach(displayedOptions, id: \.self) { option in
                        MoodOptionButton(
                            title: option,
                            isSelected: selected == option,
                            dimmed: !isCurrent && selected != option
                        ) {
                            onSelect(option)
                        }
                    }

                    if isCurrent {
                        customOptionControl
                    }
                }
            }
        }
        .opacity(isCurrent ? 1 : 0.85)
    }

    @ViewBuilder
    private var customOptionControl: some View {
        if isAddingCustomOption {
            TextField("", text: $customOption, prompt: Text(customPrompt.poemScript(script)).foregroundStyle(Color.mutedInk.opacity(0.45)))
                .font(typeface.tinySealFont)
                .foregroundStyle(Color.ink)
                .focused($customFocused)
                .multilineTextAlignment(.center)
                .frame(width: optionDiameter, height: optionDiameter)
                .background {
                    Circle()
                        .stroke(Color.cinnabar.opacity(0.75), lineWidth: 1)
                }
                .submitLabel(.done)
                .onSubmit(commitCustomOption)
                .onChange(of: customFocused) { oldValue, newValue in
                    if oldValue && !newValue {
                        commitCustomOption()
                    }
                }
                .onChange(of: customOption) { _, newValue in
                    if visibleCharacterCount(newValue) > maxCharacters {
                        showLimitHint()
                    }
                    let normalized = normalizedCustomOption(newValue)
                    if normalized != newValue {
                        customOption = normalized
                    }
                }
        } else {
            Button {
                isAddingCustomOption = true
                onBeginCustomEdit?()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    customFocused = true
                }
            } label: {
                Text("+")
                    .font(typeface.smallFont)
                    .foregroundStyle(Color.cinnabar)
                    .frame(width: optionDiameter, height: optionDiameter)
                    .background {
                        Circle()
                            .stroke(Color.cinnabar.opacity(0.75), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
        }
    }

    private func commitCustomOption() {
        let option = normalizedCustomOption(customOption)
        guard !option.isEmpty else {
            customOption = ""
            isAddingCustomOption = false
            customFocused = false
            return
        }
        customOption = option
        onSelect(option)
        customOption = ""
        isAddingCustomOption = false
        customFocused = false
    }

    private func normalizedCustomOption(_ value: String) -> String {
        let visibleCharacters = value.filter { character in
            !character.isWhitespace && !character.isNewline
        }
        return String(visibleCharacters.prefix(maxCharacters))
    }

    private func visibleCharacterCount(_ value: String) -> Int {
        value.filter { character in
            !character.isWhitespace && !character.isNewline
        }.count
    }

    private func showLimitHint() {
        withAnimation(.easeOut(duration: 0.18)) {
            showsLimitHint = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.25) {
            withAnimation(.easeOut(duration: 0.2)) {
                showsLimitHint = false
            }
        }
    }
}

private struct MoodLoadingIndicator: View {
    @Environment(\.poemTypeface) private var typeface
    @Environment(\.poemScript) private var script
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
                .tint(Color.cinnabar)

            Text("\(text)…".poemScript(script))
                .font(typeface.smallFont)
                .foregroundStyle(Color.cinnabar)
        }
        .padding(.horizontal, 14)
        .frame(height: 42)
        .background {
            Capsule()
                .fill(Color.white.opacity(0.72))
                .stroke(Color.cinnabar.opacity(0.24), lineWidth: 0.8)
        }
        .shadow(color: Color.cinnabar.opacity(0.08), radius: 10, x: 0, y: 5)
        .accessibilityLabel(Text(text.poemScript(script)))
    }
}

private struct MoodOptionButton: View {
    @Environment(\.poemTypeface) private var typeface
    @Environment(\.poemScript) private var script
    @Environment(\.spotlightGuide) private var spotlightGuide
    let title: String
    var isSelected: Bool = false
    var dimmed: Bool = false
    let action: () -> Void

    private var diameter: CGFloat {
        title.count > 2 ? 62 : 56
    }

    private var optionFont: Font {
        if title.count > 2 {
            return typeface.tinySealFont
        }
        return typeface.sealFont
    }

    private var isSpotlightTarget: Bool {
        spotlightGuide.step == .selectMood && title == "喜"
    }

    var body: some View {
        Button {
            action()
            if isSpotlightTarget {
                spotlightGuide.advance()
            }
        } label: {
            Text(title.poemScript(script))
                .font(optionFont)
                .foregroundStyle(isSelected ? .white : Color.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.68)
                .multilineTextAlignment(.center)
                .frame(width: diameter, height: diameter)
                .background {
                    Circle()
                        .fill(isSelected ? Color.cinnabar : Color.white.opacity(0.5))
                        .stroke(isSelected ? Color.cinnabar : Color.mutedInk.opacity(0.35), lineWidth: 0.8)
                }
        }
        .buttonStyle(.plain)
        .frame(width: diameter, height: diameter)
        .opacity(dimmed ? 0.3 : 1)
        .spotlightTarget(.selectMood, active: isSpotlightTarget)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isSelected)
    }
}

private struct ImagePickingView: View {
    @Environment(\.poemTypeface) private var typeface
    @Environment(\.poemScript) private var script
    @Environment(\.spotlightGuide) private var spotlightGuide
    let mood: MoodSeed
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
                QuietBackButton(title: "返回", action: onBack)
                    .position(x: size.width * 0.91, y: size.height * 0.09)

                Text("待選題目".poemScript(script))
                    .font(typeface.smallFont)
                    .tracking(4)
                    .foregroundStyle(Color.cinnabar)
                    .position(x: size.width * 0.50, y: size.height * 0.32)

                // Center: image choices
                ZStack {
                    if images.isEmpty && isRefreshing {
                        VerticalText("取意中", style: .small, color: .mutedInk, spacing: 6)
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
                .position(x: size.width * 0.50, y: size.height * 0.48)

                // Below choices: refresh and go share the same baseline.
                HStack(spacing: 28) {
                    SmallCircleButton(title: "換", action: onRefresh)
                        .opacity(isRefreshing ? 0.35 : 1)
                        .disabled(isRefreshing)

                    SmallCircleButton(title: "撰", action: onNext)
                        .opacity(images.isEmpty ? 0.35 : 1)
                        .allowsHitTesting(!images.isEmpty)
                }
                .position(x: size.width * 0.50, y: size.height * 0.68)

            }
            .frame(width: size.width, height: size.height)
        }
        .spotlightOverlay(for: [.selectImage])
    }
}

private struct LinePickingView: View {
    @Environment(\.poemTypeface) private var typeface
    @Environment(\.poemScript) private var script
    @Environment(\.spotlightGuide) private var spotlightGuide
    let mood: MoodSeed
    let image: ImageSeed
    let poemForm: PoemFormSpec
    let lineIndex: Int
    let selectedLines: [String]
    let onPick: (String) -> Void
    let onBackToImage: () -> Void
    let onBackLine: () -> Void
    @State private var choicesVisible = false
    @State private var pickedLine: String?
    @State private var sealPulse = false
    @State private var candidateLines: [String] = []
    @State private var isLoadingCandidates = false
    @State private var requestID = UUID()
    @State private var cancelPendingPick = false
    @State private var refreshSeed = 0
    @State private var showSelfWrite = false
    @State private var selfWriteText = ""

    private var fallbackOptions: [String] {
        PoetrySeed.lines(for: mood, image: image, form: poemForm, index: lineIndex + refreshSeed).map { $0.poemScript(script) }
    }

    private var options: [String] {
        candidateLines.isEmpty ? fallbackOptions : candidateLines
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let isWide = size.width > size.height
            let candidateSpacing = min(64, max(42, size.width * 0.12))
            let candidateCenterX = isWide ? size.width * 0.54 : size.width * 0.50
            let candidateCenterY = isWide ? size.height * 0.56 : size.height * 0.58
            let previousCenterX = isWide ? size.width * 0.17 : size.width * 0.16
            let previousCenterY = isWide ? size.height * 0.74 : size.height * 0.84

            ZStack {
                QuietBackButton(title: "返回") {
                    cancelPendingPick = true
                    if lineIndex == 0 {
                        onBackToImage()
                    } else {
                        cancelPendingPick = true
                        onBackLine()
                    }
                }
                .opacity(pickedLine == nil ? 1 : 0.35)
                .disabled(pickedLine != nil)
                .position(x: isWide ? size.width * 0.93 : size.width * 0.91, y: isWide ? size.height * 0.12 : size.height * 0.09)

                HStack(alignment: .top, spacing: 26) {
                    VStack(alignment: .center, spacing: 18) {
                        VerticalText(PoemDateText.current.yearText, font: typeface.font(size: 20), spacing: 7)
                        VerticalText(PoemDateText.current.monthText, style: .accent, color: .cinnabar, spacing: 8)
                    }
                    VerticalText(mood.title, font: typeface.smallFont, color: .mutedInk, spacing: 7)
                }
                .opacity(0.78)
                .position(x: isWide ? size.width * 0.11 : size.width * 0.13, y: isWide ? size.height * 0.25 : size.height * 0.22)

                VStack(alignment: .trailing, spacing: 18) {
                    VerticalText(image.title, font: typeface.font(size: 19), spacing: 7)
                    Text("第\(lineIndex + 1)句".poemScript(script))
                        .font(typeface.smallFont)
                        .foregroundStyle(Color.cinnabar)
                }
                .position(x: isWide ? size.width * 0.88 : size.width * 0.86, y: isWide ? size.height * 0.30 : size.height * 0.29)

                VStack(spacing: 14) {
                    SmallCircleButton(title: "換") {
                        refreshCandidates()
                    }
                    .opacity(pickedLine == nil && !isLoadingCandidates ? 1 : 0.35)
                    .disabled(pickedLine != nil || isLoadingCandidates)

                    SmallCircleButton(title: "書") {
                        selfWriteText = ""
                        showSelfWrite = true
                    }
                    .opacity(pickedLine == nil ? 1 : 0.35)
                    .disabled(pickedLine != nil)
                }
                .position(x: isWide ? size.width * 0.88 : size.width * 0.86, y: isWide ? size.height * 0.70 : size.height * 0.72)

                ZStack {
                    if isLoadingCandidates && candidateLines.isEmpty {
                        VerticalText("取句中", style: .small, color: .mutedInk, spacing: 6)
                            .opacity(0.7)
                            .transition(.opacity)
                    } else {
                        HStack(alignment: .top, spacing: candidateSpacing) {
                            let displayOptions = Array(options.reversed())
                            let guidedIndex = displayOptions.count > 1 ? 1 : 0
                            ForEach(Array(displayOptions.enumerated()), id: \.element) { index, line in
                                let isSpotlightTarget = spotlightGuide.step == .selectLine && index == guidedIndex
                                LineChoiceButton(
                                    line: line,
                                    isPicked: pickedLine == line,
                                    choicesVisible: choicesVisible,
                                    sealPulse: sealPulse,
                                    isSpotlightTarget: isSpotlightTarget,
                                    action: {
                                        if isSpotlightTarget {
                                            spotlightGuide.advance()
                                        }
                                        choose(line)
                                    }
                                )
                            }
                        }
                        .transition(.opacity.combined(with: .offset(y: 10)))
                    }
                }
                .frame(width: size.width * (isWide ? 0.52 : 0.70))
                .position(x: candidateCenterX, y: candidateCenterY)

                if !selectedLines.isEmpty {
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(Array(selectedLines.enumerated()).reversed(), id: \.offset) { _, line in
                            VerticalText(line, font: typeface.font(size: 13), color: .mutedInk.opacity(0.52), spacing: 6)
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .offset(y: -18)),
                                    removal: .opacity
                                ))
                        }
                    }
                    .position(x: previousCenterX, y: previousCenterY)
                    .animation(.easeOut(duration: 0.7), value: selectedLines)
                }
            }
            .frame(width: size.width, height: size.height)
        }
        .task(id: lineIndex) {
            resetCandidates()
            await loadCandidates(requestID: requestID)
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

    private func resetCandidates() {
        requestID = UUID()
        choicesVisible = false
        pickedLine = nil
        sealPulse = false
        cancelPendingPick = false
        candidateLines = []
        isLoadingCandidates = true
    }

    private func loadCandidates(requestID currentRequestID: UUID) async {
        let generated: [String]
        do {
            generated = try await BailianPoetryClient().generateCandidates(
                mood: mood,
                image: image,
                lineIndex: lineIndex,
                selectedLines: selectedLines,
                fallback: fallbackOptions,
                poemForm: poemForm,
                script: script
            )
        } catch {
            generated = fallbackOptions
        }

        guard currentRequestID == requestID else { return }

        candidateLines = generated.isEmpty ? fallbackOptions : generated
#if DEBUG
        print("Poetry candidates line \(lineIndex + 1): \(candidateLines)")
#endif
        isLoadingCandidates = false
        withAnimation(.easeOut(duration: 0.9).delay(0.12)) {
            choicesVisible = true
        }
    }

    private func refreshCandidates() {
        guard pickedLine == nil, !isLoadingCandidates else { return }
        SensoryFeedback.lightTap()
        refreshSeed += 1
        resetCandidates()
        Task {
            await loadCandidates(requestID: requestID)
        }
    }

    private func choose(_ line: String) {
        guard pickedLine == nil else { return }

        pickedLine = line
        choicesVisible = false
        SensoryFeedback.lightTap()
        prefetchNextCandidates(afterChoosing: line)

        withAnimation(.spring(response: 0.22, dampingFraction: 0.42)) {
            sealPulse = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            withAnimation(.spring(response: 0.26, dampingFraction: 0.55)) {
                sealPulse = false
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            guard !cancelPendingPick else { return }
            withAnimation(.easeInOut(duration: 0.45)) {
                onPick(line)
            }
        }
    }

    private func prefetchNextCandidates(afterChoosing line: String) {
        let nextLineIndex = lineIndex + 1
        guard nextLineIndex < poemForm.lineCount else { return }

        let nextSelectedLines = selectedLines + [line]
        let nextFallback = PoetrySeed.lines(for: mood, image: image, form: poemForm, index: nextLineIndex)
            .map { $0.poemScript(script) }

        Task {
            _ = try? await BailianPoetryClient().generateCandidates(
                mood: mood,
                image: image,
                lineIndex: nextLineIndex,
                selectedLines: nextSelectedLines,
                fallback: nextFallback,
                poemForm: poemForm,
                script: script
            )
        }
    }
}

private struct SelfWriteSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.poemTypeface) private var typeface
    @Environment(\.poemScript) private var script
    let charCount: Int
    let lineIndex: Int
    @Binding var text: String
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
        case 0: return "取景，先立意象"
        case 1: return "入情，把景转为心事"
        case 2: return "转折，让情绪有微妙变化"
        default: return "收束，留下余味"
        }
    }

    var body: some View {
        ZStack {
            PaperBackground()

            VStack(spacing: 0) {
                // Header
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("自書第\(lineIndex + 1)句".poemScript(script))
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
                            Text(char)
                                .font(typeface.font(size: fontSize))
                                .foregroundStyle(Color.ink)
                                .frame(width: boxSize, height: boxSize)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(
                                            i < cleanText.count ? Color.cinnabar.opacity(0.5) : Color.mutedInk.opacity(0.2),
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
                        Text("落筆".poemScript(script))
                            .font(typeface.sealFont)
                            .foregroundStyle(.white)
                            .frame(width: 60, height: 60)
                            .background(Circle().fill(isValid ? Color.cinnabar : Color.mutedInk.opacity(0.3)))
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

private struct LineChoiceButton: View {
    let line: String
    let isPicked: Bool
    let choicesVisible: Bool
    let sealPulse: Bool
    var isSpotlightTarget: Bool = false
    let action: () -> Void

    private var isVisible: Bool {
        choicesVisible || isPicked
    }

    var body: some View {
        Button(action: action) {
            VerticalText(line, style: .body, color: isPicked ? .white : .ink)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isPicked ? Color.cinnabar : Color.clear)
                }
                .opacity(isVisible ? (isPicked ? 1 : 0.86) : 0)
                .offset(y: choicesVisible || isPicked ? 0 : 16)
                .blur(radius: isVisible ? 0 : 2)
                .scaleEffect(sealPulse ? 1.04 : 1)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isPicked)
        .spotlightTarget(.selectLine, active: isSpotlightTarget && isVisible, offset: CGSize(width: 0, height: 10))
        .animation(.easeOut(duration: 0.75), value: choicesVisible)
        .animation(.spring(response: 0.25, dampingFraction: 0.55), value: isPicked)
    }
}

private struct TypewriterLine: View {
    @Environment(\.poemTypeface) private var typeface
    @Environment(\.poemScript) private var script
    let text: String
    let visibleCount: Int
    var fontSize: CGFloat = PoemTypeface.bodyFontSize
    var spacing: CGFloat = 6

    var body: some View {
        let chars = Array(text.poemScript(script).enumerated())
        VStack(spacing: spacing) {
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
    let line: String
    var fontSize: CGFloat = PoemTypeface.bodyFontSize
    var spacing: CGFloat = 6
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                VerticalText(line, font: typeface.font(size: fontSize), spacing: spacing)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 5)
                    .background {
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(Color.cinnabar.opacity(0.32), lineWidth: 0.8)
                    }

                Text("改".poemScript(script))
                    .font(typeface.tinySealFont)
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.cinnabar))
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
    let mood: MoodSeed
    let image: ImageSeed
    let lines: [String]
    let onReviseLine: (Int) -> Void
    let onSave: (SavedPoem) -> Void
    let onRestart: () -> Void
    @State private var revealedChars = 0
    @State private var showSeal = false
    @State private var showActions = false
    @State private var isRevisingPoem = false
    @State private var isSaved = false
    @State private var showsSharePreview = false

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

    private var poemLineSpacing: CGFloat {
        lines.count > 4 ? 14 : 22
    }

    private var poemCharacterSpacing: CGFloat {
        lines.count > 4 ? 5 : 7
    }

    private var poemFontSize: CGFloat {
        lines.count > 4 ? 16 : 18.5
    }

    private var titleFontSize: CGFloat {
        lines.count > 4 ? 13.5 : 14.5
    }

    var body: some View {
        VStack {
            HStack(alignment: .top) {
                VStack {
                    Spacer()
                    if allRevealed {
                        PoemInscriptionView(locationMark: locationMark)
                            .transition(.opacity.combined(with: .offset(y: 8)))
                            .padding(.bottom, showSeal && !sealName.isEmpty ? 16 : 60)
                    }
                    if showSeal && !sealName.isEmpty {
                        SealStampView(name: sealName, size: 44)
                            .transition(.opacity.combined(with: .scale(scale: 0.7)))
                            .padding(.bottom, 60)
                    }
                }
                .padding(.leading, 28)

                Spacer()

                HStack(alignment: .top, spacing: poemLineSpacing) {
                    ForEach(Array(lines.enumerated()).reversed(), id: \.offset) { index, line in
                        let count = charsForLine(index)
                        if isRevisingPoem {
                            RevisionLineButton(
                                line: line,
                                fontSize: poemFontSize,
                                spacing: poemCharacterSpacing,
                                action: { onReviseLine(index) }
                            )
                                .transition(.opacity)
                        } else if count > 0 {
                            TypewriterLine(
                                text: line,
                                visibleCount: count,
                                fontSize: poemFontSize,
                                spacing: poemCharacterSpacing
                            )
                                .transition(.opacity)
                        }
                    }
                    VerticalText(image.title, font: typeface.font(size: titleFontSize), color: .mutedInk, spacing: 6)
                        .padding(.leading, 12)
                }
                .padding(.top, 78)
                .padding(.trailing, 34)
            }

            Spacer()

            if showActions {
                VStack(spacing: 16) {
                    if isRevisingPoem {
                        Text("點一句重寫".poemScript(script))
                            .font(.system(size: 12))
                            .foregroundStyle(Color.mutedInk.opacity(0.72))
                            .transition(.opacity.combined(with: .offset(y: 6)))
                    }

	                    HStack(spacing: 30) {
	                        SealButton(
                                title: "分享",
                                isSelected: true,
                                spotlightStep: .tapShare,
                                action: { showsSharePreview = true }
                            )
		                        SealButton(
                                title: "首页",
                                isSelected: true,
                                spotlightStep: .returnHome,
                                advancesSpotlightAutomatically: false,
                                action: onRestart
                            )
	                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }
            Spacer().frame(height: showActions ? 0 : 38)
        }
        .padding(.bottom, 50)
        .animation(.easeOut(duration: 0.3), value: revealedChars)
        .animation(.easeOut(duration: 0.6), value: showSeal)
        .animation(.easeOut(duration: 0.45), value: showActions)
        .animation(.easeOut(duration: 0.5), value: locationProvider.inscriptionPlace)
        .task(id: lines.joined(separator: "|")) {
            await revealPoem()
        }
        .fullScreenCover(isPresented: $showsSharePreview) {
            PoemSharePreviewView(
                imageTitle: image.title,
                lines: lines,
                locationMark: locationMark,
                lunarDateText: PoemInscriptionDate.current.lunarDateText,
                dayPeriodText: PoemInscriptionDate.current.dayPeriodText
            )
        }
        .spotlightOverlay(for: [.tapShare, .returnHome])
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
            dayPeriodText: inscriptionDate.dayPeriodText
        )

        onSave(poem)
        isSaved = true
    }
}

private struct PoemInscriptionView: View {
    let locationMark: String?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VerticalText(PoemInscriptionDate.current.lunarDateText, style: .tinySeal, color: .mutedInk, spacing: 5)
            if let locationMark {
                VerticalText(compactInscriptionText(locationMark), style: .tinySeal, color: .mutedInk, spacing: 6)
            }
        }
    }
}

enum ShareArtworkLayout: String, CaseIterable, Identifiable, Hashable {
    case portrait
    case landscape

    var id: String { rawValue }

    var label: String {
        switch self {
        case .portrait: return "豎版"
        case .landscape: return "橫版"
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

private struct PoemSharePreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.poemTypeface) private var typeface
    @Environment(\.poemScript) private var script
    @Environment(\.spotlightGuide) private var spotlightGuide
    @AppStorage(SealStampView.storageKey) private var sealName = ""
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
                    Text("分享".poemScript(script))
                        .font(typeface.titleFont)
                        .foregroundStyle(Color.ink)
                    Spacer()
                    QuietBackButton(title: "返回") { dismiss() }
                }
                .padding(.horizontal, 30)
                .padding(.top, 56)
                .padding(.bottom, 18)

                ShareSurfacePicker(selectedBgRaw: $selectedBgRaw)
                    .padding(.bottom, 14)

                ScrollView {
                    VStack(spacing: 28) {
                        ForEach(layouts) { layout in
                            let key = "\(layout.rawValue)-\(selectedBgRaw)"
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
        .task(id: selectedBgRaw) {
            await renderShareImages()
        }
        .spotlightOverlay(for: [.selectBackground, .tapShareButton, .returnFromShare])
    }

    @MainActor
    private func renderShareImages() async {
        for layout in layouts {
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

        let key = "\(layout.rawValue)-\(selectedBgRaw)"
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
    @Binding var selectedBgRaw: String

    private var isShadowSelected: Bool {
        let background = PoemBackground(rawValue: selectedBgRaw)
        return background == PoemBackground.none || background == nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("紙面".poemScript(script))
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
                                        Text("擇".poemScript(script))
                                            .font(typeface.tinySealFont)
                                            .foregroundStyle(.white)
                                            .frame(width: 18, height: 18)
                                            .background(Circle().fill(Color.cinnabar))
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
	                        let isSpotlightTarget = spotlightGuide.step == .selectBackground && bg == PoemBackground.imageBackgrounds.first
                        Button {
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
                                        Text("擇".poemScript(script))
                                            .font(typeface.tinySealFont)
                                            .foregroundStyle(.white)
                                            .frame(width: 18, height: 18)
                                            .background(Circle().fill(Color.cinnabar))
                                            .offset(x: 5, y: 5)
                                            .transition(.scale(scale: 0.75).combined(with: .opacity))
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
        }
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
                        Text("享".poemScript(script))
                            .font(typeface.sealFont)
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(Color.cinnabar))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                        .spotlightTarget(.tapShareButton, active: isSpotlightTarget)
                } else {
                    Text("備".poemScript(script))
                        .font(typeface.sealFont)
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
    @Environment(\.poemTypeface) private var typeface
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

            switch layout {
            case .portrait:
                portraitBody
            case .landscape:
                landscapeBody
            }
        }
    }

    private var portraitBody: some View {
        HStack(alignment: .top) {
            VStack {
                Spacer()
                inscription
                    .padding(.bottom, showsSeal && !sealName.isEmpty ? 42 : 126)
                if showsSeal && !sealName.isEmpty {
                    SealStampView(name: sealName, size: 118)
                        .padding(.bottom, 126)
                }
            }
            .padding(.leading, 88)

            Spacer()

            HStack(alignment: .top, spacing: poemLineSpacing) {
                ForEach(Array(lines.enumerated()).reversed(), id: \.offset) { _, line in
                    VerticalText(line, font: typeface.font(size: poemFontSize), spacing: poemCharacterSpacing)
                }
                if showsTitle {
                    VerticalText(imageTitle, font: typeface.titleFont, color: .mutedInk, spacing: 18)
                        .padding(.leading, 28)
                }
            }
            .padding(.top, 170)
            .padding(.trailing, 110)
        }
    }

    private var landscapeBody: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 44) {
                inscription
                if showsSeal && !sealName.isEmpty {
                    SealStampView(name: sealName, size: 104)
                }
                Spacer()
            }
            .padding(.leading, 110)
            .padding(.top, 142)
            .padding(.bottom, 120)

            Spacer()

            HStack(alignment: .top, spacing: lines.count > 4 ? 34 : 54) {
                ForEach(Array(lines.enumerated()).reversed(), id: \.offset) { _, line in
                    VerticalText(line, font: typeface.font(size: lines.count > 4 ? 38 : 52), spacing: lines.count > 4 ? 13 : 18)
                }
                if showsTitle {
                    VerticalText(imageTitle, font: typeface.titleFont, color: .mutedInk, spacing: 16)
                        .padding(.leading, 20)
                }
            }
            .padding(.top, 130)
            .padding(.trailing, 120)
        }
    }

    private var inscription: some View {
        HStack(alignment: .top, spacing: 14) {
            VerticalText(lunarDateText, font: typeface.font(size: 31), color: .mutedInk, spacing: 12)
            if let locationMark {
                VerticalText(compactInscriptionText(locationMark), font: typeface.font(size: 31), color: .mutedInk, spacing: 14)
            }
        }
    }
}

struct SavedPoem: Codable, Identifiable, Equatable {
    let id: UUID
    let createdAt: Date
    let moodTitle: String
    let imageTitle: String
    let lines: [String]
    let locationText: String?
    let lunarDateText: String
    let dayPeriodText: String

    init(
        id: UUID = UUID(),
        createdAt: Date,
        moodTitle: String,
        imageTitle: String,
        lines: [String],
        locationText: String?,
        lunarDateText: String,
        dayPeriodText: String
    ) {
        self.id = id
        self.createdAt = createdAt
        self.moodTitle = moodTitle
        self.imageTitle = imageTitle
        self.lines = lines
        self.locationText = locationText
        self.lunarDateText = lunarDateText
        self.dayPeriodText = dayPeriodText
    }
}

private enum PoemArchiveStore {
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

private struct PoemArchiveView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.poemTypeface) private var typeface
    @Environment(\.poemScript) private var script
    @Environment(\.spotlightGuide) private var spotlightGuide
    @Binding var poems: [SavedPoem]
    @State private var poemPendingDeletion: SavedPoem?

    var body: some View {
        NavigationStack {
            ZStack {
                PaperBackground()

                VStack(spacing: 0) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("藏詩".poemScript(script))
                                .font(typeface.titleFont)
                                .foregroundStyle(Color.ink)

                            if !poems.isEmpty {
                                Text("\(poems.count)首".poemScript(script))
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.mutedInk.opacity(0.72))
                            }
                        }
                        Spacer()
                        QuietBackButton(title: "返回") { dismiss() }
                    }
                    .padding(.horizontal, 30)
                    .padding(.top, 56)
                    .padding(.bottom, 22)

                    if poems.isEmpty {
                        Spacer()
                        VerticalText("尚無藏詩".poemScript(script), style: .small, color: .mutedInk, spacing: 7)
                        Spacer()
                    } else {
                        ScrollView(.vertical, showsIndicators: false) {
	                            LazyVStack(spacing: 14) {
	                                ForEach(Array(poems.enumerated()), id: \.element.id) { index, poem in
                                            let isSpotlightTarget = spotlightGuide.step == .openHistoryPoem && index == 0
	                                    HStack(spacing: 10) {
	                                        NavigationLink {
	                                            SavedPoemDetailView(poem: poem)
	                                        } label: {
	                                            SavedPoemListRow(poem: poem)
	                                        }
	                                        .buttonStyle(.plain)
	                                        .frame(maxWidth: .infinity)
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
	                                            Text("刪".poemScript(script))
	                                                .font(typeface.tinySealFont)
	                                                .foregroundStyle(Color.cinnabar)
	                                                .frame(width: 34, height: 34)
	                                                .background {
	                                                    Circle()
	                                                        .stroke(Color.cinnabar.opacity(0.68), lineWidth: 0.9)
	                                                }
	                                        }
	                                        .buttonStyle(.plain)
	                                    }
	                                    .transition(.opacity.combined(with: .offset(y: 8)))
	                                }
	                            }
                            .padding(.horizontal, 30)
                            .padding(.bottom, 50)
                        }
                    }
                }
            }
            .navigationBarHidden(true)
            .spotlightOverlay(for: [.openHistoryPoem])
            .alert(
                "確定刪除此詩？".poemScript(script),
                isPresented: Binding(
                    get: { poemPendingDeletion != nil },
                    set: { isPresented in
                        if !isPresented {
                            poemPendingDeletion = nil
                        }
                    }
                ),
            ) {
                Button("取消".poemScript(script), role: .cancel) {
                    poemPendingDeletion = nil
                }

                Button("刪除".poemScript(script), role: .destructive) {
                    if let poem = poemPendingDeletion {
                        delete(poem)
                    }
                    poemPendingDeletion = nil
                }
            } message: {
                Text("刪除後不可恢復".poemScript(script))
            }
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

            VerticalText("閱".poemScript(script), style: .tinySeal, color: .cinnabar.opacity(0.86), spacing: 4)
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

    private static func createdAtText(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "yyyy年M月d日 HH:mm"
        return formatter.string(from: date)
    }
}

private struct SavedPoemDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.poemTypeface) private var typeface
    @Environment(\.poemScript) private var script
    @AppStorage(SealStampView.storageKey) private var sealName = ""
    let poem: SavedPoem
    @State private var showsSharePreview = false

    private var poemLineSpacing: CGFloat {
        poem.lines.count > 4 ? 14 : 22
    }

    private var poemCharacterSpacing: CGFloat {
        poem.lines.count > 4 ? 5 : 7
    }

    private var poemFontSize: CGFloat {
        poem.lines.count > 4 ? 16 : 18.5
    }

    private var titleFontSize: CGFloat {
        poem.lines.count > 4 ? 13.5 : 14.5
    }

    var body: some View {
        ZStack {
            PaperBackground()

            VStack(spacing: 0) {
                HStack(alignment: .top) {
                    Spacer()

                    QuietBackButton(title: "分享") {
                        showsSharePreview = true
                    }

                    QuietBackButton(title: "返回") {
                        dismiss()
                    }
                }
                .padding(.horizontal, 30)
                .padding(.top, 56)

                HStack(alignment: .top) {
                    VStack {
                        Spacer()
                        HStack(alignment: .top, spacing: 10) {
                            VerticalText(poem.lunarDateText, style: .tinySeal, color: .mutedInk, spacing: 5)
                            if let locationText = poem.locationText {
                                VerticalText(compactInscriptionText(locationText), style: .tinySeal, color: .mutedInk, spacing: 6)
                            }
                        }
                        .padding(.bottom, !sealName.isEmpty ? 16 : 60)

                        if !sealName.isEmpty {
                            SealStampView(name: sealName, size: 44)
                                .padding(.bottom, 60)
                        }
                    }
                    .padding(.leading, 28)

                    Spacer()

                    HStack(alignment: .top, spacing: poemLineSpacing) {
                        ForEach(Array(poem.lines.enumerated()).reversed(), id: \.offset) { _, line in
                            VerticalText(
                                line,
                                font: typeface.font(size: poemFontSize),
                                spacing: poemCharacterSpacing
                            )
                        }
                        VerticalText(poem.imageTitle, font: typeface.font(size: titleFontSize), color: .mutedInk, spacing: 6)
                            .padding(.leading, 12)
                    }
                    .padding(.top, 58)
                    .padding(.trailing, 34)
                }

                Spacer()
            }
        }
        .navigationBarHidden(true)
        .fullScreenCover(isPresented: $showsSharePreview) {
            PoemSharePreviewView(
                imageTitle: poem.imageTitle,
                lines: poem.lines,
                locationMark: poem.locationText,
                lunarDateText: poem.lunarDateText,
                dayPeriodText: poem.dayPeriodText
            )
        }
    }
}

enum SealStampStyle: String, CaseIterable, Identifiable {
    static let storageKey = "sealStyle"

    case zhuwen
    case baiwen

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .zhuwen:
            return "朱文"
        case .baiwen:
            return "白文"
        }
    }
}

private struct SealStampView: View {
    static let storageKey = "sealName"

    @AppStorage(SealStampStyle.storageKey) private var storedStyleRawValue = SealStampStyle.zhuwen.rawValue

    let name: String
    var style: SealStampStyle? = nil
    let size: CGFloat

    private var resolvedStyle: SealStampStyle {
        style ?? SealStampStyle(rawValue: storedStyleRawValue) ?? .zhuwen
    }

    private var sealChars: [String] {
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
        VStack(spacing: spacing) {
            ForEach(Array(convertedText.enumerated()), id: \.offset) { _, character in
                Text(String(character))
                    .font(font ?? typeface.font(for: style ?? .body))
                    .foregroundStyle(color)
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
                .font(typeface.font(size: 17))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.cinnabar))
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

private struct PaperBackground: View {
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
}

private enum PoemFontStyle {
    case title
    case body
    case small
    case accent
    case seal
    case tinySeal
}

protocol PoemFormOption: RawRepresentable, CaseIterable, Identifiable where RawValue == String, AllCases: RandomAccessCollection {
    var displayName: String { get }
}

enum PoemStructure: String, PoemFormOption {
    static let storageKey = "poemStructure"

    case jueju
    case lushi

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .jueju:
            return "絕句"
        case .lushi:
            return "律詩"
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

enum PoemMeter: String, PoemFormOption {
    static let storageKey = "poemMeter"

    case five
    case seven

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .five:
            return "五言"
        case .seven:
            return "七言"
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
    var displayName: String { "\(meter.displayName)\(structure.displayName)" }

    func role(for lineIndex: Int) -> String {
        if structure == .jueju {
            switch lineIndex {
            case 0:
                return "第一句：取景，先立意象"
            case 1:
                return "第二句：入情，把景转为心事"
            case 2:
                return "第三句：转折，让情绪有微妙变化"
            default:
                return "第四句：收束，留下余味"
            }
        }

        switch lineIndex {
        case 0:
            return "第一句：起，先立意象"
        case 1:
            return "第二句：承，补足景与情"
        case 2, 3:
            return "颔联：展开景物与心事，略有对仗感"
        case 4, 5:
            return "颈联：转入深一层情绪，略有对仗感"
        case 6:
            return "第七句：准备收束"
        default:
            return "第八句：收束全诗，留下余味"
        }
    }
}

enum PoemScript: String, CaseIterable, Identifiable {
    static let storageKey = "poemScript"

    case traditional
    case simplified

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .traditional:
            return "繁體"
        case .simplified:
            return "简体"
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

private struct PoemTypefaceKey: EnvironmentKey {
    static let defaultValue = PoemTypeface.kaiti
}

private extension EnvironmentValues {
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

private enum PoemTypeface: String, CaseIterable, Identifiable {
    static let storageKey = "poemTypeface"
    static let bodyFontSize: CGFloat = 17

    case kaiti
    case wenyue
    case wenkai
    case songti
    case mashan
    case xiaozhuan

    var id: String { rawValue }

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

struct MoodSeed: Identifiable, Equatable {
    let id: String
    let title: String
    let tags: [String]

    init(id: String, title: String) {
        self.id = id
        self.title = title
        self.tags = [title]
    }

    init(tags: [String]) {
        let cleanTags = tags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let title = cleanTags.isEmpty ? "未名" : cleanTags.joined(separator: "·")
        self.id = cleanTags.isEmpty ? "custom-empty" : "tags-\(cleanTags.joined(separator: "-"))"
        self.title = title
        self.tags = cleanTags
    }
}

struct ImageSeed: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
}

enum PoetrySeed {
    private static var rotatingIndex = 0


    static let moods = [
        MoodSeed(id: "miss", title: "思"),
        MoodSeed(id: "part", title: "別"),
        MoodSeed(id: "quiet", title: "寂"),
        MoodSeed(id: "relief", title: "釋")
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

    static func lines(for mood: MoodSeed, image: ImageSeed, form: PoemFormSpec, index: Int) -> [String] {
        let sevenDefault: [[String]] = [
            ["临窗独坐明月光", "夜深忽忆去年时", "风过空庭花影迟"],
            ["一纸相思未敢题", "故人消息隔天涯", "半生心事入寒窗"],
            ["欲问平安终又止", "偏是无眠人易老", "忽忆当年花下语"],
            ["只教明月替相思", "从此清风不寄谁", "不惊旧梦不惊枝"],
            ["薄雾初开人未语", "小楼风定酒微温", "灯前旧字忽成灰"],
            ["半窗花影随身瘦", "一径苔痕到梦深", "此心不肯付流云"],
            ["回首人间多聚散", "欲将心事托寒星", "忽听归雁过前汀"],
            ["明朝仍有好风来", "且把余情付晚钟", "一庭月色照归人"]
        ]

        let sevenParting: [[String]] = [
            ["长亭草色又逢春", "渡口斜阳照别身", "春雨无声湿旧尘"],
            ["一程山水一程人", "回首烟波不见君", "落花吹满去年门"],
            ["欲把离愁藏袖底", "忽闻归雁过江津", "此后相逢应有期"],
            ["愿君前路有晴云", "莫向天涯问旧痕", "各自人间各自春"],
            ["远树含烟遮旧渡", "孤帆带雨入寒津", "客路逢春春更晚"],
            ["江声不管离人意", "柳色偏牵昨日心", "一笛斜阳吹未尽"],
            ["他年若问归来处", "应记今宵月满身", "别后山河各自深"],
            ["愿从云外寄平安", "莫将清泪湿征衫", "天涯回首有春山"]
        ]

        let sevenQuiet: [[String]] = [
            ["孤灯照我到三更", "微雪无声落空庭", "旧城风起夜初沉"],
            ["万籁归来心未平", "半窗月色冷如冰", "一盏清茶坐到明"],
            ["不知梦去何方宿", "偶有钟声穿薄雾", "尘世喧哗隔一城"],
            ["且听风声过短檐", "只留清影在衣襟", "明朝醒处是新晴"],
            ["深巷无人灯自白", "残书有味夜偏长", "檐花滴破三更梦"],
            ["一榻清寒容我坐", "半生尘事向谁明", "月在窗前人不语"],
            ["忽有微风翻旧页", "暗香轻过小帘栊", "此身暂与夜同清"],
            ["天明仍是寻常日", "且把孤心寄晓钟", "雪后空庭见月生"]
        ]

        let sevenRelief: [[String]] = [
            ["流云出岫不知愁", "春水无声自向东", "竹影扫阶尘渐空"],
            ["旧事随风过小楼", "一身轻似晚来风", "心上青山月正中"],
            ["回看人间多聚散", "从今不问归何处", "万般滋味入茶中"],
            ["且把余生付远游", "花开花落两从容", "清风明月与人同"],
            ["雨后青山如洗过", "闲云不系旧时愁", "小径无人花自落"],
            ["一念放开天地阔", "半窗风月入怀清", "从此眉间少旧尘"],
            ["人间得失皆流水", "杯底浮沉看晚晴", "回身已是万山轻"],
            ["明日春风仍到门", "且留新梦在松阴", "心随白鹭过前溪"]
        ]

        let fiveDefault: [[String]] = [
            ["临窗看月", "夜深忆旧", "风过空庭"],
            ["相思未题", "故人天涯", "心事寒窗"],
            ["欲问还止", "无眠易老", "忽忆花前"],
            ["明月替思", "清风不寄", "旧梦不惊"],
            ["薄雾初开", "小楼风定", "灯前字冷"],
            ["花影随身", "苔痕入梦", "心付流云"],
            ["回首聚散", "心托寒星", "归雁过汀"],
            ["好风仍来", "余情付钟", "月照归人"]
        ]

        let fiveParting: [[String]] = [
            ["长亭又春", "渡口斜阳", "春雨湿尘"],
            ["山水一程", "烟波无君", "落花满门"],
            ["离愁藏袖", "归雁过津", "相逢有期"],
            ["前路晴云", "天涯旧痕", "人间各春"],
            ["远树含烟", "孤帆带雨", "客路春晚"],
            ["江声不管", "柳色牵心", "斜阳笛尽"],
            ["他年归处", "今宵月满", "山河各深"],
            ["云外平安", "清泪勿湿", "回首春山"]
        ]

        let fiveQuiet: [[String]] = [
            ["孤灯三更", "微雪空庭", "旧城夜沉"],
            ["万籁心平", "月色如冰", "清茶到明"],
            ["梦去何方", "钟声穿雾", "尘世隔城"],
            ["风过短檐", "清影衣襟", "醒处新晴"],
            ["深巷灯白", "残书夜长", "檐花破梦"],
            ["清寒容坐", "尘事谁明", "月前不语"],
            ["微风翻页", "暗香过帘", "此身同清"],
            ["天明如常", "孤心寄钟", "雪后月生"]
        ]

        let fiveRelief: [[String]] = [
            ["流云出岫", "春水向东", "竹影扫尘"],
            ["旧事随风", "身似晚风", "心有青山"],
            ["回看聚散", "不问归处", "滋味入茶"],
            ["余生远游", "花落从容", "明月同人"],
            ["雨后青山", "闲云无愁", "小径花落"],
            ["一念天地", "风月入怀", "眉间少尘"],
            ["得失流水", "杯底晚晴", "回身山轻"],
            ["春风到门", "新梦松阴", "心随白鹭"]
        ]

        let table: [[String]]
        switch (mood.id, form.meter) {
        case ("part", .five):
            table = fiveParting
        case ("quiet", .five):
            table = fiveQuiet
        case ("relief", .five):
            table = fiveRelief
        case (_, .five):
            table = fiveDefault
        case ("part", .seven):
            table = sevenParting
        case ("quiet", .seven):
            table = sevenQuiet
        case ("relief", .seven):
            table = sevenRelief
        default:
            table = sevenDefault
        }

        return table[index % table.count]
    }
}

// MARK: - Three-level mood selection data

private enum MoodLevels {
    private static var level2Rotation: [String: Int] = [:]
    private static var level3Rotation: [String: Int] = [:]

    /// Level 1: the four root emotions
    static let level1 = ["喜", "怒", "哀", "乐"]

    static func level2Label(for l1: String) -> String {
        switch l1 {
        case "喜":
            return "何事可喜"
        case "怒":
            return "因何不平"
        case "哀":
            return "何事牽掛"
        case "乐":
            return "何事成樂"
        default:
            return "何事在心"
        }
    }

    /// Level 2: each root branches into broad real-life situations.
    static func level2(for l1: String) -> [String] {
        level2Groups(for: l1).first ?? []
    }

    static func rotatingLevel2(for l1: String) -> [String] {
        let groups = level2Groups(for: l1)
        guard !groups.isEmpty else { return [] }
        let nextIndex = ((level2Rotation[l1] ?? 0) + 1) % groups.count
        level2Rotation[l1] = nextIndex
        return groups[nextIndex]
    }

    private static func level2Groups(for l1: String) -> [[String]] {
        switch l1 {
        case "喜":
            return [
                ["得償所願", "久別重逢", "小有成就", "暗自歡喜", "喜從天降", "心願初成", "良人相伴", "春風得意"],
                ["升職加薪", "考試過關", "新居初定", "旅途將啟", "朋友相聚", "家人安好", "被人記得", "驚喜忽至"]
            ]
        case "怒":
            return [
                ["事與願違", "被人辜負", "職場不平", "言語相傷", "等待太久", "受了委屈", "界線被犯", "反覆內耗"],
                ["努力無果", "誤會難平", "失約失信", "不被看見", "世事荒唐", "心有不甘", "舊怨未消", "忍無可忍"]
            ]
        case "哀":
            return [
                ["久別難逢", "思念成疾", "舊夢重來", "孤身一人", "愛而不得", "故人漸遠", "前路未明", "夜深難眠"],
                ["親友遠行", "離職告別", "城市陌生", "生日無人", "回憶太重", "錯過良辰", "心事無言", "人海失聯"]
            ]
        case "乐":
            return [
                ["工作順遂", "閒居有味", "愛情正好", "朋友相聚", "小事如願", "身心鬆弛", "旅途開闊", "雨過天晴"],
                ["飯後散步", "週末無事", "新茶初沸", "日落可看", "貓狗相伴", "片刻自由", "家中有光", "清晨好夢"]
            ]
        default:
            return [["心有所感", "舊事入懷", "今朝有念", "一時難言", "人間小事", "身心微動", "夢醒之後", "風過心頭"]]
        }
    }

    /// Level 3: scene anchors, broad enough for work, life, love, city, and nature.
    static func level3(for l1: String, _ l2: String) -> [String] {
        level3Groups(for: l1, l2).first ?? []
    }

    static func rotatingLevel3(for l1: String, _ l2: String) -> [String] {
        let key = "\(l1)-\(l2)"
        let groups = level3Groups(for: l1, l2)
        guard !groups.isEmpty else { return [] }
        let nextIndex = ((level3Rotation[key] ?? 0) + 1) % groups.count
        level3Rotation[key] = nextIndex
        return groups[nextIndex]
    }

    private static func level3Groups(for l1: String, _ l2: String) -> [[String]] {
        let shared = [
            ["案前燈下", "通勤路上", "城市窗邊", "家中一隅", "人群之中", "雨後街口", "月照空庭", "山水之間"],
            ["辦公室裏", "地鐵車廂", "晚風橋畔", "餐桌之前", "手機屏前", "旅店窗前", "舊巷深處", "清晨陽台"]
        ]

        if l2.contains("愛") || l2.contains("良人") || l2.contains("重逢") || l2.contains("朋友") {
            return [
                ["並肩路上", "晚飯桌前", "月下街口", "舊地門前", "人群之中", "車站燈下", "花影窗邊", "河畔長椅"],
                ["相見途中", "長椅之側", "夜色街邊", "一盞燈前", "雨後街頭", "歸家路上", "影院門外", "橋邊風裏"]
            ]
        }

        if l2.contains("工作") || l2.contains("職") || l2.contains("考") || l2.contains("升") || l2.contains("努力") {
            return [
                ["案前燈下", "會議室外", "電梯門前", "深夜工位", "通勤路上", "咖啡杯旁", "文件堆裏", "城市窗邊"],
                ["屏幕之前", "地鐵車廂", "凌晨街口", "辦公室裏", "樓道風中", "工位桌前", "鍵盤聲旁", "工牌胸前"]
            ]
        }

        if l2.contains("家") || l2.contains("親") || l2.contains("生日") || l2.contains("安好") {
            return [
                ["家中一隅", "飯桌燈下", "舊屋門前", "陽台風裏", "廚房煙火", "電話那端", "童年巷口", "歸途車上"],
                ["窗簾之前", "客廳燈下", "樓下花影", "門鎖聲旁", "舊照之前", "被褥之間", "飯桌旁邊", "清晨屋內"]
            ]
        }

        return shared
    }
}

#Preview {
    PoemComposerView()
}
