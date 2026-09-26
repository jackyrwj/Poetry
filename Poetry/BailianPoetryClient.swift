import Foundation

/// The reading app uses BaiLian only for optional literary utilities. The
/// Chinese composition candidate pipeline lives on the Chinese product branch.
struct BailianPoetryClient {
    private let config: BailianConfig
    private let session: URLSession

    init(config: BailianConfig = .load(), session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    func generatePenNames(existingName: String?) async throws -> [String] {
        let systemPrompt = """
        You create concise, literary pen names for a poetry app. Return exactly
        three distinct names, each at most four Chinese characters. Return JSON
        only, in the form {"candidates":["name one","name two","name three"]}.
        """
        let userPrompt = if let existingName, !existingName.isEmpty {
            "Create three literary Chinese pen names inspired by: \(existingName)"
        } else {
            "Create three literary Chinese pen names with distinct moods."
        }

        let candidates = try await requestCandidates(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            temperature: 1.0
        )
        return Array(candidates.filter { $0.count == 4 }.prefix(3))
    }

    func generateClassicAppreciation(poem: ClassicPoem, script: PoemScript) async throws -> String {
        let systemPrompt: String
        let userPrompt: String
        if AppLanguage.isEnglish {
            systemPrompt = """
            You are a careful, plain-spoken editor introducing classical Chinese poetry to general readers. Write one short paragraph of commentary. Discuss only imagery, language, structure, and feeling present in the poem; do not invent historical or biographical context. Write 100 to 160 words of natural English. Do not use a title, bullets, Markdown, or a disclaimer.
            """
            userPrompt = """
            Title: \(poem.title)
            Author: \(poem.dynasty) · \(poem.author)
            Form: \(poem.form)
            Original Chinese:
            \(poem.lines.joined(separator: "\n"))
            """
        } else {
            systemPrompt = """
            你是一位严谨、平实的中国古典诗词导读编辑。请为给定作品写一段适合普通读者的短赏析：只讨论作品中确实出现的意象、语言、结构与情感，不虚构创作背景或作者经历；长度 140 至 220 个汉字；不输出标题、项目符号、Markdown 或免责声明；输出使用\(script.promptName)。
            """
            userPrompt = """
            作品：\(poem.title)
            作者：\(poem.dynasty)·\(poem.author)
            体裁：\(poem.form)
            原文：\(poem.lines.joined(separator: "\n"))
            """
        }

        let text = try await requestText(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            temperature: 0.35
        )
        let cleaned = text
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { throw BailianError.emptyContent }
        return cleaned.poemScript(script)
    }

    private func requestCandidates(systemPrompt: String, userPrompt: String, temperature: Double) async throws -> [String] {
        let text = try await requestText(systemPrompt: systemPrompt, userPrompt: userPrompt, temperature: temperature)
        guard let data = text.data(using: .utf8),
              let response = try? JSONDecoder().decode(CandidateResponse.self, from: data) else {
            throw BailianError.unparseableContent
        }
        return response.candidates
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func requestText(systemPrompt: String, userPrompt: String, temperature: Double) async throws -> String {
        guard config.isUsable else { throw BailianError.missingConfig }

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
                temperature: temperature
            )
        )

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw BailianError.invalidResponse }
        guard (200..<300).contains(httpResponse.statusCode) else { throw BailianError.httpStatus(httpResponse.statusCode) }
        let chatResponse = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let content = chatResponse.choices.first?.message.content else { throw BailianError.emptyContent }
        return content
    }
}

struct BailianConfig {
    let endpoint: URL
    let model: String
    let apiKey: String

    var isUsable: Bool { !apiKey.isEmpty }

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
