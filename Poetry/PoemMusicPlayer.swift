import AVFoundation
import Foundation

struct PoemMusicTrack: Identifiable, Hashable {
    let id: String
    let resourceName: String
    let zhTitle: String
    let enTitle: String
    let zhSubtitle: String
    let enSubtitle: String
    let originalTitle: String
    let author: String
    let sourceURL: URL

    var localizedTitle: String { AppLanguage.copy(zhTitle, enTitle) }
    var localizedSubtitle: String { AppLanguage.copy(zhSubtitle, enSubtitle) }

    static let farewell = PoemMusicTrack(
        id: "farewell",
        resourceName: "farewell_huangshan",
        zhTitle: "离愁",
        enTitle: "Parting",
        zhSubtitle: "二胡 · 送别与离情",
        enSubtitle: "Erhu · Farewells and parting",
        originalTitle: "Huangshan Mountain",
        author: "ED-MusicProductions",
        sourceURL: URL(string: "https://pixabay.com/music/adventure-huangshan-mountain-402302/")!
    )
    static let moonlit = PoemMusicTrack(
        id: "moonlit",
        resourceName: "moonlit_flute_serenade",
        zhTitle: "月夜",
        enTitle: "Moonlit Night",
        zhSubtitle: "竹笛 · 月色与乡思",
        enSubtitle: "Bamboo flute · Moonlight and home",
        originalTitle: "Chinese Flute Serenade",
        author: "NourishedByMusic",
        sourceURL: URL(string: "https://pixabay.com/music/world-chinese-flute-serenade-147545/")!
    )
    static let frontier = PoemMusicTrack(
        id: "frontier",
        resourceName: "frontier_china_nature",
        zhTitle: "边塞",
        enTitle: "Frontier",
        zhSubtitle: "笛与弦 · 大漠与关山",
        enSubtitle: "Flute and strings · Deserts and passes",
        originalTitle: "China Nature",
        author: "Abydos_Music",
        sourceURL: URL(string: "https://pixabay.com/music/china-china-nature-199638/")!
    )
    static let river = PoemMusicTrack(
        id: "river",
        resourceName: "river_peaceful_morning",
        zhTitle: "江舟",
        enTitle: "River Boat",
        zhSubtitle: "古筝、琵琶 · 江湖与舟行",
        enSubtitle: "Guzheng and pipa · Rivers and boats",
        originalTitle: "A Peaceful Morning",
        author: "kaazoom",
        sourceURL: URL(string: "https://pixabay.com/music/folk-a-peaceful-morning-traditional-chinese-style-folk-music-129024/")!
    )
    static let hermit = PoemMusicTrack(
        id: "hermit",
        resourceName: "hermit_chinese_relaxing",
        zhTitle: "山居",
        enTitle: "Mountain Retreat",
        zhSubtitle: "民乐 · 山水与隐逸",
        enSubtitle: "Folk instruments · Hills and seclusion",
        originalTitle: "Chinese Relaxing",
        author: "Villatic_Music",
        sourceURL: URL(string: "https://pixabay.com/music/world-chinese-relaxing-asian-meditation-traditional-music-285376/")!
    )
    static let spring = PoemMusicTrack(
        id: "spring",
        resourceName: "spring_new_year_flute",
        zhTitle: "春日",
        enTitle: "Spring Day",
        zhSubtitle: "竹笛 · 明快与生机",
        enSubtitle: "Bamboo flute · Brightness and new life",
        originalTitle: "Chinese New Year Flute",
        author: "NourishedByMusic",
        sourceURL: URL(string: "https://pixabay.com/music/china-chinese-new-year-flute-190421/")!
    )
    static let autumn = PoemMusicTrack(
        id: "autumn",
        resourceName: "autumn_ink_not_yet_dry",
        zhTitle: "秋思",
        enTitle: "Autumn Thoughts",
        zhSubtitle: "弦与管 · 悲秋与怀远",
        enSubtitle: "Strings and winds · Autumn longing",
        originalTitle: "墨未干，人已远 (Ink Not Yet Dry, The Person Already Gone)",
        author: "AiCanvas",
        sourceURL: URL(string: "https://pixabay.com/music/modern-classical-%E5%A2%A8%E6%9C%AA%E5%B9%B2%E4%BA%BA%E5%B7%B2%E8%BF%9C-ink-not-yet-dry-the-person-already-gone-491635/")!
    )
    static let snow = PoemMusicTrack(
        id: "snow",
        resourceName: "snow_silent_valley",
        zhTitle: "寒雪",
        enTitle: "Winter Snow",
        zhSubtitle: "竹笛 · 清寒与孤高",
        enSubtitle: "Bamboo flute · Cold air and solitude",
        originalTitle: "Flute of the Silent Valley",
        author: "djovan",
        sourceURL: URL(string: "https://pixabay.com/music/ambient-flute-of-the-silent-valley-497085/")!
    )

    static let all = [farewell, moonlit, frontier, river, hermit, spring, autumn, snow]

    static func recommended(for poem: ClassicPoem) -> PoemMusicTrack {
        // The title carries the clearest intent (送别、塞下、秋思…), so it wins
        // over the background image, which only reflects the scenery.
        let title = poem.title
        if ["送", "别", "赠"].contains(where: title.contains) { return farewell }
        if ["塞", "关", "征", "戍", "从军", "凉州"].contains(where: title.contains) { return frontier }
        if title.contains("秋") { return autumn }
        if title.contains("雪") { return snow }
        if title.contains("春") { return spring }
        if title.contains("月") { return moonlit }

        switch poem.background {
        case .boat, .lotus, .bridge:
            return river
        case .rain, .autumn:
            return autumn
        case .lamp, .moon:
            return moonlit
        case .frontier:
            return frontier
        case .willow:
            return farewell
        case .spring:
            return spring
        case .plum, .snow:
            return snow
        case .waterfall, .peaks, .pavilion, .bamboo, .none:
            return hermit
        }
    }
}

final class PoemMusicPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var activeTrack: PoemMusicTrack?
    @Published private(set) var isPlaying = false
    @Published private(set) var errorMessage: String?

    private static let volume: Float = 0.8
    private var player: AVAudioPlayer?

    func toggle(_ track: PoemMusicTrack) {
        guard activeTrack?.id == track.id else {
            play(track)
            return
        }

        if isPlaying {
            pause()
        } else {
            resume()
        }
    }

    func play(_ track: PoemMusicTrack) {
        guard let url = Bundle.main.url(forResource: track.resourceName, withExtension: "m4a") else {
            errorMessage = AppLanguage.copy("配乐暂时无法播放。", "This track is unavailable right now.")
            return
        }

        do {
            // `.ambient` is silenced by the ring/silent switch, so a tap on play
            // produced no sound on muted phones. Playback is always user-initiated.
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)

            let newPlayer = try AVAudioPlayer(contentsOf: url)
            newPlayer.delegate = self
            newPlayer.volume = 0
            newPlayer.numberOfLoops = -1
            newPlayer.prepareToPlay()
            newPlayer.play()
            newPlayer.setVolume(Self.volume, fadeDuration: 2.5)
            player = newPlayer
            activeTrack = track
            isPlaying = true
            errorMessage = nil
        } catch {
            player = nil
            activeTrack = nil
            isPlaying = false
            errorMessage = AppLanguage.copy("配乐暂时无法播放。", "This track is unavailable right now.")
        }
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func stop() {
        player?.stop()
        player = nil
        activeTrack = nil
        isPlaying = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.isPlaying = false
        }
    }

    private func resume() {
        guard player?.play() == true else {
            if let activeTrack { play(activeTrack) }
            return
        }
        isPlaying = true
        errorMessage = nil
    }
}
