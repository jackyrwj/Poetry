import Foundation

/// An offline edition of the Song Ci Three Hundred collection.
/// The source edition contains 280 entries.
enum SongCiThreeHundredLibrary {
    static let collectionTitle = "宋词三百首"

    static let poems: [ClassicPoem] = loadPoems()

    static var forms: [String] {
        Array(Set(poems.map(\.form))).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    static var authors: [String] {
        Array(Set(poems.map(\.author))).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private static func loadPoems() -> [ClassicPoem] {
        guard
            let url = Bundle.main.url(forResource: "SongCiThreeHundred", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let entries = try? JSONDecoder().decode([Entry].self, from: data)
        else {
            assertionFailure("SongCiThreeHundred.json is missing or invalid.")
            return []
        }

        return entries.enumerated().map { index, entry in
            ClassicPoem(
                id: "songci-300-\(index + 1)",
                title: entry.rhythmic,
                author: entry.author,
                dynasty: "宋",
                form: entry.rhythmic,
                lines: entry.paragraphs,
                appreciation: nil,
                translation: nil,
                tags: Array(Set([collectionTitle] + entry.tags)).sorted(),
                backgroundRawValue: PoemBackground.suggested(for: entry.paragraphs.joined()).rawValue,
                origin: .songCiThreeHundred
            )
        }
    }

}

private struct Entry: Decodable {
    let author: String
    let paragraphs: [String]
    let rhythmic: String
    let tags: [String]
}
