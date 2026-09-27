import SwiftUI
import UIKit

struct ClassicPoetryView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var dailyDate = Date.now
    @AppStorage(PoemTypeface.storageKey) private var typefaceRawValue = PoemTypeface.kaiti.rawValue
    @AppStorage(PoemScript.storageKey) private var scriptRawValue = PoemScript.simplified.rawValue
    @State private var query = ""
    @State private var favoriteIDs = ClassicPoemFavorites.load()
    @State private var selectedScope: PoetryScope = .all
    @State private var showsSettings = false
    @State private var path: [PoetRoute] = []
    @State private var showsPaywall = false
    @ObservedObject private var store = StoreManager.shared

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
        case .all:
            ClassicPoemLibrary.localSearch(normalizedQuery)
        case .tangShiThreeHundred:
            TangShiThreeHundredLibrary.search(normalizedQuery)
        case .songCiThreeHundred:
            SongCiThreeHundredLibrary.search(normalizedQuery)
        case .favorites:
            []
        }
    }

    private var discoveryPoems: [ClassicPoem] {
        switch selectedScope {
        case .all: DailyPoemPicker.corpus
        case .tangShiThreeHundred: TangShiThreeHundredLibrary.poems
        case .songCiThreeHundred: SongCiThreeHundredLibrary.poems
        case .favorites: []
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

        let combined = localPoems
        // Keep the original order within each access tier.
        return combined.filter { !$0.requiresMembership }
            + combined.filter { $0.requiresMembership }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                PaperBackground()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        header
                        if normalizedQuery.isEmpty,
                           let dailyPoem = DailyPoemPicker.poem(on: dailyDate) {
                            DailyPoemCard(poem: dailyPoem, date: dailyDate, onOpenPoem: openPoem)
                        }
                        ClassicSearchField(text: $query)
                        collectionPicker

                        resultsHeader

                        if displayedPoems.isEmpty {
                            emptyState
                        } else {
                            ForEach(displayedPoems) { poem in
                                Button {
                                    openPoem(poem)
                                } label: {
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
            .navigationDestination(for: PoetRoute.self) { route in
                switch route {
                case .poet(let poet):
                    PoetDetailView(poet: poet, favoriteIDs: $favoriteIDs, path: $path)
                case .poem(let poem):
                    ClassicPoemDetailView(poem: poem, favoriteIDs: $favoriteIDs, path: $path)
                }
            }
            .sheet(isPresented: $showsSettings) {
                FontSettingsView()
            }
            .sheet(isPresented: $showsPaywall) {
                PaywallView {
                    showsPaywall = false
                }
            }
        }
        .environment(\.poemTypeface, typeface)
        .environment(\.poemScript, script)
        .tint(ClassicPalette.cinnabar)
        .onChange(of: scenePhase) { _, _ in
            dailyDate = .now
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            dailyDate = .now
        }
        .task(id: dailyDate) {
            guard scenePhase == .active else { return }
            // Sleep until the next local midnight; changing the date or scene
            // phase cancels this task and schedules against the current clock.
            guard let midnight = Calendar.autoupdatingCurrent.dateInterval(of: .day, for: .now)?.end else { return }
            let delay = max(0, midnight.timeIntervalSinceNow)
            do {
                try await Task.sleep(for: .seconds(delay))
                dailyDate = .now
            } catch {
                // Cancellation is expected when leaving the foreground.
            }
        }
    }

    private func openPoem(_ poem: ClassicPoem) {
        guard !poem.requiresMembership || store.isPremium else {
            showsPaywall = true
            return
        }
        path.append(.poem(poem))
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 6) {
                Text((selectedScope == .favorites ? AppLanguage.copy("我的收藏", "Saved poems") : AppLanguage.copy("赏诗", "Read")).poemScript(script))
                    .font(typeface.font(size: 29))
                    .foregroundStyle(ClassicPalette.ink)
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
                ScopeButton(title: AppLanguage.copy("全部", "All"), selected: selectedScope == .all) {
                    selectedScope = .all
                }
                ScopeButton(title: AppLanguage.copy("唐诗", "Tang Poems"), selected: selectedScope == .tangShiThreeHundred) {
                    selectedScope = .tangShiThreeHundred
                }
                ScopeButton(title: AppLanguage.copy("宋词", "Song Lyrics"), selected: selectedScope == .songCiThreeHundred) {
                    selectedScope = .songCiThreeHundred
                }
                ScopeButton(title: AppLanguage.copy("我的收藏", "Saved"), selected: selectedScope == .favorites) {
                    selectedScope = .favorites
                }
            }
        }
    }

    private var resultsHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(resultsTitle.poemScript(script))
                    .font(typeface.titleFont)
                    .foregroundStyle(ClassicPalette.ink)
                if selectedScope != .favorites && !displayedPoems.isEmpty {
                    Text(AppLanguage.isEnglish ? "\(displayedPoems.count) poems" : "\(displayedPoems.count) 首")
                        .font(typeface.smallFont)
                        .foregroundStyle(ClassicPalette.mutedInk)
                }
            }
            Spacer(minLength: 0)
            if selectedScope != .favorites && normalizedQuery.isEmpty {
                Button {
                    guard let poem = DailyPoemPicker.random(
                        in: discoveryPoems,
                        hasPremiumAccess: store.isPremium
                    ) else { return }
                    openPoem(poem)
                } label: {
                    Label(AppLanguage.copy("随机一首", "Random poem").poemScript(script), systemImage: "dice.fill")
                        .font(typeface.smallFont)
                        .foregroundStyle(ClassicPalette.cinnabar)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 44)
                        .background(.white.opacity(0.76), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 4)
    }

    private var resultsTitle: String {
        if !normalizedQuery.isEmpty { return AppLanguage.copy("搜索结果", "Search results") }
        switch selectedScope {
        case .all: return AppLanguage.copy("全部诗词", "All poems")
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

}

/// A dedicated home for poems saved while reading. Its card grid intentionally
/// echoes the former archive, while poem detail keeps the same custom share flow.
struct SavedClassicPoemsView: View {
    @Environment(\.poemTypeface) private var typeface
    @Environment(\.poemScript) private var script
    @State private var favoriteIDs = ClassicPoemFavorites.load()
    @State private var poems = ClassicPoemFavorites.loadPoems()
    @State private var showsSettings = false
    @State private var path: [PoetRoute] = []
    @State private var poemPendingRemoval: ClassicPoem?

    private var savedPoems: [ClassicPoem] {
        poems.filter { favoriteIDs.contains($0.id) }
    }

    var body: some View {
        NavigationStack(path: $path) {
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
                                    savedPoemCell(poem)
                                }
                            }
                            .padding(.horizontal, 24)
                            .padding(.bottom, 50)
                        }
                    }
                }
            }
            .navigationBarHidden(true)
            .navigationDestination(for: PoetRoute.self) { route in
                switch route {
                case .poet(let poet):
                    PoetDetailView(poet: poet, favoriteIDs: $favoriteIDs, path: $path)
                case .poem(let poem):
                    ClassicPoemDetailView(poem: poem, favoriteIDs: $favoriteIDs, path: $path)
                }
            }
            .sheet(isPresented: $showsSettings) {
                FontSettingsView()
            }
            .alert("Remove from saved poems?", isPresented: Binding(
                get: { poemPendingRemoval != nil },
                set: { if !$0 { poemPendingRemoval = nil } }
            )) {
                Button("Cancel", role: .cancel) { poemPendingRemoval = nil }
                Button("Remove", role: .destructive) {
                    if let poem = poemPendingRemoval {
                        SensoryFeedback.lightTap()
                        withAnimation(.easeOut(duration: 0.25)) {
                            favoriteIDs.remove(poem.id)
                            ClassicPoemFavorites.save(favoriteIDs)
                            poems = ClassicPoemFavorites.loadPoems()
                        }
                    }
                    poemPendingRemoval = nil
                }
            } message: {
                Text("You can save this poem again while reading.")
            }
        }
        .onAppear(perform: reloadSavedPoems)
        .environment(\.poemTypeface, typeface)
        .environment(\.poemScript, script)
        .tint(ClassicPalette.cinnabar)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 8) {
                Text(AppLanguage.copy("我的收藏", "Saved").poemScript(script))
                    .font(typeface.titleFont)
                    .foregroundStyle(ClassicPalette.ink)
                if !savedPoems.isEmpty {
                    Text("\(savedPoems.count) saved \(savedPoems.count == 1 ? "poem" : "poems") · Tap a card to read")
                        .font(.system(size: 12))
                        .foregroundStyle(ClassicPalette.mutedInk.opacity(0.72))
                }
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

    private func savedPoemCell(_ poem: ClassicPoem) -> some View {
        ZStack(alignment: .topTrailing) {
            NavigationLink {
                ClassicPoemDetailView(poem: poem, favoriteIDs: $favoriteIDs, path: $path)
            } label: {
                SavedClassicPoemCard(poem: poem)
            }
            .buttonStyle(.plain)

            Button {
                poemPendingRemoval = poem
            } label: {
                Image(systemName: "bookmark.slash")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(ClassicPalette.cinnabar)
                    .frame(width: 28, height: 28)
                    .background(.white.opacity(0.88), in: Circle())
                    .overlay {
                        Circle()
                            .stroke(ClassicPalette.cinnabar.opacity(0.45), lineWidth: 0.8)
                    }
            }
            .buttonStyle(.plain)
            .padding(7)
            .accessibilityLabel("Remove \(poem.localizedTitle) from saved poems")
        }
        .transition(.opacity.combined(with: .offset(y: 8)))
    }

    private func reloadSavedPoems() {
        favoriteIDs = ClassicPoemFavorites.load()
        poems = ClassicPoemFavorites.loadPoems()
    }
}

private struct SavedClassicPoemCard: View {
    @Environment(\.poemScript) private var script
    let poem: ClassicPoem

    var body: some View {
        PoemArchiveCard(
            title: poem.localizedTitle.poemScript(script),
            subtitle: poem.localizedAuthor,
            titleLineLimit: 2
        ) {
            SavedClassicPoemArtworkThumbnail(poem: poem)
        }
    }
}

private struct SavedClassicPoemArtworkThumbnail: View {
    let poem: ClassicPoem
    private let canvasSize = ShareArtworkLayout.portrait.canvasSize

    // A bounded excerpt keeps long poems and ci lyrics legible on a small card.
    // The reading destination continues to show the complete work.
    private var excerptLines: [String] {
        let phrases = poem.lines.flatMap {
            $0.components(separatedBy: CharacterSet(charactersIn: "，。！？；：、,.!?;:"))
        }
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        return phrases.prefix(4).map { phrase in
            phrase.count > 16 ? String(phrase.prefix(15)) + "…" : phrase
        }
    }

    private var excerptTitle: String {
        poem.title.count > 20 ? String(poem.title.prefix(19)) + "…" : poem.title
    }

    var body: some View {
        GeometryReader { geometry in
            let scale = geometry.size.width / canvasSize.width
            SharePoemArtwork(
                layout: .portrait,
                imageTitle: excerptTitle,
                lines: excerptLines,
                locationMark: nil,
                lunarDateText: poem.author,
                dayPeriodText: "",
                sealName: "",
                showsLight: true,
                showsSeal: false,
                showsTitle: true,
                background: poem.background,
                usesVerticalTextOverride: true
            )
            .frame(width: canvasSize.width, height: canvasSize.height)
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            .clipped()
        }
        .aspectRatio(ShareArtworkLayout.portrait.aspectRatio, contentMode: .fit)
    }
}

private enum PoetryScope: String {
    case all
    case tangShiThreeHundred
    case songCiThreeHundred
    case favorites

    var collectionTitle: String {
        switch self {
        case .tangShiThreeHundred: AppLanguage.copy(TangShiThreeHundredLibrary.collectionTitle, "Tang Poems")
        case .songCiThreeHundred: AppLanguage.copy(SongCiThreeHundredLibrary.collectionTitle, "Song Lyrics")
        case .all: AppLanguage.copy("全部", "All")
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
                .onSubmit {
                    isFocused = false
                }
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
        .onChange(of: text) { oldValue, newValue in
            if !oldValue.isEmpty && newValue.isEmpty {
                isFocused = false
            }
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

/// A single reading target for today's fixed poem. Random discovery lives
/// beside the collection heading, outside this card.
private struct DailyPoemCard: View {
    @Environment(\.poemTypeface) private var typeface
    @Environment(\.poemScript) private var script
    let poem: ClassicPoem
    let date: Date
    let onOpenPoem: (ClassicPoem) -> Void

    var body: some View {
        Button {
            onOpenPoem(poem)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center) {
                    Text(AppLanguage.copy("每日一首", "Poem of the Day").poemScript(script))
                        .font(typeface.smallFont)
                        .foregroundStyle(ClassicPalette.cinnabar)
                    Spacer()
                    Text(date, format: .dateTime.month().day())
                        .font(typeface.smallFont)
                        .foregroundStyle(ClassicPalette.mutedInk)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(poem.localizedTitle.poemScript(script))
                        .font(typeface.font(size: 21))
                        .foregroundStyle(ClassicPalette.ink)
                    Text(poem.localizedAuthor.poemScript(script))
                        .font(typeface.smallFont)
                        .foregroundStyle(ClassicPalette.mutedInk)
                    Text(poem.lines.prefix(2).joined(separator: "\n").poemScript(script))
                        .font(typeface.smallFont)
                        .foregroundStyle(ClassicPalette.ink.opacity(0.84))
                        .lineSpacing(4)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
            .background(.white.opacity(0.76), in: RoundedRectangle(cornerRadius: 19, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 19, style: .continuous)
                    .stroke(.white.opacity(0.72), lineWidth: 0.8)
            }
            .contentShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(AppLanguage.copy("阅读今日诗词", "Read today's poem").poemScript(script))
    }
}

struct ClassicPoemCard: View {
    @Environment(\.poemTypeface) private var typeface
    @Environment(\.poemScript) private var script
    @ObservedObject private var store = StoreManager.shared
    let poem: ClassicPoem
    let isFavorite: Bool

    private var isLocked: Bool {
        poem.requiresMembership && !store.isPremium
    }

    /// In English the card leads with the translated title (up to two lines)
    /// and sets the original underneath; in Chinese only the original is shown.
    @ViewBuilder
    private var titleBlock: some View {
        if let englishTitle = poem.englishTitle {
            VStack(alignment: .leading, spacing: 3) {
                Text(englishTitle.poemScript(script))
                    .font(typeface.font(size: 16))
                    .foregroundStyle(ClassicPalette.ink)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(poem.title.poemScript(script))
                    .font(typeface.font(size: 14))
                    .foregroundStyle(ClassicPalette.mutedInk)
                    .lineLimit(1)
            }
        } else {
            Text(poem.localizedTitle.poemScript(script))
                .font(typeface.font(size: 19))
                .foregroundStyle(ClassicPalette.ink)
                .lineLimit(1)
        }
    }

    /// A taste of the opening lines; the preview stays in Chinese mode, where
    /// readers can skim it, and yields its space to the bilingual title in English.
    @ViewBuilder
    private var openingLines: some View {
        if !AppLanguage.isEnglish {
            Text(poem.lines.prefix(2).joined(separator: "\n").poemScript(script))
                .font(typeface.smallFont)
                .foregroundStyle(ClassicPalette.ink.opacity(0.84))
                .lineSpacing(4)
                .lineLimit(2)
        }
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
                HStack(alignment: .top, spacing: 6) {
                    titleBlock
                    Spacer(minLength: 6)
                    if isFavorite {
                        Image(systemName: "bookmark.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(ClassicPalette.cinnabar)
                            .padding(.top, 3)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(poem.localizedAuthor.poemScript(script))
                        .font(typeface.smallFont)
                        .foregroundStyle(ClassicPalette.mutedInk)
                        .lineLimit(1)
                }

                openingLines
            }
            .padding(.vertical, 3)
        }
        .padding(12)
        .background(.white.opacity(0.76), in: RoundedRectangle(cornerRadius: 19, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .stroke(.white.opacity(0.72), lineWidth: 0.8)
        }
        .overlay(alignment: .topTrailing) {
            if isLocked {
                Image(systemName: "lock.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ClassicPalette.cinnabar.opacity(0.85))
                    .padding(10)
            }
        }
        .accessibilityLabel(
            AppLanguage.isEnglish
                ? "\(poem.localizedTitle) by \(poem.localizedAuthor)\(isLocked ? ", members only" : "")"
                : "\(poem.author)《\(poem.title)》\(isLocked ? "，雅集會員可讀" : "")"
        )
    }
}

struct ClassicPoemDetailView: View {
    @Environment(\.poemTypeface) private var typeface
    @Environment(\.poemScript) private var script
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var musicPlayer: PoemMusicPlayer
    let poem: ClassicPoem
    @Binding var favoriteIDs: Set<String>
    let path: Binding<[PoetRoute]>
    @State private var showsShare = false
    @State private var showsMusicCredits = false
    @State private var showsPaywall = false
    @State private var pendingPoet: ClassicPoet?
    @State private var readingColumnWidth: CGFloat = 0
    @ObservedObject private var store = StoreManager.shared

    private var isFavorite: Bool { favoriteIDs.contains(poem.id) }
    private var hasPremiumAccess: Bool { store.isPremium }
    private var poet: ClassicPoet? { ClassicPoetLibrary.find(name: poem.author) }
    /// Keep each verse on one row when it fits; only when the whole verse is
    /// too wide, break it into clause rows, and only when every clause still
    /// fits — otherwise the verse stays whole and wraps evenly instead of
    /// stranding a few characters on a second row.
    private var adaptiveReadingLines: [String] {
        poem.lines.flatMap { line -> [String] in
            let usableWidth = readingColumnWidth - 2
            guard usableWidth > 0 else { return [line] }

            let fits: (String) -> Bool = { PoemVerseSplitter.fitsOnOneLine($0.poemScript(script), typeface: typeface, fontSize: 20, maxWidth: usableWidth) }
            if fits(line) { return [line] }

            let segments = PoemVerseSplitter.split(line)
            let allFit = segments.count > 1 && segments.allSatisfy(fits)
            return allFit ? segments : [line]
        }
    }

    private struct ReadingColumnWidthKey: PreferenceKey {
        static var defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = max(value, nextValue())
        }
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

    init(poem: ClassicPoem, favoriteIDs: Binding<Set<String>>, path: Binding<[PoetRoute]>) {
        self.poem = poem
        self._favoriteIDs = favoriteIDs
        self.path = path
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
                lines: poem.lines,
                locationMark: poem.localizedAuthor.poemScript(script),
                lunarDateText: "",
                dayPeriodText: ""
            )
        }
        .sheet(isPresented: $showsPaywall) {
            PaywallView {
                showsPaywall = false
                if let pendingPoet {
                    path.wrappedValue.append(.poet(pendingPoet))
                    self.pendingPoet = nil
                }
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
            poetLink(poem.localizedAuthor)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 20)
        .padding(.bottom, 18)
    }

    /// Tapping the attribution opens the poet's profile. Members-only profiles
    /// reuse the gallery's paywall flow; authors without a profile render as
    /// plain, non-tappable text.
    private func poetLink(_ text: String) -> some View {
        Group {
            if let poet {
                Button {
                    openPoetProfile(poet)
                } label: {
                    poetLinkLabel(text)
                }
                .buttonStyle(.plain)
            } else {
                poetLinkLabel(text)
            }
        }
    }

    private func poetLinkLabel(_ text: String) -> some View {
        HStack(spacing: 4) {
            Text(text.poemScript(script))
            if poet != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
            }
        }
        .font(typeface.smallFont)
        .foregroundStyle(ClassicPalette.mutedInk)
    }

    private func openPoetProfile(_ poet: ClassicPoet) {
        guard !poet.requiresMembership || hasPremiumAccess else {
            pendingPoet = poet
            showsPaywall = true
            return
        }
        path.wrappedValue.append(.poet(poet))
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
            // English readers need the Chinese original above the text; the
            // Chinese hero already carries this title, so it stays hidden there.
            if AppLanguage.isEnglish {
                VStack(spacing: 8) {
                    Text(poem.title.poemScript(script))
                        .font(typeface.font(size: poem.title.count > 24 ? 20 : 24))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(ClassicPalette.ink)
                    poetLink(poem.author)
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 2)
            }

            VStack(spacing: 10) {
                ForEach(Array(adaptiveReadingLines.enumerated()), id: \.offset) { _, line in
                    poemLineText(line, fontSize: 20)
                        .font(typeface.font(size: 20))
                        .foregroundStyle(ClassicPalette.ink)
                        .multilineTextAlignment(.center)
                        .lineSpacing(7)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background {
                GeometryReader { geometry in
                    Color.clear
                        .preference(key: ReadingColumnWidthKey.self, value: geometry.size.width)
                }
            }
            .onPreferenceChange(ReadingColumnWidthKey.self) { readingColumnWidth = $0 }

            musicSection

            if let translation = poem.localizedTranslation {
                DetailSection(title: AppLanguage.copy("今译", "Translation"), text: translation)
            }

            if let appreciation = poem.localizedAppreciation {
                DetailSection(
                    title: AppLanguage.copy("赏析", "Commentary"),
                    text: appreciation
                )
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

    private func toggleFavorite() {
        if isFavorite {
            favoriteIDs.remove(poem.id)
        } else {
            favoriteIDs.insert(poem.id)
        }
        ClassicPoemFavorites.save(favoriteIDs, including: poem)
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
                .background(.white.opacity(0.88), in: Circle())
                .overlay(Circle().stroke(ClassicPalette.mutedInk.opacity(0.12), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }
}

private struct DetailSection: View {
    @Environment(\.poemTypeface) private var typeface
    @Environment(\.poemScript) private var script
    let title: String
    let text: String

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
