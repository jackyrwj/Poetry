import Foundation

/// Data shared between the app and the 每日一首 widget through the App Group.
/// The app writes the whole daily cycle once (already in the reader's script),
/// so the widget can find any day's poem without the app being opened again.
enum DailyPoemWidgetStore {
    static let appGroupID = "group.com.raowenjie.Poetry"
    static let widgetKind = "DailyPoemWidget"
    static let urlScheme = "shike"

    struct Poem: Codable, Hashable {
        let id: String
        let title: String
        let author: String
        let dynasty: String
        let lines: [String]
        /// Shown instead of the Chinese title in English.
        let englishTitle: String?
        let englishAuthor: String?
        /// Asset names of the poem's ink painting (portrait / landscape) and
        /// the poet's portrait; the files live in `imageURL(named:)`.
        var background: String?
        var landscapeBackground: String?
        var avatar: String?
    }

    struct Payload: Codable, Equatable {
        var cycle: [Poem]
        /// Font file inside the app bundle and its PostScript name, following
        /// the reader's typeface in Settings.
        var fontFile: String?
        var fontName: String?
        var isEnglish: Bool
    }

    /// Day-by-day walk through a fixed cycle; shared with `DailyPoemPicker`
    /// so the widget and the Read tab always agree on today's poem.
    static func cycleIndex(on date: Date, count: Int, timeZone: TimeZone = .autoupdatingCurrent) -> Int? {
        guard count > 0 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard let epoch = calendar.date(from: DateComponents(year: 2001, month: 1, day: 1)),
              let day = calendar.dateComponents([.day], from: epoch, to: calendar.startOfDay(for: date)).day
        else { return nil }
        return ((day % count) + count) % count
    }

    static func poem(on date: Date, in payload: Payload) -> Poem? {
        cycleIndex(on: date, count: payload.cycle.count).map { payload.cycle[$0] }
    }

    static func poemURL(id: String) -> URL? {
        var components = URLComponents()
        components.scheme = urlScheme
        components.host = "poem"
        components.queryItems = [URLQueryItem(name: "id", value: id)]
        return components.url
    }

    static func poemID(from url: URL) -> String? {
        guard url.scheme == urlScheme, url.host == "poem" else { return nil }
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "id" }?.value
    }

    private static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    private static var fileURL: URL? {
        containerURL?.appendingPathComponent("daily-poems.json")
    }

    /// Downscaled copies of the app's artwork; bump the folder name to
    /// re-export after the artwork changes.
    static var imagesDirectory: URL? {
        containerURL?.appendingPathComponent("images-v1", isDirectory: true)
    }

    /// Paintings are opaque JPEGs; the round poet portraits keep their transparency.
    static func imageURL(named name: String) -> URL? {
        imagesDirectory?.appendingPathComponent(name.hasPrefix("poet_") ? "\(name).png" : "\(name).jpg")
    }

    private static var favoritesURL: URL? {
        containerURL?.appendingPathComponent("favorite-poems.json")
    }

    /// The reader's saved poems, newest first, for pinning one to a widget.
    static func readFavorites() -> [Poem] {
        guard let favoritesURL, let data = try? Data(contentsOf: favoritesURL) else { return [] }
        return (try? JSONDecoder().decode([Poem].self, from: data)) ?? []
    }

    @discardableResult
    static func writeFavorites(_ poems: [Poem]) -> Bool {
        guard let favoritesURL, readFavorites() != poems,
              let data = try? JSONEncoder().encode(poems) else { return false }
        return (try? data.write(to: favoritesURL, options: .atomic)) != nil
    }

    static func read() -> Payload? {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(Payload.self, from: data)
    }

    /// Returns false when nothing changed, so the caller can skip reloading timelines.
    @discardableResult
    static func write(_ payload: Payload) -> Bool {
        guard let fileURL, read() != payload,
              let data = try? JSONEncoder().encode(payload) else { return false }
        return (try? data.write(to: fileURL, options: .atomic)) != nil
    }
}
