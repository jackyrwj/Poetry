import Foundation
import SwiftUI

extension Character {
    /// Whether the character is a CJK unified ideograph (used to decide seal text handling).
    var isCJK: Bool {
        guard let scalar = unicodeScalars.first else { return false }
        let value = Int(scalar.value)
        return (0x4E00...0x9FFF).contains(value)
            || (0x3400...0x4DBF).contains(value)
            || (0xF900...0xFAFF).contains(value)
    }
}

/// Transliterates Latin (English) names into Chinese characters for the seal stamp.
///
/// English names cannot be rendered by the seal-script font, so we give English users
/// the authentic experience instead: their given name transliterated into Chinese,
/// stamped in seal script like "艾米莉" for Emily.
enum NameTransliterator {
    static let overrideStorageKey = "sealTransliterationOverride"

    /// One seal character plus the alternates a user can cycle through while refining.
    struct Glyph: Equatable {
        let value: String
        let alternatives: [String]

        /// Values to cycle through on tap: current value first, then alternates (deduped).
        var cycle: [String] {
            ([value] + alternatives).filter { !$0.isEmpty }
        }
    }

    // MARK: - Public API

    /// The lowercase Latin name key (all words joined by a space), or nil if the name has no Latin letters.
    static func latinToken(for name: String) -> String? {
        latinTokens(for: name)?.joined(separator: " ")
    }

    /// Lowercase Latin words of `name`, or nil when the name should be stamped as entered.
    private static func latinTokens(for name: String) -> [String]? {
        // Any Chinese in the name means the user gave their Chinese name: stamp it directly.
        guard !name.contains(where: \.isCJK) else { return nil }
        let tokens = name
            .split(whereSeparator: { $0.isWhitespace || $0 == "-" || $0 == "'" || $0 == "_" })
            .map { String($0.filter(\.isLetter)).lowercased() }
            .filter { $0.contains(where: { $0.isASCII && $0.isLetter }) }
        // Names already in Chinese (or other scripts) are stamped as-is.
        guard let first = tokens.first, first.allSatisfy(\.isASCII) else { return nil }
        return tokens.filter { $0.allSatisfy(\.isASCII) }
    }

    /// Seal glyphs for a Latin name, honoring a stored per-name override.
    /// Returns nil when the name should be stamped as entered (e.g. already Chinese).
    static func glyphs(for name: String, storedOverride: String) -> [Glyph]? {
        guard let tokens = latinTokens(for: name) else { return nil }
        let key = tokens.joined(separator: " ")

        if let override = parseOverride(storedOverride), override.token == key {
            return makeGlyphs(String(override.chars.prefix(4)))
        }

        // Always stamp the first word; add later words only while the whole word
        // still fits in the four-character seal ("Mary Jane" → 玛丽简, "Li Bai" → 莉拜).
        var chars = transliterate(tokens[0])
        for token in tokens.dropFirst() {
            let next = transliterate(token)
            guard !next.isEmpty, chars.count + next.count <= 4 else { break }
            chars += next
        }
        guard !chars.isEmpty else { return nil }
        return makeGlyphs(String(chars.prefix(4)))
    }

    /// Text stamped as entered: only the Chinese characters when there are any
    /// ("Jacky 饶" → 饶), and whitespace never occupies a seal cell.
    static func rawSealText(_ name: String) -> String {
        name.contains(where: \.isCJK) ? name.filter(\.isCJK) : name.filter { !$0.isWhitespace }
    }

    private static func transliterate(_ token: String) -> String {
        dictionary[token] ?? syllableTransliteration(of: token)
    }

    /// Serializes an override as "token:chars".
    static func overrideString(token: String, chars: [String]) -> String {
        "\(token):\(chars.joined())"
    }

    // MARK: - Override parsing

    private static func parseOverride(_ raw: String) -> (token: String, chars: String)? {
        guard let colon = raw.firstIndex(of: ":") else { return nil }
        let token = raw[raw.startIndex..<colon].trimmingCharacters(in: .whitespaces)
        let chars = raw[raw.index(after: colon)...].filter { !$0.isWhitespace }
        guard !token.isEmpty, !chars.isEmpty else { return nil }
        return (token, chars)
    }

    private static func makeGlyphs(_ chars: String) -> [Glyph] {
        chars.map { Glyph(value: String($0), alternatives: characterAlternates[$0] ?? []) }
    }

    // MARK: - Syllable fallback

    private static let vowels: Set<Character> = ["a", "e", "i", "o", "u", "y"]

    private static func syllables(of token: String) -> [String] {
        var parts: [String] = []
        var consonants = ""
        var lastEndedWithVowel = false
        for char in token {
            if vowels.contains(char) {
                if consonants.isEmpty, lastEndedWithVowel, !parts.isEmpty {
                    parts[parts.count - 1].append(char) // vowel group: "ia", "ea", ...
                } else {
                    parts.append(consonants + String(char))
                }
                consonants = ""
                lastEndedWithVowel = true
            } else {
                consonants.append(char)
                lastEndedWithVowel = false
            }
        }
        if !consonants.isEmpty, !parts.isEmpty {
            parts[parts.count - 1].append(consonants) // trailing consonants
        }
        return parts
    }

    private static func syllableTransliteration(of token: String) -> String {
        syllables(of: token).map(fallbackSyllable).joined()
    }

    /// Maps one syllable to 1–2 Chinese characters; whole-token entries may map more.
    private static func fallbackSyllable(_ syllable: String) -> String {
        if let mapped = syllableTable[syllable] { return mapped }
        let leading = syllable.prefix { !vowels.contains($0) }
        let rest = syllable.dropFirst(leading.count)
        let cluster = String(leading.prefix(2))
        let clusterChar = clusterTable[cluster] ?? initialTable[leading.first.map(String.init) ?? ""]
        guard !rest.isEmpty else { return clusterChar ?? "" }
        let restChar = syllableTable[String(rest)] ?? vowelTable[String(rest)]
            ?? rest.first.flatMap { vowelTable[String($0)] } ?? "" // never leak Latin letters into the seal
        return (clusterChar ?? "") + restChar
    }

    // MARK: - Data

    /// Common first names → standard Chinese transliteration (given-name first).
    private static let dictionary: [String: String] = [
        "aaron": "亚伦", "abel": "亚伯", "abigail": "阿比盖尔", "adam": "亚当",
        "adrian": "阿德里安", "aisha": "艾莎", "al": "艾尔", "alan": "艾伦",
        "albert": "阿尔伯特", "alex": "亚历克斯", "alexander": "亚历山大",
        "alexandra": "亚历山德拉", "alfred": "阿尔弗雷德", "alice": "爱丽丝",
        "alicia": "艾丽西娅", "alina": "艾丽娜", "alison": "艾莉森", "amanda": "阿曼达",
        "amber": "安伯", "amelia": "阿米莉亚", "amir": "阿米尔", "amy": "埃米",
        "andrea": "安德烈娅", "andrew": "安德鲁", "andy": "安迪", "angela": "安吉拉",
        "angelina": "安吉丽娜", "anita": "安妮塔", "ann": "安", "anna": "安娜",
        "anne": "安妮", "annie": "安妮", "anthony": "安东尼", "antonio": "安东尼奥",
        "april": "艾普莉尔", "archie": "阿奇", "arthur": "阿瑟", "ashley": "阿什莉",
        "audrey": "奥德丽", "austin": "奥斯汀", "barbara": "芭芭拉", "barry": "巴里",
        "beatrice": "比阿特丽丝", "bella": "贝拉", "ben": "本", "benedict": "本尼迪克特",
        "benjamin": "本杰明", "bernard": "伯纳德", "bertha": "伯莎", "bess": "贝丝",
        "betty": "贝蒂", "bianca": "比安卡", "bill": "比尔", "billy": "比利",
        "blake": "布莱克", "bonnie": "邦妮", "brandon": "布兰登", "brenda": "布伦达",
        "brian": "布莱恩", "bruce": "布鲁斯", "bryan": "布莱恩", "byron": "拜伦",
        "caleb": "凯莱布", "calvin": "卡尔文", "camila": "卡米拉", "carl": "卡尔",
        "carla": "卡拉", "carlos": "卡洛斯", "carmen": "卡门", "carol": "卡罗尔",
        "caroline": "卡罗琳", "carrie": "卡里", "carter": "卡特", "catherine": "凯瑟琳",
        "cecilia": "塞西莉亚", "cedric": "塞德里克", "chad": "查德", "charles": "查尔斯",
        "charlie": "查利", "charlotte": "夏洛特", "cheryl": "谢丽尔", "chloe": "克洛伊",
        "chris": "克里斯", "christian": "克里斯蒂安", "christina": "克里斯蒂娜",
        "christine": "克里斯汀", "christopher": "克里斯托弗", "cindy": "辛迪",
        "clara": "克拉拉", "clarence": "克拉伦斯", "clark": "克拉克", "claudia": "克劳迪娅",
        "cliff": "克利夫", "clinton": "克林顿", "cody": "科迪", "colin": "科林",
        "connie": "康妮", "cooper": "库珀", "cora": "科拉", "corey": "科里",
        "craig": "克雷格", "crystal": "克里斯特尔", "curtis": "柯蒂斯", "cynthia": "辛西娅",
        "dale": "戴尔", "damian": "达米安", "dan": "丹", "dana": "戴娜",
        "daniel": "丹尼尔", "danielle": "丹妮尔", "danny": "丹尼", "daphne": "达夫妮",
        "darla": "达拉", "darren": "达伦", "dave": "戴夫", "david": "大卫",
        "dawn": "道恩", "dean": "迪安", "deborah": "德博拉", "denise": "丹妮丝",
        "dennis": "丹尼斯", "derek": "德里克", "desmond": "德斯蒙德", "diana": "戴安娜",
        "diane": "黛安", "diego": "迭戈", "dolores": "多洛丽丝", "dominic": "多米尼克",
        "don": "唐", "donald": "唐纳德", "donna": "唐娜", "dora": "多拉",
        "doris": "多丽丝", "dorothy": "多萝西", "douglas": "道格拉斯", "duane": "杜安",
        "dustin": "达斯蒂", "dylan": "狄伦", "earl": "厄尔", "ed": "埃德",
        "eddie": "埃迪", "edgar": "埃德加", "edith": "伊迪丝", "edmund": "埃德蒙",
        "edna": "埃德娜", "edward": "爱德华", "edwin": "埃德温", "eileen": "艾琳",
        "elaine": "伊莱恩", "eleanor": "埃莉诺", "elena": "埃琳娜", "eli": "伊莱",
        "elias": "埃利亚斯", "elijah": "伊莱贾", "ella": "埃拉", "ellen": "埃伦",
        "ellie": "埃莉", "elmer": "埃尔默", "eloise": "埃洛伊丝", "elsa": "埃尔莎",
        "elsie": "埃尔西", "elvin": "埃尔文", "elvis": "埃尔维斯", "emily": "艾米莉",
        "emma": "埃玛", "enid": "伊妮德", "eric": "埃里克", "erica": "埃丽卡",
        "erin": "艾琳", "ernest": "欧内斯特", "esther": "埃丝特", "ethan": "伊桑",
        "eugene": "尤金", "eunice": "尤妮丝", "eva": "伊娃", "evan": "埃文",
        "evelyn": "伊芙琳", "everett": "埃弗雷特", "ezra": "埃兹拉", "felix": "费利克斯",
        "fiona": "菲奥娜", "flora": "弗洛拉", "florence": "弗洛伦丝", "floyd": "弗洛伊德",
        "frances": "弗朗西丝", "francis": "弗朗西斯", "frank": "弗兰克", "franklin": "富兰克林",
        "fred": "弗雷德", "freddie": "弗雷迪", "frederick": "弗雷德里克", "gabriel": "加布里埃尔",
        "gail": "盖尔", "garrett": "加勒特", "gary": "加里", "gavin": "加文",
        "gene": "吉恩", "geoffrey": "杰弗里", "george": "乔治", "gerald": "杰拉尔德",
        "geraldine": "杰拉尔丁", "gilbert": "吉尔伯特", "gina": "吉娜", "ginger": "金杰",
        "gladys": "格拉迪斯", "glen": "格伦", "gloria": "格洛丽亚", "gordon": "戈登",
        "grace": "格蕾丝", "graham": "格雷厄姆", "grant": "格兰特", "greg": "格雷格",
        "gregory": "格雷戈里", "greta": "格蕾塔", "gwen": "格温", "hannah": "汉娜",
        "harold": "哈罗德", "harriet": "哈丽雅特", "harry": "哈里", "harvey": "哈维",
        "hazel": "黑兹尔", "heather": "希瑟", "hector": "赫克托", "heidi": "海蒂",
        "helen": "海伦", "henry": "亨利", "herbert": "赫伯特", "herman": "赫尔曼",
        "hillary": "希拉里", "holly": "霍莉", "homer": "霍默", "hope": "霍普",
        "howard": "霍华德", "hugh": "休", "ian": "伊恩", "ida": "艾达",
        "ignacio": "伊格纳西奥", "imogen": "伊莫金", "ina": "伊娜", "ingrid": "英格丽德",
        "irene": "艾琳", "iris": "艾里斯", "irma": "厄玛", "isaac": "艾萨克",
        "isabel": "伊莎贝尔", "isabella": "伊莎贝拉", "ivan": "伊万", "jack": "杰克", "jackie": "杰基", "jacky": "杰基",
        "jacob": "雅各布", "jacqueline": "杰奎琳", "jade": "贾德", "jake": "杰克",
        "james": "詹姆斯", "jamie": "杰米", "jane": "简", "janet": "珍妮特",
        "janice": "贾尼丝", "jared": "贾里德", "jasmine": "贾丝明", "jason": "贾森",
        "javier": "哈维尔", "jay": "杰伊", "jean": "琼", "jeff": "杰夫",
        "jeffrey": "杰弗里", "jennifer": "詹妮弗", "jeremy": "杰里米", "jerome": "杰罗姆",
        "jess": "杰丝", "jesse": "杰西", "jessica": "杰西卡", "jill": "吉尔",
        "jim": "吉姆", "jimmy": "吉米", "joan": "琼", "joanna": "乔安娜",
        "joanne": "乔安妮", "jocelyn": "乔斯林", "joel": "乔尔", "john": "约翰",
        "johnny": "约翰尼", "jon": "乔恩", "jonathan": "乔纳森", "jordan": "乔丹",
        "jorge": "豪尔赫", "jose": "何塞", "joseph": "约瑟夫", "josephine": "约瑟芬",
        "josh": "乔希", "joshua": "约书亚", "joyce": "乔伊斯", "juan": "胡安",
        "judith": "朱迪思", "julia": "朱莉娅", "julian": "朱利安", "julie": "朱莉",
        "juliet": "朱丽叶", "june": "朱恩", "justin": "贾斯汀", "karen": "卡伦",
        "karl": "卡尔", "kate": "凯特", "katie": "凯蒂", "katherine": "凯瑟琳",
        "kathleen": "凯瑟琳", "kathy": "凯茜", "kay": "凯",
        "keith": "基思", "kelly": "凯利", "kelvin": "凯尔文", "ken": "肯",
        "kendra": "肯德拉", "kenneth": "肯尼思", "kenny": "肯尼", "kevin": "凯文",
        "kim": "金", "kimberly": "金伯利", "kirk": "柯克", "kirsten": "柯尔斯滕",
        "kurt": "库尔特", "kyle": "凯尔", "lambert": "兰伯特", "lance": "兰斯",
        "larry": "拉里", "laura": "劳拉", "lauren": "劳伦", "laurie": "劳里",
        "lawrence": "劳伦斯", "leah": "莉亚", "lee": "李", "lena": "莉娜",
        "leo": "利奥", "leon": "莱昂", "leonard": "伦纳德", "leroy": "勒鲁瓦",
        "leslie": "莱斯利", "lester": "莱斯特", "levi": "利瓦伊", "lewis": "刘易斯",
        "liam": "利亚姆", "lillian": "莉莲", "lily": "莉莉", "lincoln": "林肯",
        "linda": "琳达", "lindsay": "林赛", "lionel": "莱昂内尔", "lisa": "莉萨",
        "lloyd": "劳埃德", "logan": "洛根", "lois": "洛伊丝", "lonnie": "朗尼",
        "lorna": "洛娜", "lorraine": "洛兰", "lou": "卢", "louis": "路易斯",
        "louise": "路易丝", "lucas": "卢卡斯", "lucia": "露西亚", "lucille": "露西尔",
        "lucy": "露西", "luis": "路易斯", "luke": "卢克", "luther": "卢瑟",
        "lydia": "莉迪娅", "lyle": "莱尔", "lynn": "林恩", "mabel": "梅布尔",
        "mack": "麦克", "madeline": "马德琳", "malcolm": "马尔科姆", "mandy": "曼迪",
        "marc": "马克", "marcia": "马西娅", "marcus": "马库斯", "margaret": "玛格丽特",
        "margie": "玛吉", "maria": "玛丽亚", "marian": "玛丽安", "marie": "玛丽",
        "marilyn": "玛丽莲", "mario": "马里奥", "marion": "马里恩", "mark": "马克",
        "marlene": "马琳", "marsha": "玛莎", "martha": "玛莎", "martin": "马丁",
        "marvin": "马文", "mary": "玛丽", "mason": "梅森", "matthew": "马修",
        "maureen": "莫琳", "maurice": "莫里斯", "max": "马克斯", "megan": "梅甘",
        "melanie": "梅拉妮", "melinda": "梅琳达", "melissa": "梅利莎", "melvin": "梅尔文",
        "meredith": "梅雷迪思", "mia": "米娅", "micah": "迈卡", "michael": "迈克尔",
        "michelle": "米歇尔", "mick": "米克", "mickey": "米奇", "miguel": "米格尔",
        "mike": "迈克", "mildred": "米尔德里德", "milton": "米尔顿", "mindy": "明迪",
        "minnie": "明妮", "miriam": "米里亚姆", "misty": "米丝蒂", "mitchell": "米切尔",
        "molly": "莫莉", "monica": "莫妮卡", "morgan": "摩根", "morris": "莫里斯",
        "moses": "摩西", "muriel": "缪丽尔", "myra": "迈拉", "myron": "迈伦",
        "nadia": "娜迪娅", "nancy": "南希", "naomi": "娜奥米", "natalie": "娜塔莉",
        "nathan": "内森", "nathaniel": "纳撒尼尔", "neil": "尼尔", "nell": "内尔",
        "nelson": "纳尔逊", "nicholas": "尼古拉斯", "nick": "尼克", "nicole": "妮科尔",
        "nina": "尼娜", "noah": "诺亚", "noel": "诺埃尔", "nolan": "诺兰",
        "nora": "诺拉", "norman": "诺曼", "olga": "奥尔加", "olive": "奥利芙",
        "oliver": "奥利弗", "olivia": "奥利维亚", "ollie": "奥利", "omar": "奥马尔",
        "oscar": "奥斯卡", "oswald": "奥斯瓦尔德", "owen": "欧文", "pablo": "巴勃罗",
        "pamela": "帕梅拉", "pat": "帕特", "patricia": "帕特里夏", "patrick": "帕特里克",
        "paul": "保罗", "paula": "保拉", "pauline": "波琳", "pearl": "珀尔",
        "peggy": "佩吉", "penelope": "佩内洛普", "penny": "彭妮", "percy": "珀西",
        "perry": "佩里", "pete": "皮特", "peter": "彼得", "phil": "菲尔",
        "philip": "菲利普", "phoebe": "菲比", "phyllis": "菲莉丝", "preston": "普雷斯顿",
        "priscilla": "普丽西拉", "rachel": "雷切尔", "ralph": "拉尔夫", "ramona": "拉蒙娜",
        "randall": "兰德尔", "randy": "兰迪", "raquel": "拉凯尔", "raul": "劳尔",
        "ray": "雷", "raymond": "雷蒙德", "rebecca": "丽贝卡", "regina": "雷吉娜",
        "reginald": "雷金纳德", "renee": "蕾妮", "rex": "雷克斯", "rhonda": "朗达",
        "richard": "理查德", "rita": "丽塔", "robert": "罗伯特", "roberta": "罗伯塔",
        "robin": "罗宾", "rodney": "罗德尼", "roger": "罗杰", "roland": "罗兰",
        "ron": "罗恩", "ronald": "罗纳德", "ronnie": "龙尼", "rosa": "罗莎",
        "rosalie": "罗莎莉", "rose": "罗丝", "rosemary": "罗斯玛丽", "ross": "罗斯",
        "roxanne": "罗克珊", "roy": "罗伊", "ruben": "鲁本", "ruby": "露比",
        "rudolph": "鲁道夫", "rudy": "鲁迪", "russell": "拉塞尔", "ruth": "露丝",
        "ryan": "瑞安", "sabrina": "萨布丽娜", "sadie": "塞迪", "sally": "萨莉",
        "salvador": "萨尔瓦多", "samantha": "萨曼莎", "samuel": "塞缪尔", "sandra": "桑德拉",
        "sandy": "桑迪", "sara": "萨拉", "sarah": "萨拉", "saul": "索尔",
        "scarlett": "斯嘉丽", "scott": "斯科特", "sean": "肖恩", "serena": "塞雷娜",
        "sergio": "塞尔吉奥", "seth": "塞思", "shane": "沙恩", "shannon": "香农",
        "sharon": "沙伦", "shawn": "肖恩", "sheila": "希拉", "sheldon": "谢尔登",
        "shelley": "谢利", "sherman": "谢尔曼", "sherry": "雪莉", "shirley": "雪莉",
        "sidney": "西德尼", "silvia": "西尔维娅", "simon": "西蒙", "sonia": "索尼娅",
        "sophia": "索菲娅", "sophie": "索菲", "spencer": "斯潘塞", "stacy": "斯泰西",
        "stanley": "斯坦利", "stella": "斯特拉", "stephanie": "斯蒂芬妮", "stephen": "史蒂文",
        "steve": "史蒂夫", "steven": "史蒂文", "stewart": "斯图尔特", "stuart": "斯图尔特",
        "sue": "苏", "susan": "苏珊", "susie": "苏茜", "suzanne": "苏珊娜",
        "sydney": "西德尼", "sylvia": "西尔维娅", "tabitha": "塔比莎", "tamara": "塔玛拉",
        "tanya": "塔尼娅", "tara": "塔拉", "taylor": "泰勒", "ted": "特德",
        "teddy": "特迪", "teresa": "特蕾莎", "terrence": "特伦斯", "terri": "特里",
        "terry": "特里", "thelma": "塞尔玛", "theo": "西奥", "theodore": "西奥多",
        "theresa": "特蕾莎", "thomas": "托马斯", "tiffany": "蒂法尼", "tim": "蒂姆",
        "timothy": "蒂莫西", "tina": "蒂娜", "toby": "托比", "todd": "托德",
        "tom": "汤姆", "tomas": "托马斯", "tommy": "汤米", "toni": "托尼",
        "tony": "托尼", "tracy": "特蕾西", "travis": "特拉维斯", "trevor": "特雷弗",
        "tyler": "泰勒", "tyrone": "蒂龙", "valerie": "瓦莱丽", "vanessa": "瓦妮莎",
        "vera": "薇拉", "verna": "弗娜", "vernon": "弗农", "veronica": "维罗妮卡",
        "victor": "维克托", "victoria": "维多利亚", "vincent": "文森特", "viola": "维奥拉",
        "violet": "维奥莱特", "virgil": "弗吉尔", "virginia": "弗吉尼亚", "vivian": "薇薇安",
        "wade": "韦德", "wallace": "华莱士", "walter": "沃尔特", "wanda": "旺达",
        "warren": "沃伦", "wayne": "韦恩", "wendy": "温迪", "wesley": "韦斯利",
        "whitney": "惠特尼", "wilbur": "威尔伯", "will": "威尔", "william": "威廉",
        "willie": "威利", "willis": "威利斯", "wilma": "威尔玛", "winifred": "威妮弗雷德",
        "winston": "温斯顿", "xavier": "泽维尔", "yolanda": "约兰达", "yvette": "伊薇特",
        "yvonne": "伊冯娜", "zachary": "扎卡里", "zack": "扎克", "zoe": "佐伊",
        "zoey": "佐伊",
    ]

    /// Syllable-level fallback for names not in the dictionary.
    private static let syllableTable: [String: String] = [
        "a": "阿", "e": "伊", "i": "伊", "o": "奥", "u": "乌", "y": "伊",
        "an": "安", "en": "恩", "in": "因", "on": "翁", "un": "温",
        "ang": "昂", "ing": "英", "ong": "翁", "ung": "温",
        "ai": "艾", "ei": "埃", "oi": "奥伊", "ui": "威", "au": "奥", "ou": "欧",
        "ar": "尔", "er": "尔", "ir": "尔", "or": "奥", "ur": "尔",
        "al": "奥尔", "el": "埃尔", "il": "伊尔", "ol": "奥尔", "ul": "乌尔",
        "am": "安", "em": "埃姆", "im": "伊姆", "om": "翁", "um": "乌姆",
        "ay": "伊", "ey": "伊", "ie": "伊", "inn": "因", "ene": "恩",
        "ba": "巴", "be": "贝", "bi": "比", "bo": "博", "bu": "布",
        "ca": "卡", "ce": "塞", "ci": "西", "co": "科", "cu": "库",
        "cha": "查", "che": "切", "chi": "奇", "cho": "乔", "chu": "丘",
        "da": "达", "de": "德", "di": "迪", "do": "多", "du": "杜",
        "fa": "法", "fe": "费", "fi": "菲", "fo": "福", "fu": "富",
        "ga": "加", "ge": "格", "gi": "吉", "go": "戈", "gu": "古",
        "ha": "哈", "he": "赫", "hi": "希", "ho": "霍", "hu": "胡",
        "ja": "贾", "je": "杰", "ji": "吉", "jo": "乔", "ju": "朱",
        "ka": "卡", "ke": "克", "ki": "基", "ko": "科", "ku": "库",
        "la": "拉", "le": "勒", "li": "莉", "lo": "洛", "lu": "卢",
        "ma": "玛", "me": "梅", "mi": "米", "mo": "莫", "mu": "穆",
        "na": "娜", "ne": "内", "ni": "妮", "no": "诺", "nu": "努",
        "pa": "帕", "pe": "佩", "pi": "皮", "po": "波", "pu": "普",
        "ra": "拉", "re": "雷", "ri": "里", "ro": "罗", "ru": "鲁",
        "sa": "萨", "se": "塞", "si": "丝", "so": "索", "su": "苏",
        "sha": "莎", "she": "谢", "shi": "希", "sho": "肖", "shu": "舒",
        "ta": "塔", "te": "特", "ti": "蒂", "to": "托", "tu": "图",
        "va": "瓦", "ve": "韦", "vi": "薇", "vo": "沃", "vu": "武",
        "wa": "瓦", "we": "韦", "wi": "威", "wo": "沃", "wu": "伍",
        "ya": "雅", "ye": "耶", "yi": "伊", "yo": "约", "yu": "于",
        "za": "扎", "ze": "泽", "zi": "兹", "zo": "佐", "zu": "祖",
    ]

    /// Two-consonant clusters that transliterate as a unit.
    private static let clusterTable: [String: String] = [
        "ch": "奇", "sh": "什", "ph": "弗", "th": "斯", "wh": "惠",
        "qu": "奎", "ck": "克", "kn": "内", "wr": "尔", "gn": "尼",
        "mc": "麦克", "mb": "姆",
    ]

    /// Single leading consonant → character when the rest is unmapped.
    private static let initialTable: [String: String] = [
        "b": "布", "c": "克", "d": "德", "f": "夫", "g": "格",
        "h": "赫", "j": "吉", "k": "克", "l": "尔", "m": "姆",
        "n": "恩", "p": "普", "q": "库", "r": "尔", "s": "斯",
        "t": "特", "v": "夫", "w": "沃", "x": "克斯", "y": "伊", "z": "兹",
    ]

    /// Bare vowel sounds → character.
    private static let vowelTable: [String: String] = [
        "a": "阿", "e": "厄", "i": "伊", "o": "奥", "u": "乌",
        "an": "安", "en": "恩", "in": "因", "on": "翁", "un": "温",
        "ang": "昂", "ing": "英", "ong": "翁",
        "ai": "艾", "ao": "奥", "au": "奥", "ei": "伊", "ou": "欧",
    ]

    /// Alternate characters a user can cycle to while refining their seal (keyed by primary char).
    private static let characterAlternates: [Character: [String]] = [
        "阿": ["安", "奥", "昂"], "安": ["昂", "庵", "谙"], "昂": ["安", "盎"],
        "艾": ["爱", "埃", "蔼"], "埃": ["艾", "爱"], "爱": ["艾", "嫒"],
        "伊": ["依", "衣", "漪"], "依": ["伊", "衣"], "衣": ["伊", "依"],
        "奥": ["欧", "澳", "懊"], "欧": ["奥", "鸥", "瓯"], "乌": ["伍", "吴", "巫"],
        "伍": ["武", "梧", "舞"], "恩": ["蒽"], "因": ["茵", "音", "姻"],
        "茵": ["因", "音"], "音": ["因", "茵"], "温": ["文", "雯", "纹"],
        "文": ["温", "雯", "纹"], "英": ["颖", "莹", "瑛", "缨"],
        "颖": ["英", "颍"], "莹": ["英", "滢"], "翁": ["泓", "瓮"],
        "厄": ["遏", "呃"], "亚": ["雅", "娅"], "雅": ["亚", "娅"],
        "尔": ["耳", "迩"],
        "巴": ["芭", "笆"], "贝": ["蓓", "呗", "钡"], "比": ["彼", "笔", "碧"],
        "博": ["伯", "帛", "铂"], "布": ["卜", "步"], "卡": ["佧", "咔", "胩"],
        "塞": ["赛", "瑟"], "西": ["希", "熙", "曦"], "科": ["柯", "珂", "苛"],
        "库": ["喾", "绔"], "查": ["茬", "楂"], "切": ["彻", "澈", "砌"],
        "奇": ["琪", "琦", "棋"], "乔": ["桥", "侨", "荞"], "丘": ["邱", "蚯"],
        "达": ["妲", "笪"], "德": ["得", "锝"], "迪": ["笛", "荻", "籴"],
        "多": ["朵", "哆"], "杜": ["度", "渡", "镀"], "法": ["发", "罚"],
        "费": ["菲", "翡"], "菲": ["霏", "菲", "妃"], "福": ["弗", "浮"],
        "富": ["付", "傅", "赋"], "加": ["佳", "伽", "迦"], "格": ["戈", "歌", "鸽"],
        "吉": ["姬", "佶", "及"], "戈": ["哥", "歌"], "古": ["谷", "骨", "蛊"],
        "哈": ["铪"], "赫": ["鹤", "壑"], "希": ["曦", "熙", "溪"],
        "霍": ["货", "祸"], "胡": ["湖", "葫", "蝴"], "贾": ["假", "甲"],
        "杰": ["洁", "捷", "婕", "颉"], "朱": ["珠", "株", "蛛"],
        "基": ["姬", "机", "玑"], "拉": ["啦", "腊", "蜡"], "勒": ["乐", "仂"],
        "莉": ["丽", "利", "骊", "梨", "俐"], "丽": ["俪", "骊", "鹂"],
        "利": ["黎", "梨", "俐", "莉"], "洛": ["骆", "络", "珞", "落"],
        "卢": ["芦", "庐", "泸"], "玛": ["马", "麻"], "马": ["玛", "玛"],
        "梅": ["眉", "玫", "湄"], "米": ["蜜", "觅", "汨"], "蜜": ["宓", "密", "谧"],
        "莫": ["寞", "漠", "茉"], "穆": ["木", "牧", "慕"], "娜": ["纳", "捺", "衲"],
        "内": ["讷"], "妮": ["尼", "昵", "泥"], "诺": ["喏", "锘"],
        "努": ["弩", "怒"], "帕": ["怕"], "佩": ["沛", "珮"], "皮": ["琵", "疲"],
        "波": ["伯", "泊", "菠"], "普": ["浦", "璞", "溥"], "雷": ["镭", "磊", "蕾"],
        "里": ["理", "锂", "俚", "鲤"], "罗": ["萝", "逻", "箩"], "鲁": ["陆", "卤"],
        "萨": ["洒", "卅"], "苏": ["酥", "稣", "愫"], "丝": ["斯", "思", "私", "司"],
        "斯": ["丝", "思", "司"], "莎": ["沙", "纱", "砂"], "谢": ["榭", "懈"],
        "肖": ["萧", "潇", "宵"], "舒": ["疏", "蔬", "书"], "塔": ["塌", "榻"],
        "特": ["忑"], "蒂": ["帝", "娣", "谛"], "托": ["拓", "脱"], "图": ["徒", "涂", "屠"],
        "瓦": ["佤"], "韦": ["伟", "炜", "玮"], "薇": ["微", "维", "巍"],
        "微": ["薇", "维", "巍"], "威": ["巍", "薇"], "沃": ["卧", "斡"],
        "武": ["伍", "舞", "鹉"], "耶": ["也", "冶"],
        "于": ["余", "虞", "瑜"], "扎": ["札", "轧"], "泽": ["则", "择", "责"],
        "兹": ["滋", "姿", "咨"], "佐": ["左", "坐"], "祖": ["组", "阻"],
        "姆": ["母", "木", "慕"], "麦": ["迈"], "什": ["石", "时", "实"],
        "弗": ["福", "扶", "芙"], "惠": ["慧", "蕙", "卉"],
        "黛": ["代", "岱", "玳"],
    ]
}

// MARK: - Refinement chips

/// Shows the transliterated seal characters for a Latin name; tapping a character
/// cycles through alternates (e.g. 莉 → 丽 → 利), refined choices are remembered
/// per name token. Renders nothing for names stamped as entered (e.g. Chinese).
struct SealTransliterationChips: View {
    let name: String
    @AppStorage(NameTransliterator.overrideStorageKey) private var storedOverride = ""

    var overrideBinding: Binding<String>? = nil

    private var selectedOverride: String {
        overrideBinding?.wrappedValue ?? storedOverride
    }

    private func updateOverride(_ value: String) {
        if let overrideBinding {
            overrideBinding.wrappedValue = value
        } else {
            storedOverride = value
        }
    }

    var body: some View {
        guard let token = NameTransliterator.latinToken(for: name),
              let glyphs = NameTransliterator.glyphs(for: name, storedOverride: selectedOverride)
        else { return AnyView(EmptyView()) }

        let isOverridden = selectedOverride.hasPrefix("\(token):")
        return AnyView(
            HStack(spacing: 10) {
                Text(AppLanguage.copy("印章漢字", "Your seal in Chinese"))
                    .font(.system(size: 12, design: .serif))
                    .foregroundStyle(ClassicPalette.mutedInk)

                HStack(spacing: 6) {
                    ForEach(Array(glyphs.enumerated()), id: \.offset) { index, glyph in
                        Button {
                            cycle(glyph, at: index, token: token, glyphs: glyphs)
                        } label: {
                            Text(glyph.value)
                                .font(.system(size: 15, design: .serif))
                                .foregroundStyle(ClassicPalette.cinnabar)
                                .frame(width: 28, height: 28)
                                .background {
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(ClassicPalette.cinnabar.opacity(0.5), lineWidth: 0.8)
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(glyph.value)
                    }

                    if isOverridden {
                        Button {
                            updateOverride("")
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(ClassicPalette.mutedInk)
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(AppLanguage.copy("恢復自動音譯", "Back to automatic transliteration"))
                    }
                }
            }
        )
    }

    private func cycle(_ glyph: NameTransliterator.Glyph, at index: Int, token: String, glyphs: [NameTransliterator.Glyph]) {
        let options = glyph.cycle
        guard options.count > 1,
              let current = options.firstIndex(of: glyph.value)
        else { return }
        var values = glyphs.map(\.value)
        values[index] = options[(current + 1) % options.count]
        updateOverride(NameTransliterator.overrideString(token: token, chars: values))
    }
}
