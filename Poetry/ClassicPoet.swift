import Foundation

struct ClassicPoet: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let dynasty: String
    let avatarAsset: String?
    let introduction: String
    let collectionTitle: String?
    let requiresMembership: Bool

    var poems: [ClassicPoem] {
        let curated = ClassicPoemLibrary.featured.filter { $0.author == name }
        let tangShi = TangShiThreeHundredLibrary.poems.filter { $0.author == name }
        let songCi = SongCiThreeHundredLibrary.poems.filter { $0.author == name }
        var seen = Set<String>()
        return (curated + tangShi + songCi).filter { poem in
            seen.insert("\(poem.title)|\(poem.author)").inserted
        }
    }
}

extension ClassicPoet {
    private static let englishProfiles: [String: (name: String, introduction: String)] = [
        "李白": ("Li Bai", "A High Tang poet known for unrestrained imagination and a sweeping, luminous vision of mountains, moonlight, and human aspiration. Later readers called him the Poet Immortal."),
        "孟浩然": ("Meng Haoran", "A High Tang poet of landscape and rural life. His poems often hold dawn, spring rain, and village scenes in language that is clear, quiet, and lingering."),
        "王之涣": ("Wang Zhihuan", "A High Tang poet whose work often looks toward frontiers and high places. In only a few lines, he creates vast landscapes and an expansive spirit."),
        "柳宗元": ("Liu Zongyuan", "A Tang writer and poet whose landscapes are spare and cool. Solitude in nature often carries his sense of inner independence and resolve."),
        "王维": ("Wang Wei", "A High Tang poet and painter. His landscape poems are tranquil and spacious, often bringing pictorial clarity and a contemplative stillness together."),
        "张继": ("Zhang Ji", "A Tang poet remembered for catching night scenes, bells, and a traveller's longing. His 'Mooring by Maple Bridge at Night' is especially celebrated."),
        "苏轼": ("Su Shi", "A Northern Song writer, poet, and lyricist whose work ranges widely—from open-hearted grandeur to clear-eyed attention to daily life."),
        "李清照": ("Li Qingzhao", "A Song lyricist whose early poems are light and vivid, while her later work grows deep and restrained. Her language is elegant, precise, and emotionally resonant."),
        "陆游": ("Lu You", "A Southern Song poet of great range and abundance. He writes of country and conscience as well as ordinary life; his plum-blossom poems are known for steadfastness."),
        "杜甫": ("Du Fu", "A Tang poet who recorded his age and its people with moral force, while writing deeply of landscape, friendship, family, and a sense of home."),
        "白居易": ("Bai Juyi", "A Mid-Tang poet whose direct language carries deep feeling. He writes of social life, the scenery of Jiangnan, friendship, and life's changing seasons."),
        "王昌龄": ("Wang Changling", "A High Tang poet known for powerful frontier poems as well as finely felt poems of separation and longing."),
        "李商隐": ("Li Shangyin", "A Late Tang poet of oblique, richly suggestive verse, often using night rain, autumn sound, curtains, and grasses to hold what cannot be said directly."),
        "柳永": ("Liu Yong", "A Northern Song lyricist who writes expansively of travel, city life, and parting. His flowing melodies make everyday experience feel enduring."),
        "辛弃疾": ("Xin Qiji", "A Southern Song lyricist whose work intertwines patriotic ambition, frustration, and the quiet pleasures of country life."),
        "刘禹锡": ("Liu Yuxi", "A Mid-Tang poet of clear, resilient verse. His poems move between historical reflection, landscape, and a lively confidence in renewal."),
        "杜牧": ("Du Mu", "A late Tang poet known for elegant, lucid verse. Autumn landscapes, history, travel, and the pleasures of the world often meet in his work."),
        "王勃": ("Wang Bo", "An early Tang poet whose youthful brilliance gives landscape and parting a wide, resonant emotional horizon."),
        "韩愈": ("Han Yu", "A Tang prose master and poet whose writing is direct, forceful, and principled, often turning landscape into a test of character."),
        "高适": ("Gao Shi", "A Tang frontier poet whose spacious, weathered verse joins military life, friendship, and the hard clarity of travel."),
        "岑参": ("Cen Shen", "A Tang frontier poet celebrated for vivid snow, desert, and military landscapes, rendered with alertness and adventurous energy."),
        "范仲淹": ("Fan Zhongyan", "A Northern Song statesman and writer whose work joins public responsibility with broad landscapes and steady moral feeling."),
        "欧阳修": ("Ouyang Xiu", "A Northern Song essayist, poet, and lyricist whose writing is generous and observant, equally at home in public life and quiet nature."),
        "王安石": ("Wang Anshi", "A Northern Song statesman and poet whose spare, searching verse carries a firm intelligence and a determined attention to the world."),
        "秦观": ("Qin Guan", "A Northern Song lyricist of delicate emotional precision. His poems and lyrics hold moonlight, travel, and parting in a tender, lingering register.")
    ]

    var localizedName: String {
        guard AppLanguage.isEnglish else { return name }
        return Self.englishProfiles[name]?.name ?? name.romanizedChinese
    }

    var localizedDynasty: String {
        guard AppLanguage.isEnglish else { return dynasty }
        switch dynasty {
        case "唐": return "Tang"
        case "宋": return "Song"
        default: return dynasty
        }
    }

    var localizedIntroduction: String {
        guard AppLanguage.isEnglish else { return introduction }
        if let profile = Self.englishProfiles[name] { return profile.introduction }
        if collectionTitle == SongCiThreeHundredLibrary.collectionTitle {
            return "A writer represented in Song Lyrics Three Hundred, with \(poems.count) works included in this collection."
        }
        if collectionTitle == TangShiThreeHundredLibrary.collectionTitle {
            return "A poet represented in Tang Poems Three Hundred, with \(poems.count) works included in this collection."
        }
        return introduction
    }

    var localizedCollectionTitle: String? {
        guard let collectionTitle else { return nil }
        guard AppLanguage.isEnglish else { return collectionTitle }
        switch collectionTitle {
        case TangShiThreeHundredLibrary.collectionTitle:
            return "Tang Poems Three Hundred"
        case SongCiThreeHundredLibrary.collectionTitle:
            return "Song Lyrics Three Hundred"
        default:
            return collectionTitle
        }
    }
}

enum ClassicPoetLibrary {
    static let featured: [ClassicPoet] = [
        poet(
            "李白", dynasty: "唐", avatar: "poet_li_bai",
            introduction: "盛唐诗人。诗风豪迈飘逸，善以奔放的想象写山河、明月与人生意气，后世称其为“诗仙”。",
            requiresMembership: false
        ),
        poet(
            "孟浩然", dynasty: "唐", avatar: "poet_meng_haoran",
            introduction: "盛唐山水田园诗人。笔下常见清晨、春雨与村野生活，语言自然清淡，情味含蓄悠长。"
        ),
        poet(
            "王之涣", dynasty: "唐", avatar: "poet_wang_zhihuan",
            introduction: "盛唐诗人。作品多写边塞与登临，气象开阔，寥寥数语便能写出壮阔山河与昂扬胸襟。"
        ),
        poet(
            "柳宗元", dynasty: "唐", avatar: "poet_liu_zongyuan",
            introduction: "唐代文学家、诗人。山水诗清峭幽冷，常把孤寂处境与独立不屈的精神寄托于自然景物。"
        ),
        poet(
            "王维", dynasty: "唐", avatar: "poet_wang_wei",
            introduction: "盛唐诗人、画家。山水田园诗宁静空灵，诗中有画，也常流露澄澈自足的禅意。"
        ),
        poet(
            "张继", dynasty: "唐", avatar: "poet_zhang_ji",
            introduction: "唐代诗人。善于在羁旅行役中捕捉夜色、钟声与客愁，《枫桥夜泊》尤为传诵。"
        ),
        poet(
            "苏轼", dynasty: "宋", avatar: "poet_su_shi",
            introduction: "北宋文学家、诗人、词人。作品题材开阔，既有旷达豪放的胸襟，也有细腻明澈的生活意趣。"
        ),
        poet(
            "李清照", dynasty: "宋", avatar: "poet_li_qingzhao",
            introduction: "宋代词人。早期词作明快灵动，后期沉郁深婉，善用清丽精炼的语言写细微而深长的情感。"
        ),
        poet(
            "陆游", dynasty: "宋", avatar: "poet_lu_you",
            introduction: "南宋诗人。诗作数量丰厚，既心系家国，也善写日常生活；咏梅之作尤见坚贞自守的品格。"
        ),
        poet(
            "杜甫", dynasty: "唐", avatar: "poet_du_fu",
            introduction: "唐代诗人。以沉郁顿挫的笔力记录时代与民生，也在山河、亲友与日常中寄托深厚的家国情怀。"
        ),
        poet(
            "白居易", dynasty: "唐", avatar: "poet_bai_juyi",
            introduction: "中唐诗人。语言平易而情感深厚，既关怀民生，也善写江南风物、亲友情谊与人生况味。"
        ),
        poet(
            "王昌龄", dynasty: "唐", avatar: "poet_wang_changling",
            introduction: "盛唐诗人。边塞诗气骨雄健，闺怨与送别诗又清丽深婉，常在开阔意境中见细腻情思。"
        ),
        poet(
            "李商隐", dynasty: "唐", avatar: "poet_li_shangyin",
            introduction: "晚唐诗人。诗意幽微含蓄，善以夜雨、秋声、帘幕与芳草寄托难言的相思和身世之感。"
        ),
        poet(
            "柳永", dynasty: "宋", avatar: "poet_liu_yong",
            introduction: "北宋词人。长于铺写羁旅、都市与离情，词调婉转舒缓，把寻常人生写得绵长动人。"
        ),
        poet(
            "辛弃疾", dynasty: "宋", avatar: "poet_xin_qiji",
            introduction: "南宋词人。词中兼有报国壮志、沉郁不平与乡村闲适，豪放与婉约在笔下彼此交织。"
        ),
        poet(
            "刘禹锡", dynasty: "唐", avatar: "poet_liu_yuxi",
            introduction: "中唐诗人。诗风清峻而有生气，常在怀古、山水与日常景物中写出对世事更新的坚定信念。"
        ),
        poet(
            "杜牧", dynasty: "唐", avatar: "poet_du_mu",
            introduction: "晚唐诗人。诗歌明丽俊爽，秋景、怀古、行旅与人事在笔下交织，既有风流情致，也有历史感怀。"
        ),
        poet(
            "王勃", dynasty: "唐", avatar: "poet_wang_bo",
            introduction: "初唐诗人。才情早发，善以开阔的山河意象承载送别、怀人和身世之感，气象清新高远。"
        ),
        poet(
            "韩愈", dynasty: "唐", avatar: "poet_han_yu",
            introduction: "唐代文学家、诗人。文章气势雄健，诗歌直抒胸臆，常把山水、人生与坚守原则的精神写得峻拔有力。"
        ),
        poet(
            "高适", dynasty: "唐", avatar: "poet_gao_shi",
            introduction: "盛唐边塞诗人。诗中有边地风尘、军旅见闻与朋友情谊，语言苍劲开阔，带着历尽世事的沉着。"
        ),
        poet(
            "岑参", dynasty: "唐", avatar: "poet_cen_shen",
            introduction: "盛唐边塞诗人。善写雪山、沙漠与军营中的奇景，想象瑰丽，笔调明快而富有行旅的冒险精神。"
        ),
        poet(
            "范仲淹", dynasty: "宋", avatar: "poet_fan_zhongyan",
            introduction: "北宋政治家、文学家。作品兼有忧乐天下的担当与开阔沉着的山河之思，气象端正而深厚。"
        ),
        poet(
            "欧阳修", dynasty: "宋", avatar: "poet_ou_yang_xiu",
            introduction: "北宋文学家、诗人、词人。文章平易舒展，诗词既写山水风物，也写士大夫日常中的旷达与温厚。"
        ),
        poet(
            "王安石", dynasty: "宋", avatar: "poet_wang_an_shi",
            introduction: "北宋政治家、文学家。诗歌精炼峭拔，常在山川与日常景物中寄寓清醒、坚定而富有思辨的精神。"
        ),
        poet(
            "秦观", dynasty: "宋", avatar: "poet_qin_guan",
            introduction: "北宋词人。词风清丽婉约，善写月色、杨柳、羁旅与离情，情绪细密而余韵悠长。"
        )
    ]

    static let tangShiThreeHundred: [ClassicPoet] = {
        let featuredNames = Set(featured.map(\.name))
        return TangShiThreeHundredLibrary.authors
            .filter { !featuredNames.contains($0) }
            .map { name in
                ClassicPoet(
                    id: "唐-\(name)",
                    name: name,
                    dynasty: "唐",
                    avatarAsset: nil,
                    introduction: "《唐诗三百首》收录诗人，现收录 \(TangShiThreeHundredLibrary.poems.filter { $0.author == name }.count) 首作品。",
                    collectionTitle: TangShiThreeHundredLibrary.collectionTitle,
                    requiresMembership: true
                )
            }
    }()

    static let songCiThreeHundred: [ClassicPoet] = {
        let featuredNames = Set(featured.map(\.name))
        return SongCiThreeHundredLibrary.authors
            .filter { !featuredNames.contains($0) }
            .map { name in
                ClassicPoet(
                    id: "宋-\(name)",
                    name: name,
                    dynasty: "宋",
                    avatarAsset: nil,
                    introduction: "《宋词三百首》收录词人，现收录 \(SongCiThreeHundredLibrary.poems.filter { $0.author == name }.count) 阕作品。",
                    collectionTitle: SongCiThreeHundredLibrary.collectionTitle,
                    requiresMembership: true
                )
            }
    }()

    private static func poet(
        _ name: String,
        dynasty: String,
        avatar: String?,
        introduction: String,
        collectionTitle: String? = nil,
        requiresMembership: Bool = true
    ) -> ClassicPoet {
        ClassicPoet(
            id: "\(dynasty)-\(name)",
            name: name,
            dynasty: dynasty,
            avatarAsset: avatar,
            introduction: introduction,
            collectionTitle: collectionTitle,
            requiresMembership: requiresMembership
        )
    }
}
