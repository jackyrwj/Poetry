import SwiftUI

enum PoetRoute: Hashable {
    case poet(ClassicPoet)
    case poem(ClassicPoem)
}

struct PoetGalleryView: View {
    @AppStorage(PoemTypeface.storageKey) private var typefaceRawValue = PoemTypeface.kaiti.rawValue
    @AppStorage(PoemScript.storageKey) private var scriptRawValue = PoemScript.simplified.rawValue
    @State private var favoriteIDs = ClassicPoemFavorites.load()
    @State private var showsSettings = false
    @State private var path: [PoetRoute] = []
    @State private var pendingPoet: ClassicPoet?
    @State private var showsPaywall = false
    @State private var scrollPosition: String?
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool
    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    private var typeface: PoemTypeface {
        PoemTypeface(rawValue: typefaceRawValue) ?? .kaiti
    }

    private var script: PoemScript {
        PoemScript(rawValue: scriptRawValue) ?? .simplified
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                PaperBackground()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        header
                            .id("poets-header")

                        searchField
                            .id("poets-search")

                        if !filteredFeatured.isEmpty {
                            LazyVGrid(columns: columns, spacing: 16) {
                                ForEach(filteredFeatured) { poet in
                                    Button { openProfile(for: poet) } label: {
                                        PoetGridCard(poet: poet)
                                    }
                                    .buttonStyle(.plain)
                                    .id(poet.id)
                                }
                            }
                        }

                        ForEach(filteredTang) { poet in
                            Button { openProfile(for: poet) } label: {
                                CollectionPoetRow(poet: poet)
                            }
                            .buttonStyle(.plain)
                            .id(poet.id)
                        }

                        if !filteredSong.isEmpty {
                            collectionHeader(
                                title: AppLanguage.copy("宋词三百首词人", "Writers in Song Lyrics Three Hundred"),
                                count: filteredSong.count,
                                countLabel: AppLanguage.isEnglish ? "writers" : "位"
                            )
                            .id("poets-song-title")

                            ForEach(filteredSong) { poet in
                                Button { openProfile(for: poet) } label: {
                                    CollectionPoetRow(poet: poet)
                                }
                                .buttonStyle(.plain)
                                .id(poet.id)
                            }
                        }

                        if showsEmptySearchResult {
                            Text(AppLanguage.copy("未找到相关诗人", "No poets found").poemScript(script))
                                .font(typeface.smallFont)
                                .foregroundStyle(ClassicPalette.mutedInk)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 40)
                        }

                        Text(AppLanguage.copy("名家头像为艺术化创作，并非历史人物真实画像。", "Portraits are artistic interpretations, not historical likenesses.").poemScript(script))
                            .font(typeface.smallFont)
                            .foregroundStyle(ClassicPalette.mutedInk.opacity(0.7))
                            .frame(maxWidth: .infinity)
                            .padding(.top, 4)
                            .id("poets-footer")
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, 22)
                    .padding(.top, 20)
                    .padding(.bottom, 36)
                }
                .scrollPosition(id: $scrollPosition)
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
                    if let pendingPoet {
                        path.append(.poet(pendingPoet))
                        self.pendingPoet = nil
                    }
                }
            }
        }
        .environment(\.poemTypeface, typeface)
        .environment(\.poemScript, script)
        .tint(ClassicPalette.cinnabar)
    }

    private var searchQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredFeatured: [ClassicPoet] {
        ClassicPoetLibrary.featured.filter(matchesSearch)
    }

    private var filteredTang: [ClassicPoet] {
        ClassicPoetLibrary.tangShiThreeHundred.filter(matchesSearch)
    }

    private var filteredSong: [ClassicPoet] {
        ClassicPoetLibrary.songCiThreeHundred.filter(matchesSearch)
    }

    private var showsEmptySearchResult: Bool {
        !searchQuery.isEmpty && filteredFeatured.isEmpty && filteredTang.isEmpty && filteredSong.isEmpty
    }

    private func matchesSearch(_ poet: ClassicPoet) -> Bool {
        guard !searchQuery.isEmpty else { return true }
        let query = searchQuery.localizedLowercase
        return poet.name.localizedLowercase.contains(query)
            || poet.localizedName.localizedLowercase.contains(query)
            || poet.localizedIntroduction.localizedLowercase.contains(query)
            || (poet.localizedBiography ?? "").localizedLowercase.contains(query)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(ClassicPalette.mutedInk)
            TextField(AppLanguage.copy("搜索诗人", "Search poets").poemScript(script), text: $searchText)
                .font(typeface.smallFont)
                .foregroundStyle(ClassicPalette.ink)
                .autocorrectionDisabled()
                .focused($isSearchFocused)
                .submitLabel(.search)
                .onSubmit {
                    isSearchFocused = false
                }
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(ClassicPalette.mutedInk.opacity(0.7))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(AppLanguage.copy("清除搜索", "Clear search").poemScript(script))
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 38)
        .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.white.opacity(0.78), lineWidth: 0.8)
        }
        .accessibilityLabel(AppLanguage.copy("搜索诗人", "Search poets").poemScript(script))
        .onChange(of: searchText) { oldValue, newValue in
            if !oldValue.isEmpty && newValue.isEmpty {
                isSearchFocused = false
            }
        }
    }

    private func collectionHeader(title: String, count: Int, countLabel: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title.poemScript(script))
                .font(typeface.titleFont)
                .foregroundStyle(ClassicPalette.ink)
            Spacer()
            Text("\(count) \(countLabel)".poemScript(script))
                .font(typeface.smallFont)
                .foregroundStyle(ClassicPalette.mutedInk)
        }
    }

    private func openProfile(for poet: ClassicPoet) {
        guard !poet.requiresMembership || StoreManager.shared.isPremium else {
            pendingPoet = poet
            showsPaywall = true
            return
        }
        path.append(.poet(poet))
    }

    private var header: some View {
        HStack(alignment: .center) {
            Text(AppLanguage.copy("诗人", "Poets").poemScript(script))
                .font(typeface.font(size: 29))
                .foregroundStyle(ClassicPalette.ink)

            Spacer()

            SettingsButton {
                showsSettings = true
            }
        }
    }
}

private struct PoetGridCard: View {
    @Environment(\.poemTypeface) private var typeface
    @Environment(\.poemScript) private var script
    @ObservedObject private var store = StoreManager.shared
    let poet: ClassicPoet

    private var isLocked: Bool {
        poet.requiresMembership && !store.isPremium
    }

    var body: some View {
        VStack(spacing: 12) {
            if let avatarAsset = poet.avatarAsset {
                Image(avatarAsset)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(Circle())
                    .overlay {
                        Circle().stroke(.white.opacity(0.9), lineWidth: 2)
                    }
                    .shadow(color: .black.opacity(0.1), radius: 12, y: 7)
            }

            if isLocked, !AppLanguage.isEnglish {
                Label(AppLanguage.copy("雅集", "Pro").poemScript(script), systemImage: "lock.fill")
                    .font(typeface.tinySealFont)
                    .foregroundStyle(ClassicPalette.cinnabar)
            }

            VStack(spacing: 4) {
                Text(poet.localizedName.poemScript(script))
                    .font(typeface.font(size: 20))
                    .foregroundStyle(ClassicPalette.ink)
                Text(AppLanguage.isEnglish ? "\(poet.poems.count) works" : "收录 \(poet.poems.count) 首".poemScript(script))
                    .font(typeface.smallFont)
                    .foregroundStyle(ClassicPalette.mutedInk)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(0.78), lineWidth: 0.8)
        }
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(alignment: .topTrailing) {
            if isLocked, AppLanguage.isEnglish {
                PremiumCrownBadge()
                    .padding(10)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(AppLanguage.isEnglish ? "\(poet.localizedName), \(poet.poems.count) works\(isLocked ? ", members only" : "")" : "诗人\(poet.name)，收录\(poet.poems.count)首作品".poemScript(script))
    }
}

private struct CollectionPoetRow: View {
    @Environment(\.poemTypeface) private var typeface
    @Environment(\.poemScript) private var script
    @ObservedObject private var store = StoreManager.shared
    let poet: ClassicPoet

    private var isLocked: Bool {
        poet.requiresMembership && !store.isPremium
    }

    var body: some View {
        HStack(spacing: 14) {
            Text(poet.localizedName.poemScript(script))
                .font(typeface.font(size: 20))
                .foregroundStyle(ClassicPalette.ink)
                .frame(width: 76, alignment: .leading)
            Text(AppLanguage.isEnglish ? "\(poet.poems.count) works" : "收录 \(poet.poems.count) 首".poemScript(script))
                .font(typeface.smallFont)
                .foregroundStyle(ClassicPalette.mutedInk)
            Spacer()
            if isLocked {
                Image(systemName: "lock.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ClassicPalette.cinnabar.opacity(0.8))
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ClassicPalette.mutedInk.opacity(0.6))
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 54)
        .background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.8), lineWidth: 0.8)
        }
        .accessibilityLabel(AppLanguage.isEnglish ? "\(poet.localizedName), \(poet.poems.count) works" : "诗人\(poet.name)，收录\(poet.poems.count)首作品".poemScript(script))
    }
}

struct PoetDetailView: View {
    @Environment(\.poemTypeface) private var typeface
    @Environment(\.poemScript) private var script
    @Environment(\.dismiss) private var dismiss
    let poet: ClassicPoet
    @Binding var favoriteIDs: Set<String>
    @Binding var path: [PoetRoute]

    var body: some View {
        ZStack {
            PaperBackground()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    poetHeader

                    if let biography = poet.localizedBiography {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(AppLanguage.copy("生平", "Life").poemScript(script))
                                .font(typeface.titleFont)
                                .foregroundStyle(ClassicPalette.ink)

                            Text(biography.poemScript(script))
                                .font(typeface.bodyFont)
                                .foregroundStyle(ClassicPalette.mutedInk)
                                .lineSpacing(7)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(18)
                                .background(.white.opacity(0.76), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        }
                    }

                    Text(AppLanguage.copy("收录作品", "Works in this collection").poemScript(script))
                        .font(typeface.titleFont)
                        .foregroundStyle(ClassicPalette.ink)

                    ForEach(poet.poems) { poem in
                        Button {
                            path.append(.poem(poem))
                        } label: {
                            ClassicPoemCard(poem: poem, isFavorite: favoriteIDs.contains(poem.id))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 18)
                .padding(.bottom, 40)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                CircleToolbarButton(systemName: "chevron.left") { dismiss() }
            }
        }
    }

    private var poetHeader: some View {
        VStack(spacing: 16) {
            if let avatarAsset = poet.avatarAsset {
                Image(avatarAsset)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 176, height: 176)
                    .clipShape(Circle())
                    .overlay {
                        Circle().stroke(.white.opacity(0.92), lineWidth: 3)
                    }
                    .shadow(color: .black.opacity(0.12), radius: 18, y: 10)
            } else {
                Image(systemName: "text.book.closed")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(ClassicPalette.cinnabar)
                    .frame(width: 112, height: 112)
                    .background(.white.opacity(0.68), in: Circle())
            }

            VStack(spacing: 6) {
                Text(poet.localizedName.poemScript(script))
                    .font(typeface.font(size: 30))
                    .foregroundStyle(ClassicPalette.ink)
                if poet.avatarAsset == nil {
                    Text((AppLanguage.isEnglish
                        ? (poet.localizedCollectionTitle ?? poet.collectionTitle ?? "")
                        : "\(poet.collectionTitle == SongCiThreeHundredLibrary.collectionTitle ? "词人" : "诗人") · \(poet.collectionTitle ?? TangShiThreeHundredLibrary.collectionTitle)").poemScript(script))
                        .font(typeface.smallFont)
                        .foregroundStyle(ClassicPalette.mutedInk)
                }

                if let lifeSpan = poet.localizedLifeSpan {
                    Text([lifeSpan, poet.localizedCourtesyName].compactMap { $0 }.joined(separator: " · ").poemScript(script))
                        .font(typeface.smallFont)
                        .foregroundStyle(ClassicPalette.mutedInk.opacity(0.85))
                        .multilineTextAlignment(.center)
                }
            }

            Text(poet.localizedIntroduction.poemScript(script))
                .font(typeface.bodyFont)
                .foregroundStyle(ClassicPalette.mutedInk)
                .lineSpacing(7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .background(.white.opacity(0.76), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }
}

#Preview("诗人") {
    PoetGalleryView()
}
