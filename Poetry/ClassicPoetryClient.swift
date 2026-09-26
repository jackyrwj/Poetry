import Foundation

struct ClassicPoetryClient: Sendable {
    private let session: URLSession
    private let baseURL = URL(string: "https://poetry.palemoky.com")!

    init(session: URLSession = .shared) {
        self.session = session
    }

    func search(query: String, script: PoemScript) async throws -> [ClassicPoem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var components = URLComponents(url: baseURL.appending(path: "api/search"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "q", value: trimmed),
            URLQueryItem(name: "lang", value: script == .traditional ? "zh-Hant" : "zh-Hans")
        ]
        guard let url = components?.url else { throw ClassicPoetryError.invalidURL }

        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw ClassicPoetryError.invalidResponse
        }
        guard (200..<300).contains(response.statusCode) else {
            throw ClassicPoetryError.httpStatus(response.statusCode)
        }

        let result = try JSONDecoder().decode(SearchResponse.self, from: data)
        return result.data.prefix(30).map { item in
            ClassicPoem(
                id: "poetry-spring-\(item.id)",
                title: item.title,
                author: item.author.name,
                dynasty: item.dynasty.name,
                form: item.type.name,
                lines: item.content,
                appreciation: nil,
                translation: nil,
                tags: [],
                backgroundRawValue: PoemBackground.suggested(for: item.content.joined()).rawValue,
                origin: .poetrySpring
            )
        }
    }

}

private struct SearchResponse: Decodable {
    let data: [SearchPoem]
}

private struct SearchPoem: Decodable {
    let id: Int
    let title: String
    let content: [String]
    let author: NamedValue
    let dynasty: NamedValue
    let type: NamedValue
}

private struct NamedValue: Decodable {
    let name: String
}

enum ClassicPoetryError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return AppLanguage.copy("搜索地址无效", "The search address is invalid")
        case .invalidResponse:
            return AppLanguage.copy("没有收到有效的诗词数据", "The poetry library returned invalid data")
        case .httpStatus:
            return AppLanguage.copy("诗词库暂时无法访问", "The poetry library is unavailable right now")
        }
    }
}
