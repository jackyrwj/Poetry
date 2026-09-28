import Foundation

/// Poem-of-the-day and recent-aware random poem selection over the offline corpus.
enum DailyPoemPicker {
    private static let recentKey = "recentRandomPoemIDs"
    private static let recentLimit = 20

    /// Full offline corpus, deduplicated by title + author.
    static let corpus: [ClassicPoem] = {
        var seen = Set<String>()
        return ClassicPoemLibrary.allPoems
            .filter { poem in
                seen.insert("\(poem.title.poemScript(.simplified))|\(poem.author.poemScript(.simplified))").inserted
            }
    }()

    /// A fixed, freely readable daily collection, independent of membership and filters.
    static let dailyPoems: [ClassicPoem] = {
        var rng = SeededRandomNumberGenerator(seed: "woven-verse-daily-cycle-v1")
        return corpus.filter { !$0.requiresMembership }.shuffled(using: &rng)
    }()

    /// Walk a shuffled cycle by local calendar day. Adjacent days never repeat
    /// when the collection has at least two poems, including at the cycle boundary.
    static func poem(on date: Date = .now, timeZone: TimeZone = .autoupdatingCurrent) -> ClassicPoem? {
        DailyPoemWidgetStore.cycleIndex(on: date, count: dailyPoems.count, timeZone: timeZone)
            .map { dailyPoems[$0] }
    }

    /// Avoid recent picks where possible, without falling back to locked works.
    static func random(
        in poems: [ClassicPoem] = corpus,
        hasPremiumAccess: Bool,
        excludingRecentIDs recentIDs: Set<String> = Set(loadRecentIDs())
    ) -> ClassicPoem? {
        let available = availablePoems(in: poems, hasPremiumAccess: hasPremiumAccess)
        let pool = available.filter { !recentIDs.contains($0.id) }
        guard let poem = (pool.isEmpty ? available : pool).randomElement() else { return nil }
        record(poem.id)
        return poem
    }

    private static func availablePoems(in poems: [ClassicPoem], hasPremiumAccess: Bool) -> [ClassicPoem] {
        poems.filter { hasPremiumAccess || !$0.requiresMembership }
    }

    static func loadRecentIDs() -> [String] {
        UserDefaults.standard.stringArray(forKey: recentKey) ?? []
    }

    private static func record(_ id: String) {
        var ids = loadRecentIDs()
        ids.removeAll { $0 == id }
        ids.insert(id, at: 0)
        if ids.count > recentLimit {
            ids = Array(ids.prefix(recentLimit))
        }
        UserDefaults.standard.set(ids, forKey: recentKey)
    }
}

/// Deterministic RNG (FNV-1a seed hash + xorshift64*) for the fixed daily cycle.
struct SeededRandomNumberGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: String) {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in seed.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        state = hash == 0 ? 0x9e3779b97f4a7c15 : hash
    }

    mutating func next() -> UInt64 {
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        return state &* 0x2545f4914f6cdd1d
    }
}

/// "Further reading" for the poem detail page, drawn only from the offline corpus:
/// the rest of the same set (其一、其二…), more by the same poet, and other
/// lyrics written to the same ci tune. Orders are fixed so a poem always shows
/// the same neighbours, but each poem starts from its own place in the list.
enum RelatedPoems {
    struct Series {
        struct Member {
            let number: Int
            let poem: ClassicPoem
        }

        let title: String
        let members: [Member]
    }

    struct Recommendations {
        var series: Series?
        var byAuthor: [ClassicPoem] = []
        var tune: String?
        var byTune: [ClassicPoem] = []

        var isEmpty: Bool { series == nil && byAuthor.isEmpty && byTune.isEmpty }
    }

    static func recommendations(for poem: ClassicPoem, prefersUnlocked: Bool, limit: Int = 3) -> Recommendations {
        var result = Recommendations()
        var shown: Set<String> = [identity(of: poem)]

        if let index = seriesIndex.byPoemID[poem.id] {
            let series = seriesIndex.all[index]
            result.series = series
            shown.formUnion(series.members.map { identity(of: $0.poem) })
        }

        let authorPool = authorIndex[poem.author.poemScript(.simplified)] ?? []
        result.byAuthor = Array(rotated(authorPool, after: poem).filter { !shown.contains(identity(of: $0)) }.prefix(limit))
        shown.formUnion(result.byAuthor.map(identity(of:)))

        if let tune = tuneName(of: poem) {
            let author = poem.author.poemScript(.simplified)
            // Other poets first: the point is hearing how different hands fill the same tune.
            let candidates = rotated(tuneIndex[tune] ?? [], after: poem)
                .filter { !shown.contains(identity(of: $0)) }
                .enumerated()
                .sorted { lhs, rhs in
                    let l = rank(lhs.element, author: author, prefersUnlocked: prefersUnlocked)
                    let r = rank(rhs.element, author: author, prefersUnlocked: prefersUnlocked)
                    return l == r ? lhs.offset < rhs.offset : l < r
                }
                .map(\.element)
            result.tune = tune
            result.byTune = Array(candidates.prefix(limit))
        }

        return result
    }

    static func chineseNumeral(_ number: Int) -> String {
        let digits = ["", "一", "二", "三", "四", "五", "六", "七", "八", "九", "十"]
        return digits.indices.contains(number) ? digits[number] : "\(number)"
    }

    // MARK: - Indexes

    /// Unlike the shared corpus, this keeps same-titled poems within a
    /// library (李商隐 has two 无题二首 sets).
    private static let pool: [ClassicPoem] = ClassicPoemLibrary.allPoems

    private static let seriesIndex: (byPoemID: [String: Int], all: [Series]) = {
        var groups: [(title: String, members: [Series.Member])] = []
        var latestGroup: [String: Int] = [:]

        for poem in pool {
            guard let position = seriesPosition(of: poem.title.poemScript(.simplified)) else { continue }
            let key = "\(poem.author.poemScript(.simplified))|\(position.title)"
            // 之一 opens a new run, so two sets sharing a title (李商隐's two 无题二首) stay apart.
            if position.number == 1 || latestGroup[key] == nil {
                groups.append((position.title, []))
                latestGroup[key] = groups.count - 1
            }
            groups[latestGroup[key]!].members.append(.init(number: position.number, poem: poem))
        }

        var byPoemID: [String: Int] = [:]
        var all: [Series] = []
        for group in groups where group.members.count > 1 {
            for member in group.members { byPoemID[member.poem.id] = all.count }
            all.append(Series(title: group.title, members: group.members.sorted { $0.number < $1.number }))
        }
        return (byPoemID, all)
    }()

    private static let authorIndex: [String: [ClassicPoem]] =
        Dictionary(grouping: pool) { $0.author.poemScript(.simplified) }

    private static let tuneIndex: [String: [ClassicPoem]] = {
        var index: [String: [ClassicPoem]] = [:]
        for poem in pool {
            if let tune = tuneName(of: poem) { index[tune, default: []].append(poem) }
        }
        return index
    }()

    // MARK: - Helpers

    private static let numerals: [Character: Int] = ["一": 1, "二": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9, "十": 10]

    /// "咏怀古迹五首之三" → ("咏怀古迹五首", 3); "饮湖上初晴后雨·其二" → ("饮湖上初晴后雨", 2).
    private static func seriesPosition(of title: String) -> (title: String, number: Int)? {
        if let match = title.wholeMatch(of: /(.+首)之([一二三四五六七八九十])/),
           let number = numerals[Character(String(match.2))] {
            return (String(match.1), number)
        }
        if let match = title.wholeMatch(of: /(.+)[·・]其([一二三四五六七八九十])/),
           let number = numerals[Character(String(match.2))] {
            return (String(match.1), number)
        }
        return nil
    }

    /// Song lyrics carry their tune as the form; curated lyrics as "如梦令·常记溪亭日暮".
    private static func tuneName(of poem: ClassicPoem) -> String? {
        if poem.origin == .songCiThreeHundred { return poem.form.poemScript(.simplified) }
        guard poem.form.poemScript(.simplified) == "词" else { return nil }
        let title = poem.title.poemScript(.simplified)
        return title.split(whereSeparator: { $0 == "·" || $0 == "・" }).first.map(String.init)
    }

    private static func identity(of poem: ClassicPoem) -> String {
        "\(poem.title.poemScript(.simplified))|\(poem.author.poemScript(.simplified))"
    }

    /// The pool starting just after `poem`, wrapping around.
    private static func rotated(_ pool: [ClassicPoem], after poem: ClassicPoem) -> [ClassicPoem] {
        let key = identity(of: poem)
        guard let index = pool.firstIndex(where: { identity(of: $0) == key }) else { return pool }
        return Array(pool[(index + 1)...] + pool[..<index])
    }

    private static func rank(_ poem: ClassicPoem, author: String, prefersUnlocked: Bool) -> Int {
        let sameAuthor = poem.author.poemScript(.simplified) == author ? 1 : 0
        let locked = prefersUnlocked && poem.requiresMembership ? 2 : 0
        return locked + sameAuthor
    }
}
