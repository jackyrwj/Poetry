import SwiftUI
import UIKit

struct ClassicPoetryView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Binding var pendingPoemID: String?
    /// Set by the 秋日诗会 event deep link.
    @Binding var opensAutumnGathering: Bool
    @State private var dailyDate = Date.now
    @AppStorage(PoemTypeface.storageKey) private var typefaceRawValue = PoemTypeface.kaiti.rawValue
    @AppStorage(PoemScript.storageKey) private var scriptRawValue = PoemScript.simplified.rawValue
    @State private var query = ""
    @State private var favoriteIDs = ClassicPoemFavorites.load()
    @State private var selectedScope: PoetryScope = .all
    @State private var showsMembersOnly = false
    @State private var path: [PoetRoute] = []
    @State private var showsPaywall = false
    @State private var showsWidgetGuide = false
    @State private var displayedPoems: [ClassicPoem]
    @State private var isSearchFocused = false
    @State private var viewportHeight: CGFloat = 0
    @ObservedObject private var store = StoreManager.shared

    private static let searchFieldID = "classicSearchField"

    init(pendingPoemID: Binding<String?> = .constant(nil), opensAutumnGathering: Binding<Bool> = .constant(false)) {
        _pendingPoemID = pendingPoemID
        _opensAutumnGathering = opensAutumnGathering
        _displayedPoems = State(initialValue: Self.results(for: SearchRequest(
            query: "",
            scope: .all,
            showsMembersOnly: false,
            isPremium: StoreManager.shared.isPremium
        )))
    }

    private var typeface: PoemTypeface {
        PoemTypeface(rawValue: typefaceRawValue) ?? .kaiti
    }

    private var script: PoemScript {
        PoemScript(rawValue: scriptRawValue) ?? .simplified
    }

    private var normalizedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var searchRequest: SearchRequest {
        SearchRequest(
            query: normalizedQuery,
            scope: selectedScope,
            showsMembersOnly: showsMembersOnly,
            isPremium: store.isPremium
        )
    }

    private var isSearching: Bool {
        isSearchFocused || !normalizedQuery.isEmpty
    }

    private var discoveryPoems: [ClassicPoem] {
        switch selectedScope {
        case .all: DailyPoemPicker.corpus
        case .tangShiThreeHundred: ClassicPoemLibrary.tangShi
        case .songCiThreeHundred: ClassicPoemLibrary.songCi
        }
    }

    /// Signature works first (see `ClassicPoem.signatureRank`), then the other
    /// free poems, then members-only works, the last two in collection order.
    /// Runs off the main thread.
    nonisolated private static func results(for request: SearchRequest) -> [ClassicPoem] {
        let collection = switch request.scope {
        case .all: ClassicPoemLibrary.allPoems
        case .tangShiThreeHundred: ClassicPoemLibrary.tangShi
        case .songCiThreeHundred: ClassicPoemLibrary.songCi
        }
        let matches = ClassicPoemLibrary.search(request.query, in: collection)
        let poems = request.showsMembersOnly && !request.isPremium
            ? matches.filter(\.requiresMembership)
            : matches
        var ranked: [(rank: Int, offset: Int, poem: ClassicPoem)] = []
        for (offset, poem) in poems.enumerated() {
            if let rank = poem.signatureRank { ranked.append((rank, offset, poem)) }
        }
        ranked.sort { $0.rank != $1.rank ? $0.rank < $1.rank : $0.offset < $1.offset }
        let signature = ranked.map(\.poem)
        return signature
            + poems.filter { !$0.isSignature && !$0.requiresMembership }
            + poems.filter(\.requiresMembership)
    }

    /// Keeps `displayedPoems` in step with the request: typing is debounced and
    /// the search runs in the background so keystrokes never wait on it.
    private func refreshResults(for request: SearchRequest) async {
        if !request.query.isEmpty {
            do { try await Task.sleep(for: .milliseconds(120)) } catch { return }
        }
        let poems = await Task.detached(priority: .userInitiated) {
            Self.results(for: request)
        }.value
        guard !Task.isCancelled else { return }
        displayedPoems = poems
    }

    /// Pins the search field near the top of the screen, a little below the
    /// safe area. The anchor is chosen so the field's top lands `inset` points
    /// below the viewport's top: y = inset / (viewport - field).
    private func scrollSearchFieldToTop(_ proxy: ScrollViewProxy) {
        let inset: CGFloat = 12
        let fieldHeight: CGFloat = 46
        let travel = max(viewportHeight - fieldHeight, 1)
        withAnimation(.easeOut(duration: 0.28)) {
            proxy.scrollTo(Self.searchFieldID, anchor: UnitPoint(x: 0.5, y: inset / travel))
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                PaperBackground()

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 18) {
                            header
                            // Keep the daily card in place while searching so the
                            // search field doesn't jump when the query changes.
                            if let dailyPoem = DailyPoemPicker.poem(on: dailyDate) {
                                DailyPoemCard(poem: dailyPoem, date: dailyDate, onOpenPoem: openPoem)
                            }
                            if AutumnGathering.isActive(on: dailyDate), !AutumnGathering.poems.isEmpty {
                                AutumnGatheringCard {
                                    path.append(.autumnGathering)
                                }
                            }
                            ClassicSearchField(text: $query, isFocused: $isSearchFocused)
                                .id(Self.searchFieldID)
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

                            // While searching, keep at least a screen of content below
                            // the field so shrinking results can't pull it back down.
                            if isSearching {
                                Color.clear
                                    .frame(height: max(0, viewportHeight - 120))
                                    .accessibilityHidden(true)
                            }
                        }
                        .padding(.horizontal, 22)
                        .padding(.top, 20)
                        .padding(.bottom, 36)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { viewportHeight = $0 }
                    .onChange(of: isSearchFocused) { _, focused in
                        if focused { scrollSearchFieldToTop(proxy) }
                    }
                }
            }
            .navigationBarHidden(true)
            .navigationDestination(for: PoetRoute.self) { route in
                PoetRouteDestination(route: route, favoriteIDs: $favoriteIDs, path: $path)
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
        .task(id: searchRequest) {
            await refreshResults(for: searchRequest)
        }
        .task {
            // Build the search index before the first keystroke needs it.
            await Task.detached(priority: .utility) { _ = ClassicPoemIndex.searchText }.value
        }
        .onChange(of: scenePhase) { _, _ in
            dailyDate = .now
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            // Offered on the reader's second day, shortly after the app opens.
            guard phase == .active else { return }
            // Idempotent per day; makes sure today counts before checking.
            WidgetGuide.recordActiveDay()
            offerWidgetGuideIfNeeded(after: .milliseconds(1200))
        }
        .onChange(of: pendingPoemID, initial: true) { _, _ in
            openPendingPoem()
        }
        .onChange(of: opensAutumnGathering, initial: true) { _, opens in
            guard opens else { return }
            opensAutumnGathering = false
            guard AutumnGathering.isActive() else { return }
            path = [.autumnGathering]
        }
        .onChange(of: path.isEmpty) { _, isEmpty in
            if isEmpty { offerWidgetGuideIfNeeded() }
        }
        .sheet(isPresented: $showsWidgetGuide) {
            WidgetGuideView(isPrompt: true)
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

    /// Offered when the app opens (from the reader's second day) and again on
    /// coming back from a poem, unless the widget is already on the Home Screen.
    private func offerWidgetGuideIfNeeded(after delay: Duration = .milliseconds(450)) {
        guard WidgetGuide.canPrompt else { return }
        Task { @MainActor in
            guard !(await WidgetGuide.isInstalled()) else { return }
            try? await Task.sleep(for: delay)
            guard scenePhase == .active, path.isEmpty, pendingPoemID == nil, !opensAutumnGathering,
                  !showsPaywall, !showsWidgetGuide, WidgetGuide.canPrompt else { return }
            WidgetGuide.recordPrompt()
            showsWidgetGuide = true
        }
    }

    /// Widget taps land here; the daily poem is always free to read.
    private func openPendingPoem() {
        guard let id = pendingPoemID else { return }
        pendingPoemID = nil
        guard let poem = DailyPoemPicker.dailyPoems.first(where: { $0.id == id })
            ?? ClassicPoemLibrary.allPoems.first(where: { $0.id == id }) else { return }
        path = []
        openPoem(poem)
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
                Text(AppLanguage.copy("赏诗", "Read").poemScript(script))
                    .font(typeface.font(size: 29))
                    .foregroundStyle(ClassicPalette.ink)
            }

            Spacer()

            // English readers have a Saved tab; Chinese reaches it from here.
            if !AppLanguage.isEnglish {
                CircleToolbarButton(systemName: "bookmark") {
                    path.append(.savedPoems)
                }
                .accessibilityLabel("我的收藏".poemScript(script))
            }
        }
        .frame(minHeight: 38)
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
                // Members read everything, so only non-members get the members-only filter.
                if !store.isPremium {
                    Rectangle()
                        .fill(ClassicPalette.mutedInk.opacity(0.24))
                        .frame(width: 0.8, height: 18)
                        .padding(.horizontal, 2)
                    MembersFilterToggle(isOn: $showsMembersOnly)
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
                if !displayedPoems.isEmpty {
                    Text(AppLanguage.isEnglish ? "\(displayedPoems.count) poems" : "\(displayedPoems.count) 首")
                        .font(typeface.smallFont)
                        .foregroundStyle(ClassicPalette.mutedInk)
                }
            }
            Spacer(minLength: 0)
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
            // Hidden rather than removed while searching so the row height stays fixed.
            .opacity(normalizedQuery.isEmpty ? 1 : 0)
            .allowsHitTesting(normalizedQuery.isEmpty)
            .accessibilityHidden(!normalizedQuery.isEmpty)
        }
        .padding(.top, 4)
    }

    private var resultsTitle: String {
        if !normalizedQuery.isEmpty { return AppLanguage.copy("搜索结果", "Search results") }
        switch selectedScope {
        case .all: return AppLanguage.copy("全部诗词", "All poems")
        case .tangShiThreeHundred: return TangShiThreeHundredLibrary.collectionTitle
        case .songCiThreeHundred: return SongCiThreeHundredLibrary.collectionTitle
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.magnifyingglass")
                .font(.system(size: 28, weight: .light))
            Text(AppLanguage.copy("没有找到相关诗词", "No poems found").poemScript(script))
                .font(typeface.bodyFont)
            Text(AppLanguage.copy("可以换一个诗名、作者或原文关键词再试。", "Try a different title, author, or line from the original poem.").poemScript(script))
                .font(typeface.smallFont)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(ClassicPalette.mutedInk)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 54)
    }

}

/// The English Saved tab: its own stack around the saved-poems grid.
struct SavedClassicPoemsView: View {
    @Environment(\.poemTypeface) private var typeface
    @Environment(\.poemScript) private var script
    @State private var favoriteIDs = ClassicPoemFavorites.load()
    @State private var path: [PoetRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            SavedClassicPoemsList(favoriteIDs: $favoriteIDs, path: $path, isPushed: false)
                .navigationBarHidden(true)
                .navigationDestination(for: PoetRoute.self) { route in
                    PoetRouteDestination(route: route, favoriteIDs: $favoriteIDs, path: $path, isSavedStack: true)
                }
        }
        .environment(\.poemTypeface, typeface)
        .environment(\.poemScript, script)
        .tint(ClassicPalette.cinnabar)
    }
}

/// Every stack built on `PoetRoute` resolves its routes the same way.
struct PoetRouteDestination: View {
    let route: PoetRoute
    @Binding var favoriteIDs: Set<String>
    @Binding var path: [PoetRoute]
    /// The English Saved tab's stack, whose root is the saved grid itself.
    var isSavedStack = false

    /// Pages opened from a saved collection only read: saving and unsaving
    /// stay on the collection pages, so the pages beneath never go stale.
    private var allowsSaving: Bool {
        !isSavedStack && !path.contains(where: \.isSavedCollection)
    }

    var body: some View {
        switch route {
        case .poet(let poet):
            PoetDetailView(poet: poet, favoriteIDs: $favoriteIDs, path: $path, allowsSaving: allowsSaving)
        case .poem(let poem):
            ClassicPoemDetailView(poem: poem, favoriteIDs: $favoriteIDs, path: $path, allowsSaving: allowsSaving)
        case .savedPoem(let poem):
            SavedClassicPoemDetailView(poem: poem)
        case .savedPoems:
            SavedClassicPoemsList(favoriteIDs: $favoriteIDs, path: $path, isPushed: true)
        case .savedPoets:
            SavedPoetsView(path: $path)
        case .autumnGathering:
            AutumnGatheringView(favoriteIDs: $favoriteIDs, path: $path)
        }
    }
}

/// A dedicated home for poems saved while reading: the English Saved tab, and
/// the page behind the bookmark on the Chinese 赏诗 header. Its card grid
/// echoes the former archive, while poem detail keeps the custom share flow.
struct SavedClassicPoemsList: View {
    @Environment(\.poemTypeface) private var typeface
    @Environment(\.poemScript) private var script
    @Environment(\.dismiss) private var dismiss
    @Binding var favoriteIDs: Set<String>
    @Binding var path: [PoetRoute]
    /// Pushed from 赏诗 rather than shown as its own tab: adds a back button.
    let isPushed: Bool
    @State private var poems = ClassicPoemFavorites.loadPoems()
    @State private var poemPendingRemoval: ClassicPoem?

    private var savedPoems: [ClassicPoem] {
        poems.filter { favoriteIDs.contains($0.id) }
    }

    var body: some View {
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
        .navigationBarBackButtonHidden(true)
        .toolbar(isPushed ? .visible : .hidden, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            if isPushed {
                ToolbarItem(placement: .topBarLeading) {
                    CircleToolbarButton(systemName: "chevron.left") { dismiss() }
                }
            }
        }
        .alert(AppLanguage.copy("取消收藏这首诗？", "Remove from saved poems?").poemScript(script), isPresented: Binding(
            get: { poemPendingRemoval != nil },
            set: { if !$0 { poemPendingRemoval = nil } }
        )) {
            Button(AppLanguage.copy("取消", "Cancel").poemScript(script), role: .cancel) { poemPendingRemoval = nil }
            Button(AppLanguage.copy("移除", "Remove").poemScript(script), role: .destructive) {
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
            Text(AppLanguage.copy("读诗时可以再次收藏。", "You can save this poem again while reading.").poemScript(script))
        }
        .onAppear(perform: reloadSavedPoems)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 8) {
                Text(AppLanguage.copy("我的收藏", "Saved").poemScript(script))
                    .font(typeface.titleFont)
                    .foregroundStyle(ClassicPalette.ink)
                if !savedPoems.isEmpty {
                    Text(savedCountText.poemScript(script))
                        .font(.system(size: 12))
                        .foregroundStyle(ClassicPalette.mutedInk.opacity(0.72))
                }
            }

            Spacer()
        }
        .frame(minHeight: 38)
        .padding(.horizontal, 22)
        .padding(.top, isPushed ? 4 : 20)
        .padding(.bottom, 22)
    }

    private var savedCountText: String {
        let count = savedPoems.count
        if count == 1, let only = savedPoems.first, ClassicPoemFavorites.isStarter(only.id) {
            return AppLanguage.copy("先为你收下一首 · 可随时移除", "Saved for you to start · Remove anytime")
        }
        return AppLanguage.isEnglish
            ? "\(count) saved \(count == 1 ? "poem" : "poems") · Tap a card to read"
            : "已收藏 \(count) 首 · 点卡片阅读"
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
            NavigationLink(value: PoetRoute.savedPoem(poem)) {
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
            .accessibilityLabel(AppLanguage.isEnglish
                ? "Remove \(poem.localizedTitle) from saved poems"
                : "取消收藏《\(poem.title)》".poemScript(script))
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

/// Reopens a saved classic as the full paper artwork its Saved card previews,
/// closed by a colophon — when and where it was saved — and the reader's seal.
private struct SavedClassicPoemDetailView: View {
    let poem: ClassicPoem
    @State private var mark: ClassicPoemSaveMark
    @State private var showsShare = false

    /// Used when the reader has not set a personal seal: a collector's seal.
    private static let fallbackSealName = "珍藏"

    init(poem: ClassicPoem) {
        self.poem = poem
        _mark = State(initialValue: ClassicPoemFavorites.mark(for: poem.id))
    }

    private var style: ShareArtworkStyle {
        let preferences = ShareArtworkStyle.defaultPreferences
        return ShareArtworkStyle(
            background: poem.background,
            typeface: preferences.typeface,
            script: preferences.script,
            // Saved classics always read as traditional vertical columns.
            usesVerticalText: true,
            sealName: preferences.sealName.isEmpty ? Self.fallbackSealName : preferences.sealName,
            sealStyle: preferences.sealStyle,
            transliteration: preferences.transliteration,
            shadow: preferences.shadow
        )
    }

    private var lunarDateText: String {
        PoemInscriptionDate.make(from: mark.savedAt).lunarDateText
    }

    private var colophon: String { poem.shareColophon(place: mark.place) }

    var body: some View {
        // Read the insets outside the full-bleed artwork: the tab bar's inset
        // is only reported to views that stay inside the safe area.
        GeometryReader { container in
            ZStack(alignment: .top) {
                PaperBackground(backgroundOverride: style.background, shadowStyleOverride: style.shadow)

                // The artwork fills the whole screen, under the status bar, the
                // quiet buttons and the tab bar, so the page reads as one sheet.
                GeometryReader { geometry in
                    let canvasWidth = ShareArtworkLayout.portrait.canvasSize.width
                    let scale = geometry.size.width / canvasWidth

                    ConfiguredShareArtwork(
                        layout: .portrait,
                        imageTitle: poem.title,
                        lines: poem.lines,
                        locationMark: colophon,
                        lunarDateText: lunarDateText,
                        dayPeriodText: "",
                        style: style,
                        translation: poem.shareTranslation,
                        extraTopPadding: (container.safeAreaInsets.top + 56) / scale,
                        extraBottomPadding: (container.safeAreaInsets.bottom + 12) / scale
                    )
                    .frame(width: canvasWidth, height: geometry.size.height / scale)
                    .scaleEffect(scale, anchor: .topLeading)
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(poem.localizedTitle) by \(poem.localizedAuthor)")
                }
                .ignoresSafeArea()

                // Only sharing: a way into the reading page from here would
                // lead back out of the saved collection it was opened from.
                PaperDetailTopBar {
                    QuietBackButton(title: AppLanguage.copy("分享", "Share")) {
                        showsShare = true
                    }
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            // The place may have arrived after this view was first built.
            mark = ClassicPoemFavorites.mark(for: poem.id)
        }
        .fullScreenCover(isPresented: $showsShare) {
            PoemSharePreviewView(
                imageTitle: poem.title,
                lines: poem.lines,
                locationMark: colophon,
                lunarDateText: lunarDateText,
                dayPeriodText: "",
                translation: poem.shareTranslation,
                initialBackground: poem.background
            )
        }
    }
}

private struct SearchRequest: Hashable, Sendable {
    let query: String
    let scope: PoetryScope
    let showsMembersOnly: Bool
    let isPremium: Bool
}

private enum PoetryScope: String, Sendable {
    case all
    case tangShiThreeHundred
    case songCiThreeHundred

    var collectionTitle: String {
        switch self {
        case .tangShiThreeHundred: AppLanguage.copy(TangShiThreeHundredLibrary.collectionTitle, "Tang Poems")
        case .songCiThreeHundred: AppLanguage.copy(SongCiThreeHundredLibrary.collectionTitle, "Song Lyrics")
        case .all: AppLanguage.copy("全部", "All")
        }
    }
}

private struct ClassicSearchField: View {
    @Environment(\.poemTypeface) private var typeface
    @Environment(\.poemScript) private var script
    @Binding var text: String
    @Binding var isFocused: Bool
    @FocusState private var fieldFocused: Bool

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(ClassicPalette.mutedInk.opacity(0.72))
            TextField(AppLanguage.copy("诗名、作者或诗句", "Chinese title, author, or line").poemScript(script), text: $text)
                .font(typeface.bodyFont)
                .foregroundStyle(ClassicPalette.ink)
                .focused($fieldFocused)
                .submitLabel(.search)
                .onSubmit {
                    fieldFocused = false
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
                .stroke(fieldFocused ? ClassicPalette.cinnabar.opacity(0.45) : ClassicPalette.mutedInk.opacity(0.22), lineWidth: 1)
        }
        .onChange(of: text) { oldValue, newValue in
            if !oldValue.isEmpty && newValue.isEmpty {
                fieldFocused = false
            }
        }
        .onChange(of: fieldFocused) { _, focused in
            isFocused = focused
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

/// Jumps a non-member to the members-only works, which otherwise sit after
/// every free poem. It stacks with the collection scopes, so it reads as a
/// check toggle rather than a tab.
private struct MembersFilterToggle: View {
    @Environment(\.poemTypeface) private var typeface
    @Environment(\.poemScript) private var script
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: isOn ? "checkmark" : "crown.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isOn ? ClassicPalette.cinnabar : Color.premiumGold)
                Text(AppLanguage.copy("會員", "Pro").poemScript(script))
                    .font(typeface.smallFont)
            }
            .foregroundStyle(isOn ? ClassicPalette.cinnabar : ClassicPalette.mutedInk)
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(isOn ? ClassicPalette.cinnabar.opacity(0.08) : .white.opacity(0.68), in: Capsule())
            .overlay {
                Capsule().stroke(isOn ? ClassicPalette.cinnabar.opacity(0.7) : ClassicPalette.mutedInk.opacity(0.16), lineWidth: 0.8)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AppLanguage.copy("只看會員詩詞", "Pro poems only").poemScript(script))
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
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

    /// In English the card shows only the translated title (up to two lines);
    /// the original is set above the text on the reading page.
    @ViewBuilder
    private var titleBlock: some View {
        if let englishTitle = poem.englishTitle {
            Text(englishTitle.poemScript(script))
                .font(typeface.font(size: 16))
                .foregroundStyle(ClassicPalette.ink)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(poem.localizedTitle.poemScript(script))
                .font(typeface.font(size: 19))
                .foregroundStyle(ClassicPalette.ink)
                .lineLimit(1)
        }
    }

    /// A taste of the opening lines, shown in the original in both languages.
    /// Chinese cards show the first two lines. English cards show the first
    /// line with half-width punctuation, followed by one line of the English
    /// translation so the original stays readable at a glance.
    /// Each line stays on one row and shrinks slightly when needed, so a
    /// seven-character couplet never wraps and pushes the next line out.
    private var openingLines: some View {
        let isEnglish = AppLanguage.isEnglish
        let lines = poem.lines.prefix(isEnglish ? 1 : 2).map {
            isEnglish ? Self.halfWidthPunctuation($0) : $0
        }
        return VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line.poemScript(script))
                    .font(typeface.smallFont)
                    .foregroundStyle(ClassicPalette.ink.opacity(0.84))
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
            }

            if isEnglish, let excerpt = translationExcerpt {
                Text(excerpt)
                    .font(.system(size: 13, design: .serif).italic())
                    .foregroundStyle(ClassicPalette.mutedInk)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    /// The opening of the English translation, trimmed to its first clause
    /// so the single line reads as a phrase rather than a cut-off paragraph.
    private var translationExcerpt: String? {
        guard let text = poem.localizedTranslation?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return nil }
        let breaks: Set<Character> = [".", ";", "—", "?", "!"]
        guard let end = text.firstIndex(where: { breaks.contains($0) }) else { return text }
        let clause = text[..<end].trimmingCharacters(in: .whitespaces)
        return clause.isEmpty ? text : clause + "…"
    }

    private static let halfWidthMarks: [Character: String] = [
        "，": ", ", "。": ". ", "！": "! ", "？": "? ", "；": "; ", "：": ": ",
        "、": ", ", "（": " (", "）": ") ", "“": "\"", "”": "\"", "‘": "'", "’": "'"
    ]

    private static func halfWidthPunctuation(_ line: String) -> String {
        line.map { halfWidthMarks[$0] ?? String($0) }
            .joined()
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(poem.backgroundImageName)
                .resizable()
                .scaledToFill()
                .frame(width: 82, height: 108)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(alignment: .topLeading) {
                    if isLocked {
                        PremiumCrownBadge()
                            .offset(x: -5, y: -5)
                    }
                }

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
    @State private var showsPaywall = false
    @State private var pendingRoute: PoetRoute?
    @State private var readingColumnWidth: CGFloat = 0
    @ObservedObject private var store = StoreManager.shared
    @StateObject private var locationProvider = PoemLocationProvider()

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

    /// False when opened from a saved collection: the bookmark is hidden there.
    let allowsSaving: Bool

    init(poem: ClassicPoem, favoriteIDs: Binding<Set<String>>, path: Binding<[PoetRoute]>, allowsSaving: Bool = true) {
        self.poem = poem
        self._favoriteIDs = favoriteIDs
        self.path = path
        self.allowsSaving = allowsSaving
    }

    var body: some View {
        ViewThatFits(in: .vertical) {
            detailContent

            ScrollView {
                detailContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // As a background the painting takes the screen's size instead of
        // proposing its own fill size to the reading column.
        .background {
            Image(poem.backgroundImageName)
                .resizable()
                .scaledToFill()
                .overlay(.white.opacity(0.34))
                .ignoresSafeArea()
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                CircleToolbarButton(systemName: "chevron.left") { dismiss() }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                if allowsSaving {
                    CircleToolbarButton(systemName: isFavorite ? "bookmark.fill" : "bookmark") { toggleFavorite() }
                }
                CircleToolbarButton(systemName: "square.and.arrow.up") { showsShare = true }
            }
        }
        .fullScreenCover(isPresented: $showsShare) {
            // Same artwork as sharing from Saved: the Chinese title and a
            // colophon, with the English reading as a caption. A saved poem
            // keeps the date and place it was saved; otherwise it is today.
            let mark = isFavorite ? ClassicPoemFavorites.mark(for: poem.id) : nil
            PoemSharePreviewView(
                imageTitle: poem.title,
                lines: poem.lines,
                locationMark: poem.shareColophon(place: mark?.place ?? locationProvider.inscriptionPlace),
                lunarDateText: PoemInscriptionDate.make(from: mark?.savedAt ?? Date()).lunarDateText,
                dayPeriodText: "",
                translation: poem.shareTranslation,
                initialBackground: poem.background
            )
        }
        .sheet(isPresented: $showsPaywall) {
            PaywallView {
                showsPaywall = false
                if let pendingRoute {
                    path.wrappedValue.append(pendingRoute)
                    self.pendingRoute = nil
                }
            }
        }
        .onDisappear {
            musicPlayer.stop()
        }
        .onChange(of: locationProvider.inscriptionPlace) { _, place in
            guard let place, isFavorite else { return }
            ClassicPoemFavorites.recordPlace(place, for: poem.id)
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
            pendingRoute = .poet(poet)
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

            relatedSection
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

    @ViewBuilder
    private var relatedSection: some View {
        let related = RelatedPoems.recommendations(for: poem, prefersUnlocked: !hasPremiumAccess)
        if !related.isEmpty {
            VStack(alignment: .leading, spacing: 18) {
                DetailSectionTitle(title: AppLanguage.copy("延伸阅读", "Further reading"))

                if let series = related.series {
                    seriesPicker(series)
                }

                if !related.byAuthor.isEmpty {
                    relatedGroup(
                        title: AppLanguage.copy("\(poem.author)的其他作品", "More by \(poem.localizedAuthor)"),
                        poems: related.byAuthor,
                        showsAuthor: false
                    )
                }

                if let tune = related.tune, !related.byTune.isEmpty {
                    relatedGroup(
                        title: AppLanguage.copy("同调《\(tune)》", "Also set to \(tune.romanizedChinese)"),
                        poems: related.byTune,
                        showsAuthor: true
                    )
                }
            }
        }
    }

    private func seriesPicker(_ series: RelatedPoems.Series) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            relatedSubheading(AppLanguage.copy(
                "组诗《\(series.title)》",
                "One of a set of \(series.members.count) · \(series.title)"
            ))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(series.members, id: \.poem.id) { member in
                        let isCurrent = member.poem.id == poem.id
                        Button {
                            openRelated(member.poem, replacingCurrent: true)
                        } label: {
                            Text(AppLanguage.copy("其\(RelatedPoems.chineseNumeral(member.number))", "No. \(member.number)").poemScript(script))
                                .font(typeface.smallFont)
                                .foregroundStyle(isCurrent ? .white : ClassicPalette.cinnabar)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(isCurrent ? ClassicPalette.cinnabar : ClassicPalette.cinnabar.opacity(0.08), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(isCurrent)
                        .accessibilityAddTraits(isCurrent ? .isSelected : [])
                    }
                }
            }
            .scrollClipDisabled()
        }
    }

    private func relatedGroup(title: String, poems: [ClassicPoem], showsAuthor: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            relatedSubheading(title)
            ForEach(Array(poems.enumerated()), id: \.element.id) { index, related in
                if index > 0 {
                    Divider().overlay(ClassicPalette.mutedInk.opacity(0.1))
                }
                relatedRow(related, showsAuthor: showsAuthor)
            }
        }
    }

    private func relatedRow(_ related: ClassicPoem, showsAuthor: Bool) -> some View {
        let isLocked = related.requiresMembership && !hasPremiumAccess
        // A lyric's title is its tune, which the heading already names; lead with the poet instead.
        let heading = showsAuthor ? related.localizedAuthor : related.localizedTitle

        return Button {
            openRelated(related, replacingCurrent: false)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(heading.poemScript(script))
                        .font(typeface.bodyFont)
                        .foregroundStyle(ClassicPalette.ink)
                        .lineLimit(1)
                    if let firstLine = related.lines.first {
                        Text(firstLine.poemScript(script))
                            .font(typeface.smallFont)
                            .foregroundStyle(ClassicPalette.mutedInk)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: isLocked ? "lock.fill" : "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ClassicPalette.mutedInk.opacity(0.7))
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func relatedSubheading(_ text: String) -> some View {
        Text(text.poemScript(script))
            .font(typeface.smallFont)
            .foregroundStyle(ClassicPalette.mutedInk)
    }

    /// Moving within a set swaps the page in place, so paging 其一 → 其五 doesn't
    /// stack five pages to back out of; everything else pushes as usual.
    private func openRelated(_ target: ClassicPoem, replacingCurrent: Bool) {
        let route = PoetRoute.poem(target)
        guard !target.requiresMembership || hasPremiumAccess else {
            pendingRoute = route
            showsPaywall = true
            return
        }
        if replacingCurrent, case .poem(let current)? = path.wrappedValue.last, current.id == poem.id {
            path.wrappedValue[path.wrappedValue.count - 1] = route
        } else {
            path.wrappedValue.append(route)
        }
    }

    private func toggleFavorite() {
        if isFavorite {
            favoriteIDs.remove(poem.id)
        } else {
            favoriteIDs.insert(poem.id)
        }
        ClassicPoemFavorites.save(favoriteIDs, including: poem)
        if isFavorite {
            AppReviewPrompt.requestAfterFavoriteIfNeeded(favoriteCount: favoriteIDs.count)
        }

        // Only the English Saved tab shows the colophon, so only it asks for location.
        guard isFavorite, AppLanguage.isEnglish else { return }
        if let place = locationProvider.inscriptionPlace {
            ClassicPoemFavorites.recordPlace(place, for: poem.id)
        } else {
            locationProvider.requestCityIfNeeded()
        }
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

private struct DetailSectionTitle: View {
    @Environment(\.poemTypeface) private var typeface
    @Environment(\.poemScript) private var script
    let title: String

    var body: some View {
        HStack(spacing: 9) {
            Rectangle()
                .fill(ClassicPalette.cinnabar)
                .frame(width: 3, height: 18)
            Text(title.poemScript(script))
                .font(typeface.titleFont)
                .foregroundStyle(ClassicPalette.ink)
        }
    }
}

private struct DetailSection: View {
    @Environment(\.poemTypeface) private var typeface
    @Environment(\.poemScript) private var script
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            DetailSectionTitle(title: title)
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

struct PoemMusicCreditsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.poemTypeface) private var typeface
    @Environment(\.poemScript) private var script

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(AppLanguage.copy("以下配乐均来自 Pixabay，依 Pixabay 内容许可免费使用。为统一音量，已做响度调整并转码为 M4A。感谢各位作者。", "All tracks come from Pixabay and are used under the Pixabay Content License. They have been loudness-matched and converted to M4A. Thanks to every creator."))
                        .font(typeface.bodyFont)
                        .foregroundStyle(ClassicPalette.mutedInk)
                        .lineSpacing(5)
                }

                Section(AppLanguage.copy("曲目与作者", "Tracks and creators")) {
                    ForEach(PoemMusicTrack.all) { track in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(track.localizedTitle.poemScript(script))
                                .font(typeface.bodyFont)
                                .foregroundStyle(ClassicPalette.ink)
                            Text(AppLanguage.copy("原曲：", "Original: ") + track.originalTitle + " · " + track.author)
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
