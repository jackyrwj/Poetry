import Foundation

struct ClassicPoem: Identifiable, Hashable, Codable, Sendable {
    enum Origin: String, Codable, Sendable {
        case curated
        case tangShiThreeHundred
        case songCiThreeHundred
        case poetrySpring
    }

    let id: String
    let title: String
    let author: String
    let dynasty: String
    let form: String
    let lines: [String]
    let appreciation: String?
    let translation: String?
    let tags: [String]
    let backgroundRawValue: String
    let origin: Origin

    var background: PoemBackground {
        PoemBackground(rawValue: backgroundRawValue) ?? .defaultBackground
    }

    var backgroundImageName: String {
        background.imageName ?? PoemBackground.defaultBackground.rawValue
    }

    var searchableText: String {
        ([title, author, dynasty, form] + lines + tags).joined(separator: " ")
    }
}

private struct EnglishClassicPoemContent {
    let title: String
    let author: String
    let dynasty: String
    let form: String
    let translation: String
    let appreciation: String
    let tags: [String]
}

extension ClassicPoem {
    private var englishContent: EnglishClassicPoemContent? {
        guard origin == .curated else { return nil }
        return Self.englishCuratedContent[id]
    }

    /// The editorial English title, if one exists for this poem.
    var englishTitle: String? {
        guard AppLanguage.isEnglish else { return nil }
        return englishContent?.title ?? EnglishClassicPoemTitleLibrary.value(for: id)
    }

    var localizedTitle: String {
        AppLanguage.isEnglish ? englishTitle ?? title : title
    }

    var localizedAuthor: String {
        guard AppLanguage.isEnglish else { return author }
        return englishContent?.author ?? author.romanizedChinese
    }

    var localizedDynasty: String {
        guard AppLanguage.isEnglish else { return dynasty }
        if let value = englishContent?.dynasty { return value }
        switch dynasty {
        case "唐": return "Tang dynasty"
        case "宋": return "Song dynasty"
        default: return dynasty.romanizedChinese
        }
    }

    var localizedForm: String {
        guard AppLanguage.isEnglish else { return form }
        if let value = englishContent?.form { return value }
        if origin == .songCiThreeHundred { return "Ci lyric" }
        switch form.poemScript(.simplified) {
        case "五言古诗": return "Five-character old-style verse"
        case "七言古诗": return "Seven-character old-style verse"
        case "五言乐府": return "Five-character yuefu"
        case "七言乐府": return "Seven-character yuefu"
        case "五言律诗": return "Five-character regulated verse"
        case "七言律诗": return "Seven-character regulated verse"
        case "五言绝句": return "Five-character quatrain"
        case "七言绝句": return "Seven-character quatrain"
        case "词": return "Ci lyric"
        default: return form.romanizedChinese
        }
    }

    var localizedAttribution: String {
        "\(localizedDynasty) · \(localizedAuthor) · \(localizedForm)"
    }

    var localizedTranslation: String? {
        guard AppLanguage.isEnglish else { return translation }
        return englishContent?.translation ?? EnglishClassicPoemTranslationLibrary.value(for: id)
    }

    var localizedAppreciation: String? {
        guard AppLanguage.isEnglish else { return appreciation }
        return englishContent?.appreciation ?? EnglishClassicPoemCommentaryLibrary.value(for: id)
    }

    var localizedTags: [String] {
        guard AppLanguage.isEnglish else { return tags }
        if let values = englishContent?.tags { return values }
        switch origin {
        case .tangShiThreeHundred:
            return ["Tang Poems Three Hundred", localizedForm]
        case .songCiThreeHundred:
            return ["Song Lyrics Three Hundred", localizedForm]
        case .poetrySpring:
            return [localizedForm]
        case .curated:
            return tags
        }
    }

    private static let englishCuratedContent: [String: EnglishClassicPoemContent] = [
        "curated-唐-李白-静夜思": .init(
            title: "Quiet Night Thoughts", author: "Li Bai", dynasty: "Tang dynasty", form: "Five-character quatrain",
            translation: "Before my bed, the moonlight shines—could it be frost upon the ground? I lift my head to watch the bright moon, then lower it and think of home.",
            appreciation: "The poem begins with cool moonlight and turns two ordinary gestures—looking up and looking down—into a sudden movement between distance and longing. Its plain language leaves a lasting hush.",
            tags: ["Moon", "Homesickness", "Night"]
        ),
        "curated-唐-孟浩然-春晓": .init(
            title: "Spring Dawn", author: "Meng Haoran", dynasty: "Tang dynasty", form: "Five-character quatrain",
            translation: "Sleeping deeply in spring, I did not notice dawn. Everywhere I hear birds calling. I remember the wind and rain last night—how many flowers must have fallen?",
            appreciation: "Instead of painting spring directly, the poem begins with waking and listening. Birdsong brings brightness, while the imagined fallen flowers add a delicate note of regret.",
            tags: ["Spring", "Flowers", "Passing time"]
        ),
        "curated-唐-王之涣-登鹳雀楼": .init(
            title: "Ascending Stork Tower", author: "Wang Zhihuan", dynasty: "Tang dynasty", form: "Five-character quatrain",
            translation: "The sun sets against the mountains; the Yellow River flows into the sea. To see a thousand miles farther, climb one more storey.",
            appreciation: "The first couplet opens onto a vast landscape. The second turns that view into an invitation: physical ascent becomes a way of enlarging the mind.",
            tags: ["Ascent", "Yellow River", "Ambition"]
        ),
        "curated-唐-柳宗元-江雪": .init(
            title: "River Snow", author: "Liu Zongyuan", dynasty: "Tang dynasty", form: "Five-character quatrain",
            translation: "From a thousand mountains, birds have vanished; on ten thousand paths, no human trace remains. In a lone boat, an old man in rain cape and bamboo hat fishes alone in the cold river snow.",
            appreciation: "The poem first empties the entire world, then narrows its gaze to one small boat. The solitary fisherman feels less like a scene of daily life than a portrait of inward resolve.",
            tags: ["Winter", "Solitude", "Snow"]
        ),
        "curated-唐-王维-竹里馆": .init(
            title: "Bamboo Lodge", author: "Wang Wei", dynasty: "Tang dynasty", form: "Five-character quatrain",
            translation: "Alone in the deep bamboo grove, I play my zither and whistle at length. No one knows I am here in the forest; only the bright moon comes to shine upon me.",
            appreciation: "Bamboo, music, a whistle, and moonlight create a quiet world complete in itself. The speaker is alone but not bereft: the moon becomes a companion.",
            tags: ["Bamboo", "Moon", "Retreat"]
        ),
        "curated-唐-王维-山居秋暝": .init(
            title: "Autumn Evening in the Mountains", author: "Wang Wei", dynasty: "Tang dynasty", form: "Five-character regulated verse",
            translation: "After fresh rain, the empty mountain enters evening and autumn is in the air. Moonlight shines through pines; clear springs flow over stones. Voices rise from bamboo as women return from washing, and lotus leaves stir as fishing boats drift down. Let spring blossoms fade—this mountain is still a place to remain.",
            appreciation: "Stillness gives way to gentle movement: moonlight, water, voices, and boats. Natural clarity and ordinary human life meet in a quiet affirmation of retreat.",
            tags: ["Autumn", "Landscape", "Retreat"]
        ),
        "curated-唐-李白-望庐山瀑布": .init(
            title: "Viewing the Waterfall at Mount Lu", author: "Li Bai", dynasty: "Tang dynasty", form: "Seven-character quatrain",
            translation: "Sunlight on Incense Burner Peak raises violet mist; from afar, the waterfall hangs before the river. Its flying torrent drops three thousand feet—perhaps the Milky Way has fallen from the ninth heaven.",
            appreciation: "Li Bai builds from violet haze to the vivid verb 'hang,' then lets the waterfall fall from heaven itself. The hyperbole carries real visual force.",
            tags: ["Waterfall", "Landscape", "Imagination"]
        ),
        "curated-唐-张继-枫桥夜泊": .init(
            title: "Mooring by Maple Bridge at Night", author: "Zhang Ji", dynasty: "Tang dynasty", form: "Seven-character quatrain",
            translation: "The moon sets; crows cry; frost fills the sky. Facing riverside maples and fishing lights, I lie awake in sorrow. From Cold Mountain Temple beyond Suzhou, the midnight bell reaches the traveller's boat.",
            appreciation: "Moonset, crows, frost, maples, and fishing lights unfold one after another. The bell crossing the darkness makes homesickness almost audible.",
            tags: ["Journey", "Night", "Temple bell"]
        ),
        "curated-宋-苏轼-题西林壁": .init(
            title: "Inscribed on the Wall of West Forest Temple", author: "Su Shi", dynasty: "Song dynasty", form: "Seven-character quatrain",
            translation: "Seen head-on, Mount Lu is a range; from the side, a peak. Near or far, high or low, it is never the same. I cannot know its true face only because I am within the mountain itself.",
            appreciation: "The poem begins with shifting views of Mount Lu and reaches a wider insight: being inside a situation can prevent us from seeing the whole. Perspective shapes judgement.",
            tags: ["Mount Lu", "Perspective", "Insight"]
        ),
        "curated-宋-苏轼-饮湖上初晴后雨·其二": .init(
            title: "West Lake: Clear After Rain, II", author: "Su Shi", dynasty: "Song dynasty", form: "Seven-character quatrain",
            translation: "On a clear day, West Lake's waters glitter beautifully; in rain, the mountains are misty and marvellous too. If West Lake were compared to Xi Shi, light or rich adornment would suit her equally well.",
            appreciation: "Clear water and rain-veiled mountains reveal two faces of West Lake. The comparison to Xi Shi celebrates not simply beauty, but a beauty at home in every change of weather.",
            tags: ["West Lake", "Rain", "Landscape"]
        ),
        "curated-宋-李清照-如梦令·常记溪亭日暮": .init(
            title: "Like a Dream: At the Creek Pavilion at Dusk", author: "Li Qingzhao", dynasty: "Song dynasty", form: "Ci lyric",
            translation: "I often remember that dusk at the creek pavilion, so drunk I forgot the way home. Returning by boat after the pleasure had run its course, I drifted by mistake into deep lotus blooms. Row, row—startling a whole sandbank of gulls and egrets into flight.",
            appreciation: "A small outing at dusk moves from happy intoxication to a lively scramble of oars. The repeated cry to row and the sudden birds bring sound and motion to the lotus pond.",
            tags: ["Lotus", "Youth", "Excursion"]
        ),
        "curated-宋-陆游-卜算子·咏梅": .init(
            title: "Divination Ode: Plum Blossom", author: "Lu You", dynasty: "Song dynasty", form: "Ci lyric",
            translation: "By a broken bridge beyond the post station, a plum blossom opens alone, untended. Dusk already brings sorrow; wind and rain add more. It does not strive for spring's favour, though other flowers may envy it. Even ground into dust, its fragrance remains unchanged.",
            appreciation: "The plum blossom stands by a deserted bridge through dusk and storm without competing for attention. Its lasting fragrance becomes an image of integrity that survives hardship.",
            tags: ["Plum blossom", "Integrity", "Storm"]
        )
    ]
}

extension String {
    /// Readable metadata fallback for Chinese names that do not yet have an editorial translation.
    var romanizedChinese: String {
        guard let latin = applyingTransform(.toLatin, reverse: false)?
            .applyingTransform(.stripDiacritics, reverse: false) else {
            return self
        }
        return latin
            .split(whereSeparator: { $0.isWhitespace })
            .map { $0.capitalized }
            .joined(separator: " ")
    }
}

private struct EnglishClassicPoemTitleResource: Decodable {
    let titles: [String: String]
}

/// English titles for the offline Tang Poems Three Hundred and Song Lyrics Three Hundred
/// collections, keyed by poem ID. The resource is loaded once so titles remain
/// available offline; generation asserts full coverage against the source JSONs.
enum EnglishClassicPoemTitleLibrary {
    private static let titles: [String: String] = {
        guard
            let url = Bundle.main.url(forResource: "ClassicPoemTitle-en", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let resource = try? JSONDecoder().decode(EnglishClassicPoemTitleResource.self, from: data)
        else {
            assertionFailure("ClassicPoemTitle-en.json is missing or invalid.")
            return [:]
        }
        return resource.titles
    }()

    static func value(for poemID: String) -> String? {
        titles[poemID]
    }
}

private struct EnglishClassicPoemCommentaryResource: Decodable {
    let commentaries: [String: String]
}

/// English editorial notes for the offline Tang Poems Three Hundred and Song Lyrics Three Hundred collections.
/// The resource is loaded once so the complete commentary library remains offline after installation.
enum EnglishClassicPoemCommentaryLibrary {
    private static let commentaries: [String: String] = {
        guard
            let url = Bundle.main.url(forResource: "ClassicPoemCommentary-en", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let resource = try? JSONDecoder().decode(EnglishClassicPoemCommentaryResource.self, from: data)
        else {
            assertionFailure("ClassicPoemCommentary-en.json is missing or invalid.")
            return [:]
        }
        return resource.commentaries
    }()

    static func value(for poemID: String) -> String? {
        commentaries[poemID]
    }
}

/// English translations for the offline Tang Poems Three Hundred and Song Lyrics Three Hundred collections.
/// The resource is loaded once so the complete translation library remains offline after installation.
enum EnglishClassicPoemTranslationLibrary {
    private static let translations: [String: String] = {
        guard
            let url = Bundle.main.url(forResource: "ClassicPoemTranslation-en", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let resource = try? JSONDecoder().decode(EnglishClassicPoemTranslationResource.self, from: data)
        else {
            assertionFailure("ClassicPoemTranslation-en.json is missing or invalid.")
            return [:]
        }
        return resource.translations
    }()

    static func value(for poemID: String) -> String? {
        translations[poemID]
    }
}

private struct EnglishClassicPoemTranslationResource: Decodable {
    let translations: [String: String]
}

enum ClassicPoemLibrary {
    static let featured: [ClassicPoem] = [
        poem(
            "静夜思", author: "李白", dynasty: "唐", form: "五言绝句",
            lines: ["床前明月光，疑是地上霜。", "举头望明月，低头思故乡。"],
            appreciation: "诗从月光落笔，把清冷的夜色与思乡之情叠在一起。“举头”与“低头”两个动作极其平常，却让遥望与归思在瞬间完成转折，语言浅白，余味悠长。",
            translation: "明亮的月光洒在床前，仿佛地上结了一层白霜。抬头望见明月，低下头便想起远方的故乡。",
            tags: ["明月", "思乡", "夜"], background: .moon
        ),
        poem(
            "春晓", author: "孟浩然", dynasty: "唐", form: "五言绝句",
            lines: ["春眠不觉晓，处处闻啼鸟。", "夜来风雨声，花落知多少。"],
            appreciation: "全诗没有正面铺陈春景，而从醒后的听觉与联想写起。鸟声带来春日的明快，昨夜风雨与未知的落花又添一层惜春之意，轻盈中藏着细微的惆怅。",
            translation: "春日酣睡，不知不觉天已亮了，四处都能听见鸟鸣。想起昨夜的风雨，不知道又有多少花被吹落。",
            tags: ["春", "花", "惜春"], background: .willow
        ),
        poem(
            "登鹳雀楼", author: "王之涣", dynasty: "唐", form: "五言绝句",
            lines: ["白日依山尽，黄河入海流。", "欲穷千里目，更上一层楼。"],
            appreciation: "前两句把落日、群山与黄河纳入阔大的视野，后两句由写景转为进取之意。空间的登高成为精神的提升，景、理自然相生，因此格外明朗有力。",
            translation: "夕阳依着群山渐渐沉落，黄河奔腾着流向大海。若想看尽更远的景色，就要再登上一层高楼。",
            tags: ["登高", "黄河", "励志"], background: .peaks
        ),
        poem(
            "江雪", author: "柳宗元", dynasty: "唐", form: "五言绝句",
            lines: ["千山鸟飞绝，万径人踪灭。", "孤舟蓑笠翁，独钓寒江雪。"],
            appreciation: "“千山”“万径”先写天地的空寂，再把视线收束到一叶孤舟。寒江独钓并非热闹的生活画面，而是诗人在严寒与孤独中仍守住自我的精神写照。",
            translation: "群山中看不到飞鸟，所有道路上也没有人的踪迹。只有披蓑戴笠的老人坐在孤舟上，独自在飘雪的寒江垂钓。",
            tags: ["冬", "孤独", "江雪"], background: .boat
        ),
        poem(
            "竹里馆", author: "王维", dynasty: "唐", form: "五言绝句",
            lines: ["独坐幽篁里，弹琴复长啸。", "深林人不知，明月来相照。"],
            appreciation: "幽竹、琴声、长啸与明月构成一个清寂自足的世界。诗人虽“独坐”，却并不孤苦；无人知晓时，明月成为知己，显出王维诗中宁静通透的禅意。",
            translation: "独自坐在幽深的竹林里，一边弹琴，一边放声长啸。深林中无人知道我在这里，只有明月静静照来。",
            tags: ["竹", "明月", "隐逸"], background: .bamboo
        ),
        poem(
            "山居秋暝", author: "王维", dynasty: "唐", form: "五言律诗",
            lines: ["空山新雨后，天气晚来秋。", "明月松间照，清泉石上流。", "竹喧归浣女，莲动下渔舟。", "随意春芳歇，王孙自可留。"],
            appreciation: "雨后空山由静入动：月光穿松、清泉过石，竹林人语与莲叶轻摇又带来生活气息。诗人把清幽自然与淳朴人情写在一起，也借“王孙可留”表达归隐山林的选择。",
            translation: "新雨过后，空山入夜，已能感到秋意。明月照在松林间，清泉从石上流过。竹林喧响，是洗衣女子归来；莲叶摇动，是渔舟顺流而下。任春花消歇，这样的秋山也值得久留。",
            tags: ["秋", "山水", "隐居"], background: .waterfall
        ),
        poem(
            "望庐山瀑布", author: "李白", dynasty: "唐", form: "七言绝句",
            lines: ["日照香炉生紫烟，遥看瀑布挂前川。", "飞流直下三千尺，疑是银河落九天。"],
            appreciation: "诗先以紫烟烘托香炉峰，再用一个“挂”字把瀑布写成横陈天际的白练。末句以银河自九天坠落作比，夸张却有真实的视觉冲击，体现李白奔放瑰丽的想象。",
            translation: "阳光照着香炉峰升起紫色云烟，远远望去，瀑布像挂在山川之前。水流从高处飞泻而下，让人怀疑是银河从九天落入人间。",
            tags: ["瀑布", "山水", "想象"], background: .waterfall
        ),
        poem(
            "枫桥夜泊", author: "张继", dynasty: "唐", form: "七言绝句",
            lines: ["月落乌啼霜满天，江枫渔火对愁眠。", "姑苏城外寒山寺，夜半钟声到客船。"],
            appreciation: "月落、乌啼、霜天、江枫与渔火连续铺开，视觉与听觉共同营造羁旅寒夜。结尾钟声越过夜色抵达客船，也把无形的乡愁写得可闻、可感。",
            translation: "月亮西沉，乌鸦啼叫，寒霜仿佛布满夜空。面对江边枫树与点点渔火，我满怀愁绪难以入眠。姑苏城外寒山寺的夜半钟声，传到了旅人的船上。",
            tags: ["羁旅", "夜", "钟声"], background: .bridge
        ),
        poem(
            "题西林壁", author: "苏轼", dynasty: "宋", form: "七言绝句",
            lines: ["横看成岭侧成峰，远近高低各不同。", "不识庐山真面目，只缘身在此山中。"],
            appreciation: "诗从观看庐山的不同角度写起，继而指出身处局中反而难见全貌。自然景观由此转化为认识事物的方法：位置与视角会塑造判断，想看清整体需要适当抽离。",
            translation: "从正面看是连绵山岭，从侧面看又成了高峰，远近高低所见各不相同。之所以认不清庐山真正的样子，只因为自己正身处山中。",
            tags: ["庐山", "哲理", "视角"], background: .peaks
        ),
        poem(
            "饮湖上初晴后雨·其二", author: "苏轼", dynasty: "宋", form: "七言绝句",
            lines: ["水光潋滟晴方好，山色空蒙雨亦奇。", "欲把西湖比西子，淡妆浓抹总相宜。"],
            appreciation: "晴日写水光，雨中写山色，西湖的两种面貌彼此映衬。以西施作比，不只在说美，更妙在“淡妆浓抹总相宜”：无论天气如何变化，西湖都有自然合宜的神韵。",
            translation: "晴天里西湖水波闪耀，景色正好；雨幕中远山迷蒙，也十分奇妙。若把西湖比作西施，无论淡妆还是浓妆都恰到好处。",
            tags: ["西湖", "雨", "写景"], background: .lotus
        ),
        poem(
            "如梦令·常记溪亭日暮", author: "李清照", dynasty: "宋", form: "词",
            lines: ["常记溪亭日暮，沉醉不知归路。", "兴尽晚回舟，误入藕花深处。", "争渡，争渡，惊起一滩鸥鹭。"],
            appreciation: "词以一次暮归小游为线索，从沉醉、迷路写到急切划船，节奏越来越轻快。“争渡”的重复与骤然飞起的鸥鹭，让静美荷塘一下充满声音和动作，显出少女时代的明朗意趣。",
            translation: "常想起在溪边亭子游玩到日暮，沉醉得忘了归路。尽兴后划船回去，却误入荷花深处。赶快划呀，赶快划呀，惊起了满滩的鸥鹭。",
            tags: ["荷花", "少女", "游兴"], background: .lotus
        ),
        poem(
            "卜算子·咏梅", author: "陆游", dynasty: "宋", form: "词",
            lines: ["驿外断桥边，寂寞开无主。", "已是黄昏独自愁，更著风和雨。", "无意苦争春，一任群芳妒。", "零落成泥碾作尘，只有香如故。"],
            appreciation: "梅花生在驿外断桥，经历黄昏风雨，却无意与群芳争春。下片由花写人：即使零落成泥，清香仍不改变，寄托了诗人在困顿中不改操守的品格。",
            translation: "驿站外的断桥边，梅花无人照料，独自开放。黄昏已令它忧愁，又遭风雨侵袭。它无意争占春光，任凭百花嫉妒；即使凋落成泥、被碾作尘，香气依旧如故。",
            tags: ["梅", "品格", "风雨"], background: .plum
        )
    ]

    static func localSearch(_ query: String) -> [ClassicPoem] {
        let key = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .poemScript(.simplified)
        let selected = mergedSelectedPoems
        guard !key.isEmpty else { return selected }
        return selected.filter { $0.searchableText.localizedCaseInsensitiveContains(key) }
    }

    /// Keeps the existing hand-curated entries first, then fills out the selection with Tang Poems Three Hundred.
    /// Curated versions win when the same title and author appear in both sources.
    private static var mergedSelectedPoems: [ClassicPoem] {
        var seen = Set<String>()
        return (featured + TangShiThreeHundredLibrary.poems).filter { poem in
            seen.insert("\(poem.title.poemScript(.simplified))|\(poem.author.poemScript(.simplified))").inserted
        }
    }

    private static func poem(
        _ title: String,
        author: String,
        dynasty: String,
        form: String,
        lines: [String],
        appreciation: String,
        translation: String,
        tags: [String],
        background: PoemBackground
    ) -> ClassicPoem {
        ClassicPoem(
            id: "curated-\(dynasty)-\(author)-\(title)",
            title: title,
            author: author,
            dynasty: dynasty,
            form: form,
            lines: lines,
            appreciation: appreciation,
            translation: translation,
            tags: tags,
            backgroundRawValue: background.rawValue,
            origin: .curated
        )
    }
}

enum ClassicPoemFavorites {
    private static let key = "classicPoemFavoriteIDs"
    private static let poemsKey = "classicPoemFavoriteItems"

    static func load() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
    }

    static func loadPoems() -> [ClassicPoem] {
        guard
            let data = UserDefaults.standard.data(forKey: poemsKey),
            let poems = try? JSONDecoder().decode([ClassicPoem].self, from: data)
        else { return [] }
        return poems
    }

    static func save(_ ids: Set<String>, including poem: ClassicPoem? = nil) {
        UserDefaults.standard.set(Array(ids).sorted(), forKey: key)

        var poems = Dictionary(uniqueKeysWithValues: loadPoems().map { ($0.id, $0) })
        if let poem, ids.contains(poem.id) {
            poems[poem.id] = poem
        }
        poems = poems.filter { ids.contains($0.key) }
        guard let data = try? JSONEncoder().encode(Array(poems.values)) else { return }
        UserDefaults.standard.set(data, forKey: poemsKey)
    }
}

enum ClassicAppreciationCache {
    private static let key = "classicPoemAIAppreciations"

    static func value(for poemID: String) -> String? {
        let values = load()
        let languageKey = "\(AppLanguage.isEnglish ? "en" : "zh"):\(poemID)"
        if let value = values[languageKey] { return value }
        // Older builds stored unqualified Chinese commentary by poem ID.
        return AppLanguage.isEnglish ? nil : values[poemID]
    }

    static func save(_ text: String, for poemID: String) {
        var values = load()
        values["\(AppLanguage.isEnglish ? "en" : "zh"):\(poemID)"] = text
        guard let data = try? JSONEncoder().encode(values) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private static func load() -> [String: String] {
        guard
            let data = UserDefaults.standard.data(forKey: key),
            let values = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return values
    }
}
