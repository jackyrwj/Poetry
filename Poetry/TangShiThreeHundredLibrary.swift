import Foundation

/// An offline edition of the Tang Poems Three Hundred collection.
/// The source edition contains 319 entries because several grouped works are split into individual poems.
enum TangShiThreeHundredLibrary {
    static let collectionTitle = "唐诗三百首"

    static let poems: [ClassicPoem] = loadPoems()

    static let forms: [String] = [
        "五言古诗", "七言古诗", "五言乐府", "七言乐府",
        "五言律诗", "七言律诗", "五言绝句", "七言绝句"
    ]

    static var authors: [String] {
        Array(Set(poems.map(\.author))).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    static func search(_ query: String, form: String? = nil) -> [ClassicPoem] {
        let key = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .poemScript(.simplified)

        return poems.filter { poem in
            let matchesForm = form == nil || poem.form == form
            let matchesQuery = key.isEmpty || poem.searchableText
                .poemScript(.simplified)
                .localizedCaseInsensitiveContains(key)
            return matchesForm && matchesQuery
        }
    }

    private static func loadPoems() -> [ClassicPoem] {
        guard
            let url = Bundle.main.url(forResource: "TangShiThreeHundred", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let entries = try? JSONDecoder().decode([Entry].self, from: data)
        else {
            assertionFailure("TangShiThreeHundred.json is missing or invalid.")
            return []
        }

        return entries.map { entry in
            ClassicPoem(
                id: "tangshi-300-\(entry.id)",
                title: entry.title,
                author: entry.author,
                dynasty: "唐",
                form: entry.type,
                lines: entry.contents
                    .split(separator: "\n")
                    .map(String.init)
                    .filter { !$0.isEmpty },
                appreciation: nil,
                translation: nil,
                tags: [collectionTitle, entry.type],
                backgroundRawValue: PoemBackground.suggested(for: entry.contents).rawValue,
                origin: .tangShiThreeHundred
            )
        }
    }

}

private struct Entry: Decodable {
    let id: Int
    let contents: String
    let type: String
    let author: String
    let title: String
}
