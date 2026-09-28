import AppIntents
import CoreText
import SwiftUI
import WidgetKit

@main
struct PoetryWidgetBundle: WidgetBundle {
    var body: some Widget {
        DailyPoemWidget()
    }
}

struct DailyPoemWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: DailyPoemWidgetStore.widgetKind,
            intent: SelectPoemIntent.self,
            provider: DailyPoemProvider()
        ) { entry in
            DailyPoemWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("每日一首")
        .description("每天一首唐诗宋词；也可以长按选择一首收藏的诗固定显示。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - Poem Selection

struct SelectPoemIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "选择诗词"
    static var description = IntentDescription("从收藏中选一首固定显示；不选则每天换一首。")

    @Parameter(title: "诗词")
    var poem: SavedPoemEntity?
}

struct SavedPoemEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "诗词")
    static var defaultQuery = SavedPoemQuery()

    let id: String
    let title: String
    let author: String
    let firstLine: String
    let avatar: String?

    init(_ poem: DailyPoemWidgetStore.Poem) {
        id = poem.id
        title = poem.englishTitle ?? poem.title
        author = poem.englishAuthor ?? poem.author
        firstLine = poem.lines.first ?? ""
        avatar = poem.avatar
    }

    var displayRepresentation: DisplayRepresentation {
        let subtitle: LocalizedStringResource = "\(author) · \(firstLine)"
        if let avatar, let url = DailyPoemWidgetStore.imageURL(named: avatar) {
            return DisplayRepresentation(title: "\(title)", subtitle: subtitle, image: .init(url: url))
        }
        return DisplayRepresentation(title: "\(title)", subtitle: subtitle)
    }
}

struct SavedPoemQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [SavedPoemEntity] {
        DailyPoemWidgetStore.readFavorites()
            .filter { identifiers.contains($0.id) }
            .map(SavedPoemEntity.init)
    }

    func entities(matching string: String) async throws -> [SavedPoemEntity] {
        let query = string.trimmingCharacters(in: .whitespaces).lowercased()
        return DailyPoemWidgetStore.readFavorites()
            .filter { poem in
                query.isEmpty || ([poem.title, poem.author, poem.englishTitle ?? "", poem.englishAuthor ?? ""] + poem.lines)
                    .contains { $0.lowercased().contains(query) }
            }
            .map(SavedPoemEntity.init)
    }

    func suggestedEntities() async throws -> [SavedPoemEntity] {
        DailyPoemWidgetStore.readFavorites().map(SavedPoemEntity.init)
    }
}

// MARK: - Timeline

struct DailyPoemProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> DailyPoemEntry {
        DailyPoemEntry(date: .now, poem: Self.samplePoem, fontName: nil, isEnglish: Self.systemIsEnglish)
    }

    func snapshot(for configuration: SelectPoemIntent, in context: Context) async -> DailyPoemEntry {
        entry(on: .now, pinnedID: configuration.poem?.id, family: context.family) ?? placeholder(in: context)
    }

    /// A pinned poem is a single entry. Otherwise one entry per day for a
    /// week, each starting at local midnight, so the poem turns over with the
    /// calendar even if the app is never opened.
    func timeline(for configuration: SelectPoemIntent, in context: Context) async -> Timeline<DailyPoemEntry> {
        if let pinnedID = configuration.poem?.id,
           let entry = entry(on: .now, pinnedID: pinnedID, family: context.family), entry.isPinned {
            return Timeline(entries: [entry], policy: .never)
        }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        var entries: [DailyPoemEntry] = []
        for offset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let entry = entry(on: offset == 0 ? .now : day, pinnedID: nil, family: context.family) else { continue }
            entries.append(entry)
        }
        guard !entries.isEmpty else {
            // The app hasn't written the cycle yet (not opened since installing).
            return Timeline(entries: [placeholder(in: context)], policy: .after(.now.addingTimeInterval(3600)))
        }
        return Timeline(entries: entries, policy: .atEnd)
    }

    /// A pinned poem that is no longer saved falls back to the daily poem.
    private func entry(on date: Date, pinnedID: String?, family: WidgetFamily) -> DailyPoemEntry? {
        guard let payload = DailyPoemWidgetStore.read() else { return nil }
        let pinned = pinnedID.flatMap { id in DailyPoemWidgetStore.readFavorites().first { $0.id == id } }
        guard let poem = pinned ?? DailyPoemWidgetStore.poem(on: date, in: payload) else { return nil }
        let fontName = payload.fontFile.flatMap { file in
            payload.fontName.flatMap { WidgetFonts.register(file: file, name: $0) }
        }
        // Lock Screen widgets are monochrome text; only Home Screen sizes load artwork.
        let showsArtwork = [.systemSmall, .systemMedium, .systemLarge].contains(family)
        let backgroundName = family == .systemMedium ? poem.landscapeBackground : poem.background
        return DailyPoemEntry(
            date: date,
            poem: poem,
            fontName: fontName,
            isEnglish: payload.isEnglish,
            isPinned: pinned != nil,
            background: showsArtwork ? image(named: backgroundName) : nil,
            avatar: showsArtwork ? image(named: poem.avatar) : nil
        )
    }

    private func image(named name: String?) -> UIImage? {
        guard let name, let url = DailyPoemWidgetStore.imageURL(named: name) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    private static let systemIsEnglish =
        Bundle.main.preferredLocalizations.first?.lowercased().hasPrefix("en") == true

    private static let samplePoem = DailyPoemWidgetStore.Poem(
        id: "curated-唐-李白-静夜思",
        title: "静夜思",
        author: "李白",
        dynasty: "唐",
        lines: ["床前明月光，疑是地上霜。", "举头望明月，低头思故乡。"],
        englishTitle: systemIsEnglish ? "Quiet Night Thoughts" : nil,
        englishAuthor: systemIsEnglish ? "Li Bai" : nil
    )
}

/// The typefaces ship inside the app; the widget registers the reader's one
/// from there rather than bundling another copy of the (large) font files.
enum WidgetFonts {
    private static var registered: Set<String> = []

    static func register(file: String, name: String) -> String? {
        if registered.contains(name) { return name }
        if UIFont(name: name, size: 12) != nil {
            registered.insert(name)
            return name
        }
        // …/诗客.app/PlugIns/PoetryWidget.appex → …/诗客.app
        let appURL = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
        let fontURL = appURL.appendingPathComponent(file)
        guard FileManager.default.fileExists(atPath: fontURL.path) else { return nil }
        CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, nil)
        guard UIFont(name: name, size: 12) != nil else { return nil }
        registered.insert(name)
        return name
    }
}

struct DailyPoemWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DailyPoemEntry

    var body: some View {
        DailyPoemWidgetView(entry: entry)
            .containerBackground(for: .widget) {
                DailyPoemWidgetBackground(entry: entry, family: family)
            }
    }
}
