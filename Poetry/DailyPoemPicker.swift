import Foundation

/// Poem-of-the-day and recent-aware random poem selection over the offline corpus.
enum DailyPoemPicker {
    private static let recentKey = "recentRandomPoemIDs"
    private static let recentLimit = 20

    /// Full offline corpus, deduplicated by title + author.
    static let corpus: [ClassicPoem] = {
        var seen = Set<String>()
        return (ClassicPoemLibrary.featured + TangShiThreeHundredLibrary.poems + SongCiThreeHundredLibrary.poems)
            .filter { poem in
                seen.insert("\(poem.title.poemScript(.simplified))|\(poem.author.poemScript(.simplified))").inserted
            }
    }()

    /// A fixed, freely readable daily collection, independent of membership and filters.
    private static let dailyPoems: [ClassicPoem] = {
        var rng = SeededRandomNumberGenerator(seed: "woven-verse-daily-cycle-v1")
        return corpus.filter { !$0.requiresMembership }.shuffled(using: &rng)
    }()

    /// Walk a shuffled cycle by local calendar day. Adjacent days never repeat
    /// when the collection has at least two poems, including at the cycle boundary.
    static func poem(on date: Date = .now, timeZone: TimeZone = .autoupdatingCurrent) -> ClassicPoem? {
        guard !dailyPoems.isEmpty else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard let epoch = calendar.date(from: DateComponents(year: 2001, month: 1, day: 1)),
              let day = calendar.dateComponents([.day], from: epoch, to: calendar.startOfDay(for: date)).day
        else { return nil }
        let index = ((day % dailyPoems.count) + dailyPoems.count) % dailyPoems.count
        return dailyPoems[index]
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
