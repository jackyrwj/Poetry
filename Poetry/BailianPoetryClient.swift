import Foundation

actor PoetryCandidateStore {
    static let shared = PoetryCandidateStore()

    private var cachedCandidates: [String: [String]] = [:]
    private var activeRequests: [String: Task<[String], Error>] = [:]

    func candidates(for key: String, create: @escaping () async throws -> [String]) async throws -> [String] {
        if let cached = cachedCandidates[key] {
            return cached
        }

        if let activeRequest = activeRequests[key] {
            return try await activeRequest.value
        }

        let request = Task {
            try await create()
        }
        activeRequests[key] = request

        do {
            let candidates = try await request.value
            cachedCandidates[key] = candidates
            activeRequests[key] = nil
            return candidates
        } catch {
            activeRequests[key] = nil
            throw error
        }
    }
}

struct BailianPoetryClient {
    private let config: BailianConfig
    private let session: URLSession

    init(config: BailianConfig = .load(), session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    func generateCandidates(
        mood: MoodSeed,
        image: ImageSeed,
        lineIndex: Int,
        selectedLines: [String],
        fallback: [String],
        poemForm: PoemFormSpec,
        script: PoemScript = .traditional
    ) async throws -> [String] {
        let cacheKey = candidateCacheKey(
            mood: mood,
            image: image,
            lineIndex: lineIndex,
            selectedLines: selectedLines,
            fallback: fallback,
            poemForm: poemForm,
            script: script
        )

        let candidates = try await PoetryCandidateStore.shared.candidates(for: cacheKey) {
            try await requestCandidates(
                mood: mood,
                image: image,
                lineIndex: lineIndex,
                selectedLines: selectedLines,
                fallback: fallback,
                poemForm: poemForm,
                script: script
            )
        }
        return candidates
    }

    private func requestCandidates(
        mood: MoodSeed,
        image: ImageSeed,
        lineIndex: Int,
        selectedLines: [String],
        fallback: [String],
        poemForm: PoemFormSpec,
        script: PoemScript
    ) async throws -> [String] {
        guard config.isUsable else {
            throw BailianError.missingConfig
        }

        var request = URLRequest(url: config.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(
            ChatRequest(
                model: config.model,
                messages: [
                    .init(role: "system", content: systemPrompt),
                    .init(role: "user", content: userPrompt(
                        mood: mood,
                        image: image,
                        lineIndex: lineIndex,
                        selectedLines: selectedLines,
                        fallback: fallback,
                        poemForm: poemForm,
                        script: script
                    ))
                ],
                temperature: 0.85
            )
        )

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BailianError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw BailianError.httpStatus(httpResponse.statusCode)
        }

        let chatResponse = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let content = chatResponse.choices.first?.message.content else {
            throw BailianError.emptyContent
        }

        let candidates = try parseCandidates(from: content)
        let titleFiltered = filteredPoemCandidates(candidates, imageTitle: image.title, lineIndex: lineIndex)
        let metered = strictlyMeteredCandidates(titleFiltered, fallback: fallback, characterCount: poemForm.characterCount)
        return metered.map { $0.poemScript(script) }
    }

    private func candidateCacheKey(
        mood: MoodSeed,
        image: ImageSeed,
        lineIndex: Int,
        selectedLines: [String],
        fallback: [String],
        poemForm: PoemFormSpec,
        script: PoemScript
    ) -> String {
        [
            mood.id,
            mood.title,
            image.id,
            image.title,
            "\(lineIndex)",
            selectedLines.joined(separator: "|"),
            fallback.joined(separator: "|"),
            poemForm.id,
            "strict-meter-v2-\(poemForm.characterCount)",
            script.rawValue
        ].joined(separator: "||")
    }

    func generateImageSeeds(
        mood: MoodSeed,
        fallback: [ImageSeed],
        excluding excludedTitles: [String] = [],
        script: PoemScript = .traditional
    ) async throws -> [ImageSeed] {
        guard config.isUsable else {
            throw BailianError.missingConfig
        }

        var request = URLRequest(url: config.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(
            ChatRequest(
                model: config.model,
                messages: [
                    .init(role: "system", content: imageSeedSystemPrompt),
                    .init(role: "user", content: imageSeedUserPrompt(
                        mood: mood,
                        fallback: fallback,
                        excludedTitles: excludedTitles,
                        script: script
                    ))
                ],
                temperature: 0.95
            )
        )

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BailianError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw BailianError.httpStatus(httpResponse.statusCode)
        }

        let chatResponse = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let content = chatResponse.choices.first?.message.content else {
            throw BailianError.emptyContent
        }

        let titles = try parseCandidates(from: content)
            .map { String($0.prefix(6)) }
            .filter { !$0.isEmpty && !excludedTitles.contains($0.poemScript(script)) }

        return Array(titles.prefix(3).enumerated()).map { index, title in
            let convertedTitle = title.poemScript(script)
            return ImageSeed(id: "ai-\(Int(Date().timeIntervalSince1970))-\(index)-\(convertedTitle)", title: convertedTitle, subtitle: "")
        }
    }

    func generateMoodOptions(
        level: Int,
        l1: String,
        l2: String?,
        fallback: [String],
        maxCharacters: Int,
        script: PoemScript = .traditional
    ) async throws -> [String] {
        guard config.isUsable else {
            throw BailianError.missingConfig
        }

        var request = URLRequest(url: config.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(
            ChatRequest(
                model: config.model,
                messages: [
                    .init(role: "system", content: moodOptionSystemPrompt),
                    .init(role: "user", content: moodOptionUserPrompt(
                        level: level,
                        l1: l1,
                        l2: l2,
                        fallback: fallback,
                        maxCharacters: maxCharacters,
                        script: script
                    ))
                ],
                temperature: 0.9
            )
        )

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BailianError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw BailianError.httpStatus(httpResponse.statusCode)
        }

        let chatResponse = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let content = chatResponse.choices.first?.message.content else {
            throw BailianError.emptyContent
        }

        let options = try parseCandidates(from: content)
            .map { normalizedMoodOption($0, maxCharacters: maxCharacters).poemScript(script) }
            .filter { !$0.isEmpty }

        return Array(options.prefix(8))
    }

    private var systemPrompt: String {
        """
        你是一个帮助用户"择诗"的古典中文诗歌助手，精通近体诗格律。
        你的任务不是写完整诗，而是为当前第几句生成 3 个候选句。
        语言要像现代人能读懂的古诗：清楚、温柔、有画面，但不要晦涩。
        少用典故、少用生僻字、少用艰深倒装，不要为了古风而牺牲可懂。

        格律基本规则（必须遵守）：
        - 押韵：偶数句（第二、四、六、八句）末字必须押平声韵，且全诗韵脚用同一韵部（参考平水韵）。第一句可押可不押。奇数句（第三、五、七句）末字用仄声。
        - 平仄：遵循"一三五不论，二四六分明"的基本原则。句内平仄交替，联内对句平仄相对，联间邻句平仄相粘。
        - 五言基本句式：仄仄平平仄、平平仄仄平、平平平仄仄、仄仄仄平平。
        - 七言基本句式：平平仄仄平平仄、仄仄平平仄仄平、仄仄平平平仄仄、平平仄仄仄平平。
        - 允许合理的变格（如拗救），但要避免孤平和三平尾。
        - 律诗颔联和颈联需要对仗。

        每句只保留汉字，不要标点，不要解释。
        只输出 JSON，格式为 {"candidates":["候选一","候选二","候选三"]}。
        """
    }

    private var imageSeedSystemPrompt: String {
        """
        你是一个为诗歌 App 生成“今日诗引”的助手。
        诗引是用户进入写诗前选择的短意境，不是完整诗句。
        每个诗引 2 到 6 个汉字，要有画面感、情绪感、可继续生发成古诗。
        不要标点，不要解释，不要现代口语。
        只输出 JSON，格式为 {"candidates":["诗引一","诗引二","诗引三"]}。
        """
    }

    private var moodOptionSystemPrompt: String {
        """
        你是一个为诗歌 App 拆解用户当下心绪的助手。
        选项要短、含蓄、覆盖面不同，适合继续生成古典中文诗意。
        尽量使用现实处境相关的短语，不要标点，不要解释，不要重复。
        只输出 JSON，格式为 {"candidates":["选项一","选项二","选项三","选项四","选项五","选项六","选项七","选项八"]}。
        """
    }

    private func imageSeedUserPrompt(
        mood: MoodSeed,
        fallback: [ImageSeed],
        excludedTitles: [String],
        script: PoemScript
    ) -> String {
        """
        今日心绪：\(mood.title)
        用户选择的心绪标签：\(mood.tags.joined(separator: "、"))
        今日日期：\(Date())
        风格参考：\(fallback.map(\.title).joined(separator: " / "))
        最近已经出现过，请避开：\(excludedTitles.suffix(18).joined(separator: " / "))
        字形偏好：\(script.promptName)

        请生成 3 个不同方向的诗引：
        1. 一个偏景物
        2. 一个偏身体感或当下情绪
        3. 一个偏转念或余味
        每个诗引都要能回应用户选择的心绪标签，不要重复参考和避开列表里的表达。
        """
    }

    private func moodOptionUserPrompt(
        level: Int,
        l1: String,
        l2: String?,
        fallback: [String],
        maxCharacters: Int,
        script: PoemScript
    ) -> String {
        let levelGoal: String
        let levelRules: String
        if level == 2 {
            levelGoal = "随情绪追问现实事件大类"
            levelRules = """
            第二层要生成“因何而起”的大类，例如职场、关系、家庭、城市、独处、等待、失信、内耗等方向。
            不要太具体到某一个瞬间，留给第三层继续细化。
            """
        } else {
            levelGoal = "选择此刻所在地点"
            levelRules = """
            第三层只生成“身在何处”的地点、场所或空间锚点，例如案前灯下、通勤路上、城市窗边、家中一隅。
            不要生成具体一事，不要写动作或事件，例如等待太久、会议之后、收到消息、发生争吵都不合格。
            地点要能回应已选牵挂，并适合继续生发成古典中文诗意。
            """
        }

        return """
        当前层级：\(levelGoal)
        已选心绪：\(l1)
        已选牵挂：\(l2 ?? "未选")
        本地参考：\(fallback.joined(separator: " / "))
        字形偏好：\(script.promptName)

        \(levelRules)
        请生成 8 个彼此差异明显的选项。
        每个选项最多 \(maxCharacters) 个汉字，越接近 \(maxCharacters) 个字越好，不能超过 \(maxCharacters) 个字。
        输出必须使用\(script.promptName)。
        """
    }

    private func normalizedMoodOption(_ value: String, maxCharacters: Int) -> String {
        let visibleCharacters = value.filter { character in
            !character.isWhitespace && !character.isNewline
        }
        return String(visibleCharacters.prefix(maxCharacters))
    }

    private func userPrompt(
        mood: MoodSeed,
        image: ImageSeed,
        lineIndex: Int,
        selectedLines: [String],
        fallback: [String],
        poemForm: PoemFormSpec,
        script: PoemScript
    ) -> String {
        let role = poemForm.role(for: lineIndex)
        let isEvenLine = (lineIndex + 1) % 2 == 0
        let isFirstLine = lineIndex == 0
        let rhymeHint: String
        if isEvenLine {
            let existingRhymes = selectedLines.enumerated()
                .filter { ($0.offset + 1) % 2 == 0 }
                .compactMap { $0.element.last.map(String.init) }
            if existingRhymes.isEmpty {
                rhymeHint = "本句是偶数句，末字必须是平声字，作为全诗的韵脚。"
            } else {
                rhymeHint = "本句是偶数句，末字必须押平声韵，与前面的韵脚「\(existingRhymes.joined(separator: "、"))」同韵部（平水韵）。"
            }
        } else if isFirstLine {
            rhymeHint = "本句是第一句，末字可平可仄。若选择平声结尾则视为入韵，后续偶数句须与之同韵部。"
        } else {
            rhymeHint = "本句是奇数句，末字必须用仄声字，不押韵。"
        }
        let structureHint = poemForm.structure == .lushi
            ? "这是一首\(poemForm.displayName)，共\(poemForm.lineCount)句。颔联（第3-4句）和颈联（第5-6句）须对仗，但不要为了对仗牺牲自然。"
            : "这是一首\(poemForm.displayName)，共\(poemForm.lineCount)句，起承转合要清楚。"
        let moodPath = mood.tags.enumerated().map { index, tag in
            switch index {
            case 0:
                return "第一题情绪：\(tag)"
            case 1:
                return "第二题缘由：\(tag)"
            case 2:
                return "第三题地点：\(tag)"
            default:
                return tag
            }
        }.joined(separator: "；")

        return """
        心绪路径：\(moodPath.isEmpty ? mood.title : moodPath)
        題目：\(image.title)
        詩式：\(poemForm.displayName)
        当前：\(role)
        结构：\(structureHint)
        已选句：\(selectedLines.isEmpty ? "无" : selectedLines.joined(separator: " / "))
        固定样例风格：\(fallback.joined(separator: " / "))
        字形偏好：\(script.promptName)

        押韵提示：\(rhymeHint)

        请生成 3 个候选句。要求：
        1. 每句必须正好 \(poemForm.characterCount) 个汉字，不是最多，不是大约，是严格等于 \(poemForm.characterCount)。
        2. 只计算汉字；不要出现标点、空格、英文、数字或解释。若多于或少于 \(poemForm.characterCount) 个汉字，就是无效输出。
        3. 三句气质要不同：一平实清楚，一有画面，一更有情绪。
        4. 必须能和已选句自然连成一首\(poemForm.displayName)。
        4a. 平仄必须合律：句内平仄交替，和已选句之间平仄相对或相粘。避免孤平、三平尾、三仄尾。
        5. 題目只是诗的引子，不是诗句素材。尤其第一句不得直接复述、改写或拆用題目，不能包含完整題目，也不要连续使用題目中的两个以上关键字。
        6. 优先使用日常可感的词，如风、灯、雨、路、窗、书、饭桌、城市、归家；少用冷僻意象和抽象词。
        7. 输出必须使用\(script.promptName)。
        """
    }

    private func parseCandidates(from content: String) throws -> [String] {
        let cleaned = content
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let data = cleaned.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(CandidateResponse.self, from: data) {
            return sanitize(decoded.candidates)
        }

        guard let start = cleaned.firstIndex(of: "{"),
              let end = cleaned.lastIndex(of: "}") else {
            throw BailianError.unparseableContent
        }

        let jsonSlice = String(cleaned[start...end])
        if let data = jsonSlice.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(CandidateResponse.self, from: data) {
            return sanitize(decoded.candidates)
        }

        throw BailianError.unparseableContent
    }

    private func sanitize(_ candidates: [String]) -> [String] {
        candidates
            .map { candidate in
                candidate.filter { character in
                    String(character).range(of: #"\p{Han}"#, options: .regularExpression) != nil
                }
            }
            .filter { !$0.isEmpty }
    }

    private func filteredPoemCandidates(_ candidates: [String], imageTitle: String, lineIndex: Int) -> [String] {
        let titleCharacters = hanCharacters(in: imageTitle)
        guard lineIndex == 0, !titleCharacters.isEmpty else { return candidates }

        var result: [String] = []
        for candidate in candidates where !isTooCloseToTitle(candidate, titleCharacters: titleCharacters) {
            if !result.contains(candidate) {
                result.append(candidate)
            }
        }
        return result
    }

    private func strictlyMeteredCandidates(_ candidates: [String], fallback: [String], characterCount: Int) -> [String] {
        var result: [String] = []
        for candidate in candidates + fallback where hanCharacters(in: candidate).count == characterCount {
            if !result.contains(candidate) {
                result.append(candidate)
            }
            if result.count == 3 {
                break
            }
        }
        return result
    }

    private func isTooCloseToTitle(_ candidate: String, titleCharacters: [Character]) -> Bool {
        let candidateCharacters = hanCharacters(in: candidate)
        guard !candidateCharacters.isEmpty else { return true }

        let title = String(titleCharacters)
        let candidateText = String(candidateCharacters)
        if candidateText.contains(title) {
            return true
        }

        let sharedCount = Set(candidateCharacters).intersection(Set(titleCharacters)).count
        if sharedCount >= max(3, titleCharacters.count / 2) {
            return true
        }

        for index in titleCharacters.indices.dropLast() {
            let pair = String([titleCharacters[index], titleCharacters[titleCharacters.index(after: index)]])
            if candidateText.contains(pair) {
                return true
            }
        }

        return false
    }

    private func hanCharacters(in text: String) -> [Character] {
        text.filter { character in
            String(character).range(of: #"\p{Han}"#, options: .regularExpression) != nil
        }
    }

    /// Generate literary pen names (雅号) for the seal stamp.
    func generatePenNames(existingName: String?) async throws -> [String] {
        guard config.isUsable else {
            throw BailianError.missingConfig
        }

        let systemPrompt = """
        你是一个帮助用户起文人雅号的古典文学助手。
        雅号要有古典韵味，像"东坡居士""易安居士""青莲居士""六一居士"这样。
        每个雅号必须恰好 4 个汉字，不要标点，不要解释。
        只输出 JSON，格式为 {"candidates":["雅号一","雅号二","雅号三"]}。
        """

        let userPrompt: String
        if let name = existingName, !name.isEmpty {
            userPrompt = "我叫「\(name)」，帮我起 3 个四字文人雅号，可以和我的名字有关联，也可以随性而起。"
        } else {
            userPrompt = "帮我随机起 3 个四字文人雅号，风格各异，有的典雅，有的洒脱，有的清幽。"
        }

        var request = URLRequest(url: config.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(
            ChatRequest(
                model: config.model,
                messages: [
                    .init(role: "system", content: systemPrompt),
                    .init(role: "user", content: userPrompt)
                ],
                temperature: 1.0
            )
        )

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BailianError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw BailianError.httpStatus(httpResponse.statusCode)
        }

        let chatResponse = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let content = chatResponse.choices.first?.message.content else {
            throw BailianError.emptyContent
        }

        let candidates = try parseCandidates(from: content)
            .filter { $0.count == 4 }
        return Array(candidates.prefix(3))
    }
}

struct BailianConfig {
    let endpoint: URL
    let model: String
    let apiKey: String

    var isUsable: Bool {
        !apiKey.isEmpty
    }

    static func load() -> BailianConfig {
        let defaults = BailianConfig(
            endpoint: URL(string: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions")!,
            model: "qwen-plus",
            apiKey: ""
        )

        guard let url = Bundle.main.url(forResource: "AIConfig", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String] else {
            return defaults
        }

        return BailianConfig(
            endpoint: plist["endpoint"].flatMap(URL.init(string:)) ?? defaults.endpoint,
            model: plist["model"] ?? defaults.model,
            apiKey: plist["apiKey"] ?? defaults.apiKey
        )
    }
}

enum BailianError: Error {
    case missingConfig
    case invalidResponse
    case httpStatus(Int)
    case emptyContent
    case unparseableContent
}

private struct ChatRequest: Encodable {
    let model: String
    let messages: [ChatMessage]
    let temperature: Double
}

private struct ChatMessage: Codable {
    let role: String
    let content: String
}

private struct ChatResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: ChatMessage
    }
}

private struct CandidateResponse: Decodable {
    let candidates: [String]
}
