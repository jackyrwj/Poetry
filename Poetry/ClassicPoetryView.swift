import SwiftUI

struct ClassicPoetryView: View {
    @AppStorage(PoemTypeface.storageKey) private var typefaceRawValue = PoemTypeface.kaiti.rawValue
    @AppStorage(PoemScript.storageKey) private var scriptRawValue = PoemScript.simplified.rawValue
    @State private var query = ""
    @State private var remotePoems: [ClassicPoem] = []
    @State private var favoriteIDs = ClassicPoemFavorites.load()
    @State private var selectedScope: PoetryScope = .featured
    @State private var showsSettings = false

    private var typeface: PoemTypeface {
        PoemTypeface(rawValue: typefaceRawValue) ?? .kaiti
    }

    private var script: PoemScript {
        PoemScript(rawValue: scriptRawValue) ?? .simplified
    }

    private var normalizedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var localPoems: [ClassicPoem] {
        switch selectedScope {
        case .featured:
            ClassicPoemLibrary.localSearch(normalizedQuery)
        case .tangShiThreeHundred:
            TangShiThreeHundredLibrary.search(normalizedQuery)
        case .songCiThreeHundred:
            SongCiThreeHundredLibrary.search(normalizedQuery)
        case .favorites:
            []
        }
    }

    private var displayedPoems: [ClassicPoem] {
        if selectedScope == .favorites {
            let cached = ClassicPoemFavorites.loadPoems().filter { poem in
                normalizedQuery.isEmpty || poem.searchableText.poemScript(.simplified)
                    .localizedCaseInsensitiveContains(normalizedQuery.poemScript(.simplified))
            }
            return cached.filter { favoriteIDs.contains($0.id) }
        }

        let localKeys = Set(localPoems.map {
            "\($0.title.poemScript(.simplified))|\($0.author.poemScript(.simplified))"
        })
        let combined = localPoems + remotePoems.filter {
            !localKeys.contains("\($0.title.poemScript(.simplified))|\($0.author.poemScript(.simplified))")
        }
        return combined
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PaperBackground()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        header
                        ClassicSearchField(text: $query)
                        if selectedScope != .favorites {
                            collectionPicker
                        }

                        resultsHeader

                        if displayedPoems.isEmpty {
                            emptyState
                        } else {
                            ForEach(displayedPoems) { poem in
                                NavigationLink(value: poem) {
                                    ClassicPoemCard(poem: poem, isFavorite: favoriteIDs.contains(poem.id))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 20)
                    .padding(.bottom, 36)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationBarHidden(true)
            .navigationDestination(for: ClassicPoem.self) { poem in
                ClassicPoemDetailView(poem: poem, favoriteIDs: $favoriteIDs)
            }
            .task(id: "\(normalizedQuery)|\(script.rawValue)|\(selectedScope.rawValue)") {
                await searchRemotely()
            }
            .sheet(isPresented: $showsSettings) {
                FontSettingsView()
            }
        }
        .environment(\.poemTypeface, typeface)
        .environment(\.poemScript, script)
        .tint(ClassicPalette.cinnabar)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 6) {
                Text((selectedScope == .favorites ? AppLanguage.copy("我的收藏", "Saved poems") : AppLanguage.copy("赏诗", "Read")).poemScript(script))
                    .font(typeface.font(size: 29))
                    .foregroundStyle(ClassicPalette.ink)
                Text((selectedScope == .favorites ? AppLanguage.copy("留住每一次心动", "Keep the poems that move you") : AppLanguage.copy("精选与唐诗三百首，离线可读", "Selected poems and Tang Poems Three Hundred, available offline")).poemScript(script))
                    .font(typeface.smallFont)
                    .foregroundStyle(ClassicPalette.mutedInk)
            }

            Spacer()

            SettingsButton {
                showsSettings = true
            }
        }
    }

    private var collectionPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ScopeButton(title: AppLanguage.copy("全部", "All"), selected: selectedScope == .featured) {
                    selectedScope = .featured
                }
                ScopeButton(title: AppLanguage.copy("唐诗", "Tang Poems"), selected: selectedScope == .tangShiThreeHundred) {
                    selectedScope = .tangShiThreeHundred
                }
                ScopeButton(title: AppLanguage.copy("宋词", "Song Lyrics"), selected: selectedScope == .songCiThreeHundred) {
                    selectedScope = .songCiThreeHundred
                }
            }
        }
    }

    private var resultsHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(resultsTitle.poemScript(script))
                .font(typeface.titleFont)
                .foregroundStyle(ClassicPalette.ink)
            Spacer()
            if selectedScope != .favorites && !displayedPoems.isEmpty {
                Text(AppLanguage.isEnglish ? "\(displayedPoems.count) poems" : "\(displayedPoems.count) 首")
                    .font(typeface.smallFont)
                    .foregroundStyle(ClassicPalette.mutedInk)
            }
        }
        .padding(.top, 4)
    }

    private var resultsTitle: String {
        if !normalizedQuery.isEmpty { return AppLanguage.copy("搜索结果", "Search results") }
        switch selectedScope {
        case .featured: return AppLanguage.copy("精选诗词", "Selected poems")
        case .tangShiThreeHundred: return TangShiThreeHundredLibrary.collectionTitle
        case .songCiThreeHundred: return SongCiThreeHundredLibrary.collectionTitle
        case .favorites: return AppLanguage.copy("我的收藏", "Saved poems")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: selectedScope == .favorites ? "bookmark" : "text.magnifyingglass")
                .font(.system(size: 28, weight: .light))
            Text((selectedScope == .favorites ? AppLanguage.copy("还没有收藏诗词", "No saved poems yet") : AppLanguage.copy("没有找到相关诗词", "No poems found")).poemScript(script))
                .font(typeface.bodyFont)
            Text((selectedScope == .favorites ? AppLanguage.copy("读诗时点一下书签，喜欢的作品会留在这里。", "Tap the bookmark while reading to save a poem here.") : AppLanguage.copy("可以换一个诗名、作者或原文关键词再试。", "Try a different title, author, or line from the original poem.")).poemScript(script))
                .font(typeface.smallFont)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(ClassicPalette.mutedInk)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 54)
    }

    private func searchRemotely() async {
        guard selectedScope == .featured else {
            remotePoems = []
            return
        }
        guard !normalizedQuery.isEmpty else {
            remotePoems = []
            return
        }
        guard normalizedQuery.count >= 3 else {
            remotePoems = []
            return
        }

        do {
            try await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            let results = try await ClassicPoetryClient().search(query: normalizedQuery, script: script)
            guard !Task.isCancelled else { return }
            remotePoems = results
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            remotePoems = []
        }
    }
}

/// A dedicated home for poems saved while reading. Its card grid intentionally
/// echoes the former archive, while poem detail keeps the same custom share flow.
struct SavedClassicPoemsView: View {
    @Environment(\.poemTypeface) private var typeface
    @Environment(\.poemScript) private var script
    @State private var favoriteIDs = ClassicPoemFavorites.load()
    @State private var poems = ClassicPoemFavorites.loadPoems()
    @State private var showsSettings = false

    private var savedPoems: [ClassicPoem] {
        poems.filter { favoriteIDs.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PaperBackground()

                VStack(spacing: 0) {
                    header

                    if savedPoems.isEmpty {
                        emptyState
                    } else {
                        ScrollView(.vertical, showsIndicators: false) {
                            LazyVGrid(
                                columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)],
                                spacing: 18
                            ) {
                                ForEach(savedPoems) { poem in
                                    NavigationLink {
                                        ClassicPoemDetailView(poem: poem, favoriteIDs: $favoriteIDs)
                                    } label: {
                                        SavedClassicPoemCard(poem: poem)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 24)
                            .padding(.bottom, 42)
                        }
                    }
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showsSettings) {
                FontSettingsView()
            }
        }
        .onAppear(perform: reloadSavedPoems)
        .environment(\.poemTypeface, typeface)
        .environment(\.poemScript, script)
        .tint(ClassicPalette.cinnabar)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 6) {
                Text(AppLanguage.copy("我的收藏", "Saved").poemScript(script))
                    .font(typeface.titleFont)
                    .foregroundStyle(ClassicPalette.ink)
                Text((savedPoems.isEmpty
                      ? AppLanguage.copy("留住每一次心动", "Keep the poems that move you")
                      : AppLanguage.copy("\\(savedPoems.count) 首诗词", "\\(savedPoems.count) saved poems")).poemScript(script))
                    .font(typeface.smallFont)
                    .foregroundStyle(ClassicPalette.mutedInk)
            }

            Spacer()

            SettingsButton {
                showsSettings = true
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 20)
        .padding(.bottom, 22)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bookmark")
                .font(.system(size: 28, weight: .light))
            Text(AppLanguage.copy("还没有收藏诗词", "No saved poems yet").poemScript(script))
                .font(typeface.bodyFont)
            Text(AppLanguage.copy("读诗时点一下书签，喜欢的作品会留在这里。", "Tap the bookmark while reading to save a poem here.").poemScript(script))
                .font(typeface.smallFont)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(ClassicPalette.mutedInk)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 40)
        .padding(.bottom, 80)
    }

    private func reloadSavedPoems() {
        favoriteIDs = ClassicPoemFavorites.load()
        poems = ClassicPoemFavorites.loadPoems()
    }
}

private struct SavedClassicPoemCard: View {
    @Environment(\.poemTypeface) private var typeface
    @Environment(\.poemScript) private var script
    let poem: ClassicPoem

    private var title: String {
        poem.localizedTitle.poemScript(script)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(poem.backgroundImageName)
                .resizable()
                .scaledToFill()
                .frame(height: 142)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(alignment: .bottom) {
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.36)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .overlay(alignment: .bottomLeading) {
                    Text(poem.title.poemScript(script))
                        .font(typeface.smallFont)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(10)
                }

            Text(title)
                .font(typeface.smallFont)
                .foregroundStyle(ClassicPalette.ink)
                .lineLimit(2)
                .frame(minHeight: 32, alignment: .topLeading)

            Text(poem.localizedAttribution.poemScript(script))
                .font(.system(size: 10, weight: .medium, design: .serif))
                .foregroundStyle(ClassicPalette.mutedInk.opacity(0.72))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private enum PoetryScope: String {
    case featured
    case tangShiThreeHundred
    case songCiThreeHundred
    case favorites

    var collectionTitle: String {
        switch self {
        case .tangShiThreeHundred: AppLanguage.copy(TangShiThreeHundredLibrary.collectionTitle, "Tang Poems")
        case .songCiThreeHundred: AppLanguage.copy(SongCiThreeHundredLibrary.collectionTitle, "Song Lyrics")
        case .featured: AppLanguage.copy("赏诗", "Read")
        case .favorites: AppLanguage.copy("我的收藏", "Saved poems")
        }
    }
}

private struct ClassicSearchField: View {
    @Environment(\.poemTypeface) private var typeface
    @Environment(\.poemScript) private var script
    @Binding var text: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(ClassicPalette.mutedInk.opacity(0.72))
            TextField(AppLanguage.copy("诗名、作者或诗句", "Chinese title, author, or line").poemScript(script), text: $text)
                .font(typeface.bodyFont)
                .foregroundStyle(ClassicPalette.ink)
                .focused($isFocused)
                .submitLabel(.search)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(ClassicPalette.mutedInk.opacity(0.55))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(AppLanguage.copy("清除搜索", "Clear search").poemScript(script))
            }
        }
        .padding(.horizontal, 15)
        .frame(height: 46)
        .background(.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(isFocused ? ClassicPalette.cinnabar.opacity(0.45) : .white.opacity(0.8), lineWidth: 1)
        }
    }
}

private struct ScopeButton: View {
    @Environment(\.poemTypeface) private var typeface
    @Environment(\.poemScript) private var script
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title.poemScript(script))
                .font(typeface.smallFont)
                .foregroundStyle(selected ? .white : ClassicPalette.mutedInk)
                .padding(.horizontal, 16)
                .frame(height: 34)
                .background(selected ? ClassicPalette.cinnabar : .white.opacity(0.68), in: Capsule())
                .overlay {
                    if !selected {
                        Capsule().stroke(ClassicPalette.mutedInk.opacity(0.16), lineWidth: 0.8)
                    }
                }
        }
        .buttonStyle(.plain)
    }
}

struct ClassicPoemCard: View {
    @Environment(\.poemTypeface) private var typeface
    @Environment(\.poemScript) private var script
    let poem: ClassicPoem
    let isFavorite: Bool

    /// In English the card leads with the translated title and keeps the
    /// original beside it; in Chinese only the original is shown.
    private var cardTitle: String {
        guard let englishTitle = poem.englishTitle else {
            return poem.localizedTitle.poemScript(script)
        }
        return "\(englishTitle.poemScript(script))（\(poem.title.poemScript(script))）"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(poem.backgroundImageName)
                .resizable()
                .scaledToFill()
                .frame(width: 82, height: 108)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(cardTitle)
                        .font(typeface.font(size: 19))
                        .foregroundStyle(ClassicPalette.ink)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    if isFavorite {
                        Image(systemName: "bookmark.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(ClassicPalette.cinnabar)
                    }
                }

                Text(poem.localizedAttribution.poemScript(script))
                    .font(typeface.smallFont)
                    .foregroundStyle(ClassicPalette.mutedInk)
                    .lineLimit(1)

                Text(poem.lines.prefix(2).joined(separator: "\n").poemScript(script))
                    .font(typeface.smallFont)
                    .foregroundStyle(ClassicPalette.ink.opacity(0.84))
                    .lineSpacing(4)
                    .lineLimit(2)
            }
            .padding(.vertical, 3)
        }
        .padding(12)
        .background(.white.opacity(0.76), in: RoundedRectangle(cornerRadius: 19, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .stroke(.white.opacity(0.72), lineWidth: 0.8)
        }
    }
}

struct ClassicPoemDetailView: View {
    @Environment(\.poemTypeface) private var typeface
    @Environment(\.poemScript) private var script
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var musicPlayer: PoemMusicPlayer
    let poem: ClassicPoem
    @Binding var favoriteIDs: Set<String>
    @State private var aiAppreciation: String?
    @State private var isGenerating = false
    @State private var generationError: String?
    @State private var showsShare = false
    @State private var showsMusicCredits = false
    @State private var paywallReason: PaywallReason?
    @ObservedObject private var store = StoreManager.shared

    private var isFavorite: Bool { favoriteIDs.contains(poem.id) }
    private var hasPremiumAccess: Bool { store.isPremium }
    private var displayedAppreciation: String? { poem.localizedAppreciation ?? aiAppreciation }
    private var hasBundledAppreciation: Bool { poem.localizedAppreciation != nil }
    private var readingLines: [String] {
        poem.lines.flatMap(Self.splitAtSentenceEndings)
    }

    private static func splitAtSentenceEndings(_ line: String) -> [String] {
        var lines: [String] = []
        var currentLine = ""
        let sentenceEndings: Set<Character> = ["，", "。", "！", "？", "；", "：", ",", ".", "!", "?", ";", ":"]

        for character in line {
            currentLine.append(character)
            if sentenceEndings.contains(character) {
                lines.append(currentLine)
                currentLine = ""
            }
        }

        if !currentLine.isEmpty {
            lines.append(currentLine)
        }

        return lines.isEmpty ? [line] : lines
    }

    private static let loweredPunctuation: Set<Character> = ["，", "。", "；", "、", "：", ",", ";", ":"]

    /// Fonts like Huiwen Mincho center full-width punctuation vertically; nudge those
    /// glyphs down to the usual Chinese bottom-left position without changing line metrics.
    private func poemLineText(_ line: String, fontSize: CGFloat) -> Text {
        let text = line.poemScript(script)
        guard let dropFactor = typeface.punctuationDropFactor else { return Text(text) }

        let drop = dropFactor * fontSize
        var result = Text("")
        var run = ""
        for character in text {
            if Self.loweredPunctuation.contains(character) {
                result = result + Text(run) + Text(String(character)).baselineOffset(-drop)
                run = ""
            } else {
                run.append(character)
            }
        }
        return result + Text(run)
    }

    init(poem: ClassicPoem, favoriteIDs: Binding<Set<String>>) {
        self.poem = poem
        self._favoriteIDs = favoriteIDs
        self._aiAppreciation = State(initialValue: ClassicAppreciationCache.value(for: poem.id))
    }

    var body: some View {
        ZStack {
            Image(poem.backgroundImageName)
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
                .overlay(.white.opacity(0.34))

            ViewThatFits(in: .vertical) {
                detailContent

                ScrollView {
                    detailContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                CircleToolbarButton(systemName: "chevron.left") { dismiss() }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                CircleToolbarButton(systemName: isFavorite ? "bookmark.fill" : "bookmark") { toggleFavorite() }
                CircleToolbarButton(systemName: "square.and.arrow.up") { showsShare = true }
            }
        }
        .fullScreenCover(isPresented: $showsShare) {
            PoemSharePreviewView(
                imageTitle: poem.localizedTitle.poemScript(script),
                lines: poem.lines.map { $0.poemScript(script) },
                locationMark: "\(poem.localizedDynasty) · \(poem.localizedAuthor)".poemScript(script),
                lunarDateText: "",
                dayPeriodText: ""
            )
        }
        .sheet(item: $paywallReason) { reason in
            PaywallView(reason: reason) {
                paywallReason = nil
            }
        }
        .sheet(isPresented: $showsMusicCredits) {
            PoemMusicCreditsSheet()
        }
        .onDisappear {
            musicPlayer.stop()
        }
    }

    private var hero: some View {
        VStack(spacing: 6) {
            Text(poem.localizedTitle.poemScript(script))
                .font(typeface.font(size: poem.localizedTitle.count > 24 ? 23 : 30))
                .multilineTextAlignment(.center)
                .foregroundStyle(ClassicPalette.ink)
            Text("\(poem.localizedDynasty) · \(poem.localizedAuthor)".poemScript(script))
                .font(typeface.smallFont)
                .foregroundStyle(ClassicPalette.mutedInk)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 20)
        .padding(.bottom, 18)
    }

    private var detailContent: some View {
        VStack(spacing: 0) {
            hero
            readingPaper
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 18)
    }

    private var readingPaper: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(spacing: 10) {
                ForEach(Array(readingLines.enumerated()), id: \.offset) { _, line in
                    poemLineText(line, fontSize: 20)
                        .font(typeface.font(size: 20))
                        .foregroundStyle(ClassicPalette.ink)
                        .multilineTextAlignment(.center)
                        .lineSpacing(7)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)

            musicSection

            if let translation = poem.localizedTranslation {
                DetailSection(title: AppLanguage.copy("今译", "Translation"), text: translation)
            }

            if let appreciation = displayedAppreciation {
                DetailSection(
                    title: hasBundledAppreciation ? AppLanguage.copy("赏析", "Commentary") : AppLanguage.copy("AI 赏析", "AI commentary"),
                    text: appreciation,
                    footnote: hasBundledAppreciation ? nil : AppLanguage.copy("由 AI 生成，仅作阅读参考。", "Generated by AI for reading reference only.")
                )
            } else {
                aiAppreciationPrompt
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 22)
        .background(.white.opacity(0.86), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(.white.opacity(0.8), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.08), radius: 18, y: 10)
    }

    private var musicSection: some View {
        let suggestedTrack = PoemMusicTrack.recommended(for: poem)
        let displayedTrack = musicPlayer.activeTrack ?? suggestedTrack
        let isCurrentTrack = musicPlayer.activeTrack?.id == displayedTrack.id

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                Rectangle()
                    .fill(ClassicPalette.cinnabar)
                    .frame(width: 3, height: 18)
                Text(AppLanguage.copy("赏析配乐", "Music for reading").poemScript(script))
                    .font(typeface.titleFont)
                    .foregroundStyle(ClassicPalette.ink)
                Spacer()
                Button {
                    showsMusicCredits = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(ClassicPalette.mutedInk)
                        .frame(width: 30, height: 30)
                }
                .accessibilityLabel(AppLanguage.copy("音乐来源与授权", "Music credits and licenses").poemScript(script))
            }

            HStack(spacing: 12) {
                Button {
                    musicPlayer.toggle(displayedTrack)
                } label: {
                    Image(systemName: isCurrentTrack && musicPlayer.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 42, height: 42)
                        .foregroundStyle(.white)
                        .background(ClassicPalette.cinnabar, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel((isCurrentTrack && musicPlayer.isPlaying ? AppLanguage.copy("暂停配乐", "Pause music") : AppLanguage.copy("播放配乐", "Play music")).poemScript(script))

                VStack(alignment: .leading, spacing: 3) {
                    Text(displayedTrack.localizedTitle.poemScript(script))
                        .font(typeface.bodyFont)
                        .foregroundStyle(ClassicPalette.ink)
                    Text(displayedTrack.localizedSubtitle.poemScript(script))
                        .font(typeface.smallFont)
                        .foregroundStyle(ClassicPalette.mutedInk)
                }

                Spacer(minLength: 0)

                Menu {
                    ForEach(PoemMusicTrack.all) { track in
                        Button {
                            musicPlayer.play(track)
                        } label: {
                            if track.id == displayedTrack.id {
                                Label(track.localizedTitle.poemScript(script), systemImage: "checkmark")
                            } else {
                                Text(track.localizedTitle.poemScript(script))
                            }
                        }
                    }
                } label: {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(ClassicPalette.cinnabar)
                        .frame(width: 38, height: 38)
                        .background(ClassicPalette.cinnabar.opacity(0.09), in: Circle())
                }
                .accessibilityLabel(AppLanguage.copy("选择配乐", "Choose music").poemScript(script))
            }

            if let errorMessage = musicPlayer.errorMessage {
                Text(errorMessage.poemScript(script))
                    .font(typeface.smallFont)
                    .foregroundStyle(ClassicPalette.cinnabar)
            }
        }
    }

    private var aiAppreciationPrompt: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(AppLanguage.copy("赏析", "Commentary").poemScript(script))
                .font(typeface.titleFont)
                .foregroundStyle(ClassicPalette.ink)
            Text(AppLanguage.copy("这首诗暂未收录精选赏析，可以请 AI 从意象、语言和情感入手解读。", "This poem has no curated commentary yet. Ask AI to explore its imagery, language, and feeling.").poemScript(script))
                .font(typeface.bodyFont)
                .foregroundStyle(ClassicPalette.mutedInk)
                .lineSpacing(6)

            if !hasPremiumAccess {
                Text(AppLanguage.copy("每日可免费生成 1 次；雅集会员不限次。", "One free commentary each day. Pro is unlimited.").poemScript(script))
                    .font(typeface.smallFont)
                    .foregroundStyle(ClassicPalette.mutedInk.opacity(0.76))
            }

            if let generationError {
                Text(generationError.poemScript(script))
                    .font(typeface.smallFont)
                    .foregroundStyle(ClassicPalette.cinnabar)
            }

            Button {
                Task { await generateAppreciation() }
            } label: {
                HStack(spacing: 8) {
                    if isGenerating { ProgressView().tint(.white) }
                    Text((isGenerating ? AppLanguage.copy("正在品读…", "Reading…") : AppLanguage.copy("生成 AI 赏析", "Generate AI commentary")).poemScript(script))
                }
                .font(typeface.accentFont)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(ClassicPalette.cinnabar, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isGenerating)
        }
    }

    private func toggleFavorite() {
        if isFavorite {
            favoriteIDs.remove(poem.id)
        } else {
            favoriteIDs.insert(poem.id)
        }
        ClassicPoemFavorites.save(favoriteIDs, including: poem)
    }

    @MainActor
    private func generateAppreciation() async {
        guard !isGenerating else { return }
        guard hasPremiumAccess || PremiumAccess.freeAppreciationRemaining > 0 else {
            paywallReason = .classicAppreciation
            return
        }
        isGenerating = true
        generationError = nil
        do {
            let text = try await BailianPoetryClient().generateClassicAppreciation(poem: poem, script: script)
            aiAppreciation = text
            ClassicAppreciationCache.save(text, for: poem.id)
            _ = PremiumAccess.consumeAppreciationIfNeeded(hasPremiumAccess: hasPremiumAccess)
        } catch BailianError.missingConfig {
            generationError = AppLanguage.copy("AI 服务尚未配置，请稍后再试。", "AI is not configured. Try again later.")
        } catch {
            generationError = AppLanguage.copy("暂时无法生成赏析，请稍后再试。", "Unable to generate commentary right now. Try again later.")
        }
        isGenerating = false
    }
}

struct CircleToolbarButton: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(ClassicPalette.ink)
                .frame(width: 36, height: 36)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
    }
}

private struct DetailSection: View {
    @Environment(\.poemTypeface) private var typeface
    @Environment(\.poemScript) private var script
    let title: String
    let text: String
    var footnote: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 9) {
                Rectangle()
                    .fill(ClassicPalette.cinnabar)
                    .frame(width: 3, height: 18)
                Text(title.poemScript(script))
                    .font(typeface.titleFont)
                    .foregroundStyle(ClassicPalette.ink)
            }
            Text(text.poemScript(script))
                .font(typeface.bodyFont)
                .foregroundStyle(ClassicPalette.mutedInk)
                .lineSpacing(8)
                .textSelection(.enabled)
            if let footnote {
                Text(footnote.poemScript(script))
                    .font(typeface.smallFont)
                    .foregroundStyle(ClassicPalette.mutedInk.opacity(0.7))
            }
        }
    }
}

private struct FlowingTags: View {
    @Environment(\.poemTypeface) private var typeface
    @Environment(\.poemScript) private var script
    let tags: [String]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(tags, id: \.self) { tag in
                Text(tag.poemScript(script))
                    .font(typeface.smallFont)
                    .foregroundStyle(ClassicPalette.cinnabar)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(ClassicPalette.cinnabar.opacity(0.08), in: Capsule())
            }
        }
    }
}

private struct PoemMusicCreditsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.poemTypeface) private var typeface
    @Environment(\.poemScript) private var script

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(AppLanguage.copy("所有曲目均为古琴实录或琴歌，并由原始 Ogg 文件转码为 M4A。使用 CC 授权音乐时，应用分发须保留作者、原始来源、许可证与转码说明。", "All tracks are guqin recordings or qin songs, converted from the original Ogg files to M4A. App distribution must retain author, source, license, and conversion notices."))
                        .font(typeface.bodyFont)
                        .foregroundStyle(ClassicPalette.mutedInk)
                        .lineSpacing(5)
                }

                Section(AppLanguage.copy("曲目与授权", "Tracks and licenses")) {
                    ForEach(PoemMusicTrack.all) { track in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(track.localizedTitle.poemScript(script))
                                .font(typeface.bodyFont)
                                .foregroundStyle(ClassicPalette.ink)
                            Text(AppLanguage.copy("演奏：Charlie Huang（Charles R Tsua） · ", "Performed by Charlie Huang (Charles R Tsua) · ") + track.license)
                                .font(typeface.smallFont)
                                .foregroundStyle(ClassicPalette.mutedInk)
                            Link(AppLanguage.copy("查看原始来源", "View original source"), destination: track.sourceURL)
                                .font(typeface.smallFont)
                                .foregroundStyle(ClassicPalette.cinnabar)
                        }
                        .padding(.vertical, 3)
                    }
                }
            }
            .navigationTitle(AppLanguage.copy("音乐致谢", "Music credits").poemScript(script))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(AppLanguage.copy("完成", "Done").poemScript(script)) {
                        dismiss()
                    }
                }
            }
        }
    }
}

enum ClassicPalette {
    static let ink = Color(red: 0.08, green: 0.075, blue: 0.07)
    static let mutedInk = Color(red: 0.34, green: 0.32, blue: 0.29)
    static let cinnabar = Color(red: 0.77, green: 0.02, blue: 0.06)
}

#Preview("赏诗") {
    ClassicPoetryView()
        .environmentObject(PoemMusicPlayer())
}
