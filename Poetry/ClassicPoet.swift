import Foundation

struct ClassicPoet: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let dynasty: String
    let avatarAsset: String?
    let introduction: String
    let lifeSpan: String?
    let courtesyName: String?
    let biography: String?
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
    private struct EnglishProfile {
        let name: String
        let lifeSpan: String?
        let courtesyName: String?
        let introduction: String
        let biography: String?
    }

    private static let englishProfiles: [String: EnglishProfile] = [
        "李白": EnglishProfile(
            name: "Li Bai",
            lifeSpan: "701–762",
            courtesyName: "Courtesy name Taibai, art name Qinglian Jushi",
            introduction: "A High Tang poet known for unrestrained imagination and a sweeping, luminous vision of mountains, moonlight, and human aspiration. Later readers called him the Poet Immortal.",
            biography: "Born in Suyab on the western frontier and raised in Sichuan, he entered Chang'an in the Tianbao era and served briefly at the Hanlin Academy before leaving to wander. Caught up in the An Lushan rebellion, he was exiled toward Yelang but pardoned en route; his later years were spent drifting through the southeast, and he died in Dangtu."
        ),
        "孟浩然": EnglishProfile(
            name: "Meng Haoran",
            lifeSpan: "689–740",
            courtesyName: "Courtesy name Haoran; known as Meng of Xiangyang",
            introduction: "A High Tang poet of landscape and rural life. His poems often hold dawn, spring rain, and village scenes in language that is clear, quiet, and lingering.",
            biography: "A native of Xiangyang who never held office, he withdrew to Lumen Mountain after failing the capital examination in his forties. He lived among fields and rivers with wine and poetry as companions, and counted Wang Wei and Li Bai among his friends."
        ),
        "王之涣": EnglishProfile(
            name: "Wang Zhihuan",
            lifeSpan: "688–742",
            courtesyName: "Courtesy name Jiling",
            introduction: "A High Tang poet whose work often looks toward frontiers and high places. In only a few lines, he creates vast landscapes and an expansive spirit.",
            biography: "From an official family of Jinyang, he resigned a county post after being slandered and wandered freely among mountains and rivers for some fifteen years, later serving as county magistrate of Wen'an until his death. Though few of his poems survive, his quatrains are celebrated for their vast, uplifting spirit."
        ),
        "柳宗元": EnglishProfile(
            name: "Liu Zongyuan",
            lifeSpan: "773–819",
            courtesyName: "Courtesy name Zihou; known as Liu Hedong",
            introduction: "A Tang writer and poet whose landscapes are spare and cool. Solitude in nature often carries his sense of inner independence and resolve.",
            biography: "A jinshi of the Zhenyuan era, he was demoted after the failed Yongzhen reform to a minor exile post in Yongzhou for ten years, then transferred to Liuzhou, where he died in office. With Han Yu he led the movement to revive ancient-style prose, and his landscape poems are cool, spare, and resolute."
        ),
        "王维": EnglishProfile(
            name: "Wang Wei",
            lifeSpan: "701–761",
            courtesyName: "Courtesy name Mojie, art name Mojie Jushi",
            introduction: "A High Tang poet and painter. His landscape poems are tranquil and spacious, often bringing pictorial clarity and a contemplative stillness together.",
            biography: "A jinshi of the Kaiyuan era, he rose to vice director of the right bureau and was forced to accept an office under the rebels during the An Lushan rebellion, then demoted after the restoration. He lived half in office, half in seclusion, grew devoutly Buddhist in his later years, and was also an accomplished painter and musician."
        ),
        "张继": EnglishProfile(
            name: "Zhang Ji",
            lifeSpan: nil,
            courtesyName: "Courtesy name Yisun",
            introduction: "A Tang poet remembered for catching night scenes, bells, and a traveller's longing. His 'Mooring by Maple Bridge at Night' is especially celebrated.",
            biography: "A jinshi of the Tianbao era from Xiangzhou, he fled to the Jiangnan region during the An Lushan rebellion, and his celebrated 'Mooring by Maple Bridge at Night' is traditionally dated to his sojourn in Suzhou. Little else of his life is recorded; his clear, remote quatrains are what survive."
        ),
        "苏轼": EnglishProfile(
            name: "Su Shi",
            lifeSpan: "1037–1101",
            courtesyName: "Courtesy name Zizhan, art name Dongpo Jushi",
            introduction: "A Northern Song writer, poet, and lyricist whose work ranges widely—from open-hearted grandeur to clear-eyed attention to daily life.",
            biography: "A jinshi of the Jiayou era, he was posted away after opposing Wang Anshi's reforms and later banished to Huangzhou in the Crow Terrace poetry trial. In his final years he was exiled still farther, to Huizhou and Danzhou; recalled under a new emperor, he died on the journey north at Changzhou. He stands as a master of poetry, lyric, prose, calligraphy, and painting alike."
        ),
        "李清照": EnglishProfile(
            name: "Li Qingzhao",
            lifeSpan: "c. 1084 – c. 1155",
            courtesyName: "Art name Yi'an Jushi",
            introduction: "A Song lyricist whose early poems are light and vivid, while her later work grows deep and restrained. Her language is elegant, precise, and emotionally resonant.",
            biography: "Born in Jinan, she enjoyed an early life of ease, collecting bronze inscriptions and paintings with her husband Zhao Mingcheng. The Jingkang catastrophe drove the court south; her husband died and her collection scattered, and her later years were marked by hardship. She held that the lyric is an art of its own."
        ),
        "陆游": EnglishProfile(
            name: "Lu You",
            lifeSpan: "1125–1210",
            courtesyName: "Courtesy name Wuquan, art name Fangweng",
            introduction: "A Southern Song poet of great range and abundance. He writes of country and conscience as well as ordinary life; his plum-blossom poems are known for steadfastness.",
            biography: "From Shanyin, he was blocked from office under the chancellor Qin Hui, received his jinshi by imperial favor under Emperor Xiaozong, and repeatedly pressed for war against the Jin, only to be sidelined by the peace faction. He spent his middle years in Sichuan and his last decades at home in Shanyin, leaving nearly ten thousand poems."
        ),
        "杜甫": EnglishProfile(
            name: "Du Fu",
            lifeSpan: "712–770",
            courtesyName: "Courtesy name Zimei; known as Du the Ministry Councillor",
            introduction: "A Tang poet who recorded his age and its people with moral force, while writing deeply of landscape, friendship, family, and a sense of home.",
            biography: "He failed the examinations of the Kaiyuan era and travelled widely, was trapped in Chang'an when the An Lushan rebellion broke out, then reached the emperor's temporary court and was made a remonstrator. He soon gave up office for Sichuan, built his thatched hut in Chengdu, and served under the governor Yan Wu. His last years were spent drifting through the Xiang river region, and he died aboard a boat."
        ),
        "白居易": EnglishProfile(
            name: "Bai Juyi",
            lifeSpan: "772–846",
            courtesyName: "Courtesy name Letian, art name Xiangshan Jushi",
            introduction: "A Mid-Tang poet whose direct language carries deep feeling. He writes of social life, the scenery of Jiangnan, friendship, and life's changing seasons.",
            biography: "A jinshi of the Zhenyuan era, he rose to Hanlin academician and was banished to a minor post in Jiangzhou for remonstrating too boldly. He later governed Zhongzhou, Hangzhou, and Suzhou, and retired in old age to Xiangshan in Luoyang as a ministry president emeritus."
        ),
        "王昌龄": EnglishProfile(
            name: "Wang Changling",
            lifeSpan: "698–c. 756",
            courtesyName: "Courtesy name Shaobo",
            introduction: "A High Tang poet known for powerful frontier poems as well as finely felt poems of separation and longing.",
            biography: "A jinshi of the Kaiyuan era, he served in a succession of minor county posts at Yanshui, Jiangning, and Longbiao—hence his familiar nicknames—and was killed by a prefect during the An Lushan rebellion. His seven-syllable quatrains were so esteemed that later readers called him the master of the form."
        ),
        "李商隐": EnglishProfile(
            name: "Li Shangyin",
            lifeSpan: "c. 813–858",
            courtesyName: "Courtesy name Yishan, art name Yuxi Sheng",
            introduction: "A Late Tang poet of oblique, richly suggestive verse, often using night rain, autumn sound, curtains, and grasses to hold what cannot be said directly.",
            biography: "A jinshi of the Kaicheng era, he was taken under the patronage of Linghu Chu early on, then married the daughter of the frontier commander Wang Maoyuan—an alliance that dragged him into the Niu–Li factional strife and stalled his career in petty posts. He spent his last years idle in Zhengzhou and died in Xingyang."
        ),
        "柳永": EnglishProfile(
            name: "Liu Yong",
            lifeSpan: "c. 987–c. 1053",
            courtesyName: "Originally named Sanbian, courtesy name Qingqing",
            introduction: "A Northern Song lyricist who writes expansively of travel, city life, and parting. His flowing melodies make everyday experience feel enduring.",
            biography: "From Chong'an, he wandered the pleasure quarters in his youth and repeatedly failed the examinations, changing his name to Yong before finally passing in the Jingyou era. He rose only to a minor office in charge of imperial farms, yet his lyrics—half refined, half vernacular—were sung everywhere, in what was said to be every place with a well."
        ),
        "辛弃疾": EnglishProfile(
            name: "Xin Qiji",
            lifeSpan: "1140–1207",
            courtesyName: "Courtesy name You'an, art name Jiaxuan",
            introduction: "A Southern Song lyricist whose work intertwines patriotic ambition, frustration, and the quiet pleasures of country life.",
            biography: "Born in Licheng under Jurchen rule, he raised an armed band against the Jin as a young man and rode south to join the Song. He served as a regional commissioner and built the Flying Tiger Corps, memorializing again and again for the recovery of the north, but the court left him in long idleness at Shangrao and Qianshan. His bold, generous lyrics pair him with Su Shi as 'Su and Xin'."
        ),
        "刘禹锡": EnglishProfile(
            name: "Liu Yuxi",
            lifeSpan: "772–842",
            courtesyName: "Courtesy name Mengde",
            introduction: "A Mid-Tang poet of clear, resilient verse. His poems move between historical reflection, landscape, and a lively confidence in renewal.",
            biography: "A jinshi of the Zhenyuan era, he was demoted to a remote post in Langzhou when the Yongzhen reform collapsed, then moved through a chain of provincial posts for nearly twenty years. In old age he was made a household companion to the heir apparent in Luoyang, exchanging poems with Bai Juyi."
        ),
        "杜牧": EnglishProfile(
            name: "Du Mu",
            lifeSpan: "803–852",
            courtesyName: "Courtesy name Muzhi, art name Fanchuan Jushi",
            introduction: "A late Tang poet known for elegant, lucid verse. Autumn landscapes, history, travel, and the pleasures of the world often meet in his work.",
            biography: "Grandson of the chief minister Du You, from the capital region. A jinshi of the Dahe era, he served as prefect of Huangzhou, Chizhou, and Muzhou and rose to vice minister before dying in office as a chief secretary. He is famed for his lucid, elegant seven-syllable quatrains and collected his prose in the Fanchuan Anthology."
        ),
        "王勃": EnglishProfile(
            name: "Wang Bo",
            lifeSpan: "650–676",
            courtesyName: "Courtesy name Zi'an",
            introduction: "An early Tang poet whose youthful brilliance gives landscape and parting a wide, resonant emotional horizon.",
            biography: "From Longmen, he passed the examination in the Linde era and briefly served in Guozhou before being dismissed. In 676, crossing the sea to visit his father, he drowned in fright and died at twenty-seven. Foremost of the Four Paragons of the early Tang, he is remembered above all for his 'Preface to the Pavilion of Prince Teng'."
        ),
        "韩愈": EnglishProfile(
            name: "Han Yu",
            lifeSpan: "768–824",
            courtesyName: "Courtesy name Tuizhi; known as Han of Changli",
            introduction: "A Tang prose master and poet whose writing is direct, forceful, and principled, often turning landscape into a test of character.",
            biography: "A jinshi of the Zhenyuan era, he rose to vice minister of justice and was banished to a remote post in Chaozhou for remonstrating against the welcome of the Buddha's relic, ending his career as vice minister of personnel. He led the movement to revive ancient-style prose and was revered as the writer who revived letters across eight dynasties, first among the Eight Masters of Tang and Song."
        ),
        "高适": EnglishProfile(
            name: "Gao Shi",
            lifeSpan: "c. 704–765",
            courtesyName: "Courtesy name Dafu",
            introduction: "A Tang frontier poet whose spacious, weathered verse joins military life, friendship, and the hard clarity of travel.",
            biography: "Poor and fatherless in his youth, he roamed the Liang-Song region for years before passing a special examination at fifty. He rose to military governor of Huainan and of western Sichuan and was ennobled as a count of Bohai—one of the very few Tang poets to reach such rank. His frontier poems stand beside Cen Shen's in the 'Gao and Cen' tradition."
        ),
        "岑参": EnglishProfile(
            name: "Cen Shen",
            lifeSpan: "c. 715–c. 770",
            courtesyName: nil,
            introduction: "A Tang frontier poet celebrated for vivid snow, desert, and military landscapes, rendered with alertness and adventurous energy.",
            biography: "From Jiangling, a jinshi of the Tianbao era who rose to prefect of Jiazhou—hence his familiar nickname. He twice went out to the western frontier as a staff judge, and his firsthand experience of desert marches and snowbound armies fed the vivid, exotic imagery of his celebrated frontier verse."
        ),
        "范仲淹": EnglishProfile(
            name: "Fan Zhongyan",
            lifeSpan: "989–1052",
            courtesyName: "Courtesy name Xiwen",
            introduction: "A Northern Song statesman and writer whose work joins public responsibility with broad landscapes and steady moral feeling.",
            biography: "From Wu County, a jinshi of the Dazhong Xiangfu era. As a chief councillor he launched the Qingli reforms, was forced out by conservative opposition, and governed border prefectures instead; in the northwest he drilled armies so well that the Western Xia court said he held tens of thousands of armored soldiers in his breast. In old age he endowed schools for his clan."
        ),
        "欧阳修": EnglishProfile(
            name: "Ouyang Xiu",
            lifeSpan: "1007–1072",
            courtesyName: "Courtesy name Yongshu, art names Zuiweng and Liuyi Jushi",
            introduction: "A Northern Song essayist, poet, and lyricist whose writing is generous and observant, equally at home in public life and quiet nature.",
            biography: "From Yongfeng, a jinshi of the Tiansheng era, banished to Yiling for supporting Fan Zhongyan and later rising to vice chief councillor. He championed younger writers—Su Shi and Zeng Gong among his protégés—and retired to Yingzhou in his last years. He was the acknowledged leader of the Northern Song literary world and one of the Eight Masters of Tang and Song."
        ),
        "王安石": EnglishProfile(
            name: "Wang Anshi",
            lifeSpan: "1021–1086",
            courtesyName: "Courtesy name Jiefu, art name Banshan",
            introduction: "A Northern Song statesman and poet whose spare, searching verse carries a firm intelligence and a determined attention to the world.",
            biography: "From Linchuan, a jinshi of the Qingli era. As chief councillor under Emperor Shenzong he launched sweeping reforms to strengthen state and army, met fierce resistance from the old faction, and was dismissed twice. He withdrew in old age to his garden at Banshan in Jiangning; his spare, searching poetry and prose place him among the Eight Masters of Tang and Song."
        ),
        "秦观": EnglishProfile(
            name: "Qin Guan",
            lifeSpan: "1049–1100",
            courtesyName: "Courtesy name Shaoyou, art name Huaihai Jushi",
            introduction: "A Northern Song lyricist of delicate emotional precision. His poems and lyrics hold moonlight, travel, and parting in a tender, lingering register.",
            biography: "From Gaoyou, a jinshi of the Yuanfeng era recommended by Su Shi to posts at the Imperial University and the History Bureau. With the Yuanyou faction's fall he was banished in stages to Chenzhou, Hengzhou, and Leizhou; recalled under a new emperor, he died at Tengzhou on the journey north. Among the Four Scholars of the Su school, his lyrics are the most tender and lingering."
        )
    ]

    var localizedName: String {
        guard AppLanguage.isEnglish else { return name }
        return Self.englishProfiles[name]?.name ?? name.romanizedChinese
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

    var localizedLifeSpan: String? {
        guard let lifeSpan else { return nil }
        guard AppLanguage.isEnglish else { return lifeSpan }
        return Self.englishProfiles[name]?.lifeSpan ?? lifeSpan
    }

    var localizedCourtesyName: String? {
        guard let courtesyName else { return nil }
        guard AppLanguage.isEnglish else { return courtesyName }
        return Self.englishProfiles[name]?.courtesyName ?? courtesyName
    }

    var localizedBiography: String? {
        guard AppLanguage.isEnglish else { return biography }
        return Self.englishProfiles[name]?.biography ?? biography
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
            lifeSpan: "701–762",
            courtesyName: "字太白，号青莲居士",
            biography: "祖籍陇西成纪，生于西域碎叶，长于蜀中。天宝年间入长安，供奉翰林，不久辞官游历四方。安史之乱中曾入永王幕府，获罪流放夜郎，中途遇赦，晚年漂泊东南，卒于当涂。",
            requiresMembership: false
        ),
        poet(
            "孟浩然", dynasty: "唐", avatar: "poet_meng_haoran",
            introduction: "盛唐山水田园诗人。笔下常见清晨、春雨与村野生活，语言自然清淡，情味含蓄悠长。",
            lifeSpan: "689–740",
            courtesyName: "名浩，字浩然",
            biography: "襄州襄阳人，一生未曾入仕，隐居鹿门山。早年有志用世，游历四方；四十岁时入京应试不第，遂归隐田园，以诗酒自娱，与王维、李白交好。"
        ),
        poet(
            "王之涣", dynasty: "唐", avatar: "poet_wang_zhihuan",
            introduction: "盛唐诗人。作品多写边塞与登临，气象开阔，寥寥数语便能写出壮阔山河与昂扬胸襟。",
            lifeSpan: "688–742",
            courtesyName: "字季凌",
            biography: "并州晋阳人，出身官宦世家。曾任冀州衡水主簿，因遭人诬陷而辞官，悠游山水十余年，后复出任文安县尉，卒于任上。传世诗作虽少，绝句尤为后人推重。"
        ),
        poet(
            "柳宗元", dynasty: "唐", avatar: "poet_liu_zongyuan",
            introduction: "唐代文学家、诗人。山水诗清峭幽冷，常把孤寂处境与独立不屈的精神寄托于自然景物。",
            lifeSpan: "773–819",
            courtesyName: "字子厚，世称柳河东",
            biography: "河东人，贞元年间进士，官至礼部员外郎。参与永贞革新，失败后被贬永州司马十年，再贬柳州刺史，卒于柳州任上。与韩愈共同倡导古文运动，名列“唐宋八大家”。"
        ),
        poet(
            "王维", dynasty: "唐", avatar: "poet_wang_wei",
            introduction: "盛唐诗人、画家。山水田园诗宁静空灵，诗中有画，也常流露澄澈自足的禅意。",
            lifeSpan: "701–761",
            courtesyName: "字摩诘，号摩诘居士",
            biography: "河东蒲州人，开元年间进士，官至尚书右丞，世称王右丞。安史之乱中被迫受伪职，乱平后获罪降职，此后过着亦官亦隐的生活。晚年笃信佛教，兼精绘画与音乐。"
        ),
        poet(
            "张继", dynasty: "唐", avatar: "poet_zhang_ji",
            introduction: "唐代诗人。善于在羁旅行役中捕捉夜色、钟声与客愁，《枫桥夜泊》尤为传诵。",
            courtesyName: "字懿孙",
            biography: "襄州人，天宝年间进士。安史之乱中避地江南，《枫桥夜泊》相传即作于流寓苏州之时。生平事迹传世甚少，诗风清远，以绝句见长。"
        ),
        poet(
            "苏轼", dynasty: "宋", avatar: "poet_su_shi",
            introduction: "北宋文学家、诗人、词人。作品题材开阔，既有旷达豪放的胸襟，也有细腻明澈的生活意趣。",
            lifeSpan: "1037–1101",
            courtesyName: "字子瞻，号东坡居士",
            biography: "眉州眉山人，嘉祐年间进士。因反对王安石变法被贬外任，又身陷“乌台诗案”贬居黄州；晚年再贬惠州、儋州。徽宗即位后遇赦北归，卒于常州。诗、词、文、书画俱为一代大家。"
        ),
        poet(
            "李清照", dynasty: "宋", avatar: "poet_li_qingzhao",
            introduction: "宋代词人。早期词作明快灵动，后期沉郁深婉，善用清丽精炼的语言写细微而深长的情感。",
            lifeSpan: "约1084–约1155",
            courtesyName: "号易安居士",
            biography: "济南人，早期生活优裕，与丈夫赵明诚共同致力于金石书画的收藏整理。靖康之变后南渡，丈夫病逝，文物散佚，晚年境遇凄苦。其词清新婉约，提出“词别是一家”。"
        ),
        poet(
            "陆游", dynasty: "宋", avatar: "poet_lu_you",
            introduction: "南宋诗人。诗作数量丰厚，既心系家国，也善写日常生活；咏梅之作尤见坚贞自守的品格。",
            lifeSpan: "1125–1210",
            courtesyName: "字务观，号放翁",
            biography: "越州山阴人，因忤秦桧而未能入仕，孝宗时赐进士出身。力主抗金，屡遭主和派排挤，中年入蜀，参赞南郑军务，晚年退居山阴。一生存诗近万首，为宋代诗人之冠。"
        ),
        poet(
            "杜甫", dynasty: "唐", avatar: "poet_du_fu",
            introduction: "唐代诗人。以沉郁顿挫的笔力记录时代与民生，也在山河、亲友与日常中寄托深厚的家国情怀。",
            lifeSpan: "712–770",
            courtesyName: "字子美，世称杜工部",
            biography: "巩县人，开元年间科举不第，漫游四方。安史之乱中陷于长安，后奔赴行在任左拾遗，不久弃官入蜀，营建成都草堂，依严武任检校工部员外郎。晚年漂泊湘楚之间，卒于舟中。"
        ),
        poet(
            "白居易", dynasty: "唐", avatar: "poet_bai_juyi",
            introduction: "中唐诗人。语言平易而情感深厚，既关怀民生，也善写江南风物、亲友情谊与人生况味。",
            lifeSpan: "772–846",
            courtesyName: "字乐天，号香山居士",
            biography: "下邽人，贞元年间进士，官至翰林学士、左赞善大夫。因上书言事被贬江州司马，后历任忠州、杭州、苏州刺史，晚年以刑部尚书致仕，居洛阳香山，自号香山居士。"
        ),
        poet(
            "王昌龄", dynasty: "唐", avatar: "poet_wang_changling",
            introduction: "盛唐诗人。边塞诗气骨雄健，闺怨与送别诗又清丽深婉，常在开阔意境中见细腻情思。",
            lifeSpan: "698–约756",
            courtesyName: "字少伯",
            biography: "京兆人，开元年间进士，历任汜水尉、江宁丞、龙标尉，世称王江宁、王龙标。安史之乱中被刺史闾丘晓所杀。其七绝名重当时，后人推为“七绝圣手”。"
        ),
        poet(
            "李商隐", dynasty: "唐", avatar: "poet_li_shangyin",
            introduction: "晚唐诗人。诗意幽微含蓄，善以夜雨、秋声、帘幕与芳草寄托难言的相思和身世之感。",
            lifeSpan: "约813–858",
            courtesyName: "字义山，号玉溪生",
            biography: "怀州河内人，开成年间进士。早年受知于令狐楚，后入泾原节度使王茂元幕府并娶其女，由此卷入牛李党争，终生仕途坎坷，仅任秘书省校书郎、弘农尉等微职，晚年闲居郑州，卒于荥阳。"
        ),
        poet(
            "柳永", dynasty: "宋", avatar: "poet_liu_yong",
            introduction: "北宋词人。长于铺写羁旅、都市与离情，词调婉转舒缓，把寻常人生写得绵长动人。",
            lifeSpan: "约987–约1053",
            courtesyName: "原名三变，字耆卿",
            biography: "崇安人，早年流连坊曲，科举屡试不第，后改名永，于景祐年间及第。官至屯田员外郎，世称柳屯田。其词雅俗并陈，传唱极广，相传“凡有井水处，皆能歌柳词”。"
        ),
        poet(
            "辛弃疾", dynasty: "宋", avatar: "poet_xin_qiji",
            introduction: "南宋词人。词中兼有报国壮志、沉郁不平与乡村闲适，豪放与婉约在笔下彼此交织。",
            lifeSpan: "1140–1207",
            courtesyName: "字幼安，号稼轩",
            biography: "历城人，生于金占区，青年时聚众抗金，率众南归。历任江西、湖南等地安抚使，创制飞虎军，屡陈恢复中原之策，不为朝廷所用，长期闲居上饶、铅山。词风豪放，与苏轼并称“苏辛”。"
        ),
        poet(
            "刘禹锡", dynasty: "唐", avatar: "poet_liu_yuxi",
            introduction: "中唐诗人。诗风清峻而有生气，常在怀古、山水与日常景物中写出对世事更新的坚定信念。",
            lifeSpan: "772–842",
            courtesyName: "字梦得",
            biography: "洛阳人，贞元年间进士。参与永贞革新，失败后被贬朗州司马，此后辗转连州、夔州、和州等地任刺史近二十年。晚年以太子宾客分司东都，与白居易唱和，世称刘宾客。"
        ),
        poet(
            "杜牧", dynasty: "唐", avatar: "poet_du_mu",
            introduction: "晚唐诗人。诗歌明丽俊爽，秋景、怀古、行旅与人事在笔下交织，既有风流情致，也有历史感怀。",
            lifeSpan: "803–852",
            courtesyName: "字牧之，号樊川居士",
            biography: "京兆万年人，宰相杜佑之孙。大和年间进士，历任黄州、池州、睦州刺史及司勋员外郎，官至中书舍人。其诗明丽俊爽，尤以七言绝句著称，著有《樊川文集》。"
        ),
        poet(
            "王勃", dynasty: "唐", avatar: "poet_wang_bo",
            introduction: "初唐诗人。才情早发，善以开阔的山河意象承载送别、怀人和身世之感，气象清新高远。",
            lifeSpan: "650–676",
            courtesyName: "字子安",
            biography: "绛州龙门人，麟德年间应举及第，曾任虢州参军，因事革职。上元二年南下省亲，渡海溺水，惊悸而卒，年仅二十七岁。为“初唐四杰”之首，代表作《滕王阁序》。"
        ),
        poet(
            "韩愈", dynasty: "唐", avatar: "poet_han_yu",
            introduction: "唐代文学家、诗人。文章气势雄健，诗歌直抒胸臆，常把山水、人生与坚守原则的精神写得峻拔有力。",
            lifeSpan: "768–824",
            courtesyName: "字退之，世称韩昌黎",
            biography: "河阳人，贞元年间进士。历任国子博士、刑部侍郎，因谏迎佛骨被贬潮州刺史，后官至吏部侍郎。倡导古文运动，排斥佛老，被尊为“文起八代之衰”，为“唐宋八大家”之首。"
        ),
        poet(
            "高适", dynasty: "唐", avatar: "poet_gao_shi",
            introduction: "盛唐边塞诗人。诗中有边地风尘、军旅见闻与朋友情谊，语言苍劲开阔，带着历尽世事的沉着。",
            lifeSpan: "约704–765",
            courtesyName: "字达夫",
            biography: "渤海蓚人，少时孤贫，长期漫游梁宋一带。五十岁后举有道科，历任封丘尉、淮南节度使、剑南西川节度使，官至散骑常侍，封渤海县侯，是唐代诗人中功名最显者之一。边塞诗与岑参齐名，并称“高岑”。"
        ),
        poet(
            "岑参", dynasty: "唐", avatar: "poet_cen_shen",
            introduction: "盛唐边塞诗人。善写雪山、沙漠与军营中的奇景，想象瑰丽，笔调明快而富有行旅的冒险精神。",
            lifeSpan: "约715–约770",
            biography: "荆州江陵人，天宝年间进士，官至嘉州刺史，世称岑嘉州。两度出塞，任安西、北庭节度使幕府判官，亲历西域军旅生活，以奇峭瑰丽的边塞诗著称。"
        ),
        poet(
            "范仲淹", dynasty: "宋", avatar: "poet_fan_zhongyan",
            introduction: "北宋政治家、文学家。作品兼有忧乐天下的担当与开阔沉着的山河之思，气象端正而深厚。",
            lifeSpan: "989–1052",
            courtesyName: "字希文",
            biography: "苏州吴县人，大中祥符年间进士。官至参知政事，推行“庆历新政”，因遭保守派反对而罢政，历知邠州、邓州等地。戍边西北时整军御敌，西夏人称其“胸中自有数万甲兵”。晚年捐资兴办义学。"
        ),
        poet(
            "欧阳修", dynasty: "宋", avatar: "poet_ou_yang_xiu",
            introduction: "北宋文学家、诗人、词人。文章平易舒展，诗词既写山水风物，也写士大夫日常中的旷达与温厚。",
            lifeSpan: "1007–1072",
            courtesyName: "字永叔，号醉翁、六一居士",
            biography: "吉州永丰人，天圣年间进士。因支持范仲淹被贬夷陵，后官至参知政事。奖掖后进，苏轼、曾巩皆出其门。晚年以太子少师致仕，定居颍州，为北宋文坛领袖，“唐宋八大家”之一。"
        ),
        poet(
            "王安石", dynasty: "宋", avatar: "poet_wang_an_shi",
            introduction: "北宋政治家、文学家。诗歌精炼峭拔，常在山川与日常景物中寄寓清醒、坚定而富有思辨的精神。",
            lifeSpan: "1021–1086",
            courtesyName: "字介甫，号半山",
            biography: "抚州临川人，庆历年间进士。熙宁年间任参知政事、宰相，推行变法以富国强兵，遭旧党反对，两度罢相。晚年退居江宁半山园，自号半山。诗文峭拔精炼，为“唐宋八大家”之一。"
        ),
        poet(
            "秦观", dynasty: "宋", avatar: "poet_qin_guan",
            introduction: "北宋词人。词风清丽婉约，善写月色、杨柳、羁旅与离情，情绪细密而余韵悠长。",
            lifeSpan: "1049–1100",
            courtesyName: "字少游，号淮海居士",
            biography: "高邮人，元丰年间进士，经苏轼举荐任太学博士、国史院编修。绍圣年间因元祐党籍连遭贬谪，谪居郴州、横州、雷州；徽宗即位后北归，卒于藤州。其词婉约深挚，为“苏门四学士”之一。"
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
                    lifeSpan: nil,
                    courtesyName: nil,
                    biography: nil,
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
                    lifeSpan: nil,
                    courtesyName: nil,
                    biography: nil,
                    collectionTitle: SongCiThreeHundredLibrary.collectionTitle,
                    requiresMembership: true
                )
            }
    }()

    /// Names of the curated famous poets, normalized to simplified Chinese.
    /// Poems by these authors read for free; everything else in the Tang/Song
    /// collections is members-only.
    static let famousAuthorNames: Set<String> = Set(featured.map { $0.name.poemScript(.simplified) })

    static func isFamousAuthor(_ name: String) -> Bool {
        famousAuthorNames.contains(name.poemScript(.simplified))
    }

    /// The poet matching an author name, tolerant of simplified/traditional
    /// variants. Returns nil for authors who have no profile (e.g. anonymous works).
    static func find(name: String) -> ClassicPoet? {
        let normalized = name.poemScript(.simplified)
        return (featured + tangShiThreeHundred + songCiThreeHundred).first {
            $0.name == name || $0.name.poemScript(.simplified) == normalized
        }
    }

    /// The curated famous poets are free to browse; only the long-tail
    /// Tang/Song collection rows stay members-only.
    private static func poet(
        _ name: String,
        dynasty: String,
        avatar: String?,
        introduction: String,
        lifeSpan: String? = nil,
        courtesyName: String? = nil,
        biography: String? = nil,
        collectionTitle: String? = nil,
        requiresMembership: Bool = false
    ) -> ClassicPoet {
        ClassicPoet(
            id: "\(dynasty)-\(name)",
            name: name,
            dynasty: dynasty,
            avatarAsset: avatar,
            introduction: introduction,
            lifeSpan: lifeSpan,
            courtesyName: courtesyName,
            biography: biography,
            collectionTitle: collectionTitle,
            requiresMembership: requiresMembership
        )
    }
}
