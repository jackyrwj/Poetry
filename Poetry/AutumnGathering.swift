import SwiftUI

/// 秋日诗会: the October 2026 in-app event (App Store event "秋日诗会 2026").
/// The App Store event card deep-links here with `shike://autumn`.
enum AutumnGathering {
    /// The App Store event runs through October (Beijing time). The entry opens
    /// a few days early so App Review can reach it before the event starts.
    private static let window: DateInterval = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        let start = calendar.date(from: DateComponents(year: 2026, month: 9, day: 29)) ?? .distantFuture
        let end = calendar.date(from: DateComponents(year: 2026, month: 11, day: 1)) ?? .distantFuture
        return DateInterval(start: start, end: end)
    }()

    static func isActive(on date: Date = .now) -> Bool {
        #if DEBUG
        // Always on in debug builds so the page can be checked before October.
        return true
        #else
        return date >= window.start && date < window.end
        #endif
    }

    static func matches(_ url: URL) -> Bool {
        url.scheme == "shike" && url.host == "autumn"
    }

    /// From early autumn through 中秋 and 重阳 to late autumn. Matched by author
    /// and opening words: hand-edited editions replace some collection ids.
    private static let selections: [(author: String, opening: String)] = [
        ("王维", "空山新雨后"),
        ("杜牧", "银烛秋光冷画屏"),
        ("苏轼", "明月几时有"),
        ("王维", "独在异乡为异客"),
        ("李清照", "薄雾浓云愁永昼"),
        ("杜甫", "风急天高猿啸哀"),
        ("范仲淹", "碧云天"),
        ("王安石", "登临送目"),
        ("张继", "月落乌啼霜满天"),
        ("李商隐", "君问归期未有期"),
        ("柳永", "寒蝉凄切"),
        ("柳永", "对潇潇"),
        ("辛弃疾", "楚天千里清秋"),
        ("李清照", "寻寻觅觅")
    ]

    /// The event is free, so only poems anyone can read are included.
    static let poems: [ClassicPoem] = selections.compactMap { selection in
        ClassicPoemLibrary.allPoems.first { poem in
            poem.author == selection.author
                && poem.lines.joined().hasPrefix(selection.opening)
                && !poem.requiresMembership
        }
    }
}

private struct WriteAutumnPoemKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
    /// Switches to AI写诗. Unset where there is no composer (English).
    var writeAutumnPoem: (() -> Void)? {
        get { self[WriteAutumnPoemKey.self] }
        set { self[WriteAutumnPoemKey.self] = newValue }
    }
}

/// Shown on 赏诗 below the daily poem while the event runs.
struct AutumnGatheringCard: View {
    @Environment(\.poemTypeface) private var typeface
    @Environment(\.poemScript) private var script
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 14) {
                Image("autumn_gathering")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 92, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(AppLanguage.copy("秋日诗会", "Autumn Poetry Gathering").poemScript(script))
                            .font(typeface.smallFont)
                            .foregroundStyle(ClassicPalette.cinnabar)
                        Spacer(minLength: 8)
                        Text(AppLanguage.copy("十月限定", "October only").poemScript(script))
                            .font(typeface.smallFont)
                            .foregroundStyle(ClassicPalette.mutedInk)
                    }
                    Text(AppLanguage.copy("读一首秋诗，写一首自己的秋", "Autumn in classic verse").poemScript(script))
                        .font(typeface.bodyFont)
                        .foregroundStyle(ClassicPalette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text((AppLanguage.isEnglish
                          ? "\(AutumnGathering.poems.count) autumn poems"
                          : "\(AutumnGathering.poems.count) 首秋日诗词").poemScript(script))
                        .font(typeface.smallFont)
                        .foregroundStyle(ClassicPalette.mutedInk)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .background(.white.opacity(0.76), in: RoundedRectangle(cornerRadius: 19, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 19, style: .continuous)
                    .stroke(.white.opacity(0.72), lineWidth: 0.8)
            }
            .contentShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(AppLanguage.copy("打开秋日诗会", "Open the Autumn Poetry Gathering").poemScript(script))
    }
}

struct AutumnGatheringView: View {
    @Environment(\.poemTypeface) private var typeface
    @Environment(\.poemScript) private var script
    @Environment(\.dismiss) private var dismiss
    @Environment(\.writeAutumnPoem) private var writeAutumnPoem
    @Binding var favoriteIDs: Set<String>
    @Binding var path: [PoetRoute]

    var body: some View {
        ZStack {
            PaperBackground()

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 18) {
                    hero

                    if let writeAutumnPoem {
                        Button(action: writeAutumnPoem) {
                            Label("以秋为题，写一首诗".poemScript(script), systemImage: "wand.and.stars")
                                .font(typeface.bodyFont)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .background(ClassicPalette.cinnabar, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }

                    Text(AppLanguage.copy("秋日诗词", "Autumn poems").poemScript(script))
                        .font(typeface.titleFont)
                        .foregroundStyle(ClassicPalette.ink)
                        .padding(.top, 6)

                    ForEach(AutumnGathering.poems) { poem in
                        Button {
                            path.append(.poem(poem))
                        } label: {
                            ClassicPoemCard(poem: poem, isFavorite: favoriteIDs.contains(poem.id))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 36)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                CircleToolbarButton(systemName: "chevron.left") { dismiss() }
            }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image("autumn_gathering")
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
                .accessibilityHidden(true)

            Text(AppLanguage.copy("秋日诗会", "Autumn Poetry Gathering").poemScript(script))
                .font(typeface.font(size: 29))
                .foregroundStyle(ClassicPalette.ink)

            Text(AppLanguage.copy(
                "十月整月，从山居秋暝到重阳登高，再到枫桥夜泊，读古人笔下的秋山、秋江与秋夜。",
                "All October, read autumn as the classical poets saw it: rain-washed hills, the Double Ninth climb, a temple bell on a frosty night."
            ).poemScript(script))
                .font(typeface.smallFont)
                .foregroundStyle(ClassicPalette.mutedInk)
                .lineSpacing(4)
        }
    }
}
