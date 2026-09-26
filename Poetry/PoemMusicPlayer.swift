import AVFoundation
import Foundation

struct PoemMusicTrack: Identifiable, Hashable {
    let id: String
    let resourceName: String
    let title: String
    let subtitle: String
    let sourceURL: URL
    let license: String

    var localizedTitle: String {
        switch id {
        case "yangguan": return AppLanguage.copy(title, "Yangguan Sandie")
        case "zuiyu": return AppLanguage.copy(title, "Fisherman's Evening Song")
        case "pingsha": return AppLanguage.copy(title, "Wild Geese Descending on the Sandbank")
        case "liushui": return AppLanguage.copy(title, "Flowing Water")
        case "peilan": return AppLanguage.copy(title, "Fragrant Orchid")
        case "qiufeng": return AppLanguage.copy(title, "Song of the Autumn Wind")
        default: return title
        }
    }

    var localizedSubtitle: String {
        switch id {
        case "yangguan": return AppLanguage.copy(subtitle, "Guqin · Farewell and moonlit nights")
        case "zuiyu": return AppLanguage.copy(subtitle, "Guqin · River boats at dusk")
        case "pingsha": return AppLanguage.copy(subtitle, "Guqin · Open landscapes")
        case "liushui": return AppLanguage.copy(subtitle, "Guqin · Springs and waterfalls")
        case "peilan": return AppLanguage.copy(subtitle, "Guqin · Orchids and quiet retreat")
        case "qiufeng": return AppLanguage.copy(subtitle, "Qin song · Autumn longing")
        default: return subtitle
        }
    }

    static let yangguan = PoemMusicTrack(
        id: "yangguan",
        resourceName: "guqin_yangguan_sandie",
        title: "阳关三叠",
        subtitle: "古琴 · 送别与月夜",
        sourceURL: URL(string: "https://commons.wikimedia.org/wiki/File:Guqin-Yangguan_Sandie.ogg")!,
        license: "CC BY-SA 3.0 / GFDL"
    )
    static let zuiyu = PoemMusicTrack(
        id: "zuiyu",
        resourceName: "guqin_zuiyu_changwan",
        title: "醉渔唱晚",
        subtitle: "古琴 · 江舟与暮色",
        sourceURL: URL(string: "https://commons.wikimedia.org/wiki/File:Guqin-Zuiyu_Changwan.ogg")!,
        license: "CC BY-SA 3.0"
    )
    static let pingsha = PoemMusicTrack(
        id: "pingsha",
        resourceName: "pingsha_luoyan",
        title: "平沙落雁",
        subtitle: "古琴 · 山水与旷远",
        sourceURL: URL(string: "https://commons.wikimedia.org/wiki/File:Pingsha_Luoyan.ogg")!,
        license: "CC BY-SA 3.0 / CC BY 2.5 / GFDL"
    )
    static let liuShui = PoemMusicTrack(
        id: "liushui",
        resourceName: "liu_shui",
        title: "流水",
        subtitle: "古琴 · 泉瀑与清流",
        sourceURL: URL(string: "https://commons.wikimedia.org/wiki/File:Liu_Shui.ogg")!,
        license: "CC BY 2.5 / CC BY-SA 3.0 / GFDL"
    )
    static let peiLan = PoemMusicTrack(
        id: "peilan",
        resourceName: "pei_lan",
        title: "佩兰",
        subtitle: "古琴 · 兰香与幽居",
        sourceURL: URL(string: "https://commons.wikimedia.org/wiki/File:Pei_Lan.ogg")!,
        license: "CC BY 2.5 / CC BY-SA 3.0 / GFDL"
    )
    static let qiuFeng = PoemMusicTrack(
        id: "qiufeng",
        resourceName: "qiu_feng_ci",
        title: "秋风词",
        subtitle: "琴歌 · 秋意与怀远",
        sourceURL: URL(string: "https://commons.wikimedia.org/wiki/File:Qiu_Feng_Ci.ogg")!,
        license: "CC BY 2.5 / CC BY-SA 3.0 / GFDL"
    )

    static let all = [yangguan, zuiyu, pingsha, liuShui, peiLan, qiuFeng]

    static func recommended(for poem: ClassicPoem) -> PoemMusicTrack {
        let poemText = ([poem.title] + poem.lines + poem.tags).joined()
        if poemText.contains("秋") { return qiuFeng }

        switch poem.background {
        case .boat, .lotus, .bridge:
            return zuiyu
        case .rain, .lamp:
            return yangguan
        case .autumn:
            return qiuFeng
        case .frontier:
            return pingsha
        case .waterfall:
            return liuShui
        case .plum, .bamboo, .pavilion, .willow, .spring:
            return peiLan
        case .moon, .snow:
            return yangguan
        case .peaks, .none:
            return pingsha
        }
    }
}

final class PoemMusicPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var activeTrack: PoemMusicTrack?
    @Published private(set) var isPlaying = false
    @Published private(set) var errorMessage: String?

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
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)

            let newPlayer = try AVAudioPlayer(contentsOf: url)
            newPlayer.delegate = self
            newPlayer.volume = 0.52
            newPlayer.prepareToPlay()
            newPlayer.play()
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
