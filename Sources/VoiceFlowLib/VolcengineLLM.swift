import Foundation

/// 豆包/火山引擎 LLM — OpenAI 兼容接口
/// 支持 Seed 系列模型的 thinking 控制
public class VolcengineLLM: LLMProvider {
    private let apiKey: String
    private let baseURL: String
    private let model: String

    /// 复用 URLSession（HTTP 连接池，避免每次请求重建 TLS）
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 2
        config.timeoutIntervalForRequest = 10
        return URLSession(configuration: config)
    }()

    public init(apiKey: String, baseURL: String, model: String) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.model = model
    }

    public func process(text: String, preset: Preset) async throws -> String {
        let url = URL(string: "\(baseURL)/chat/completions")!

        // 加载词典和个人偏好，组合成完整的 system prompt
        let dictionary = PresetManager.loadDictionary()
        let preference = PresetManager.loadPersonalPreference()
        let fullSystemPrompt = preset.buildFullSystemPrompt(
            dictionary: dictionary,
            personalPreference: preference
        )

        var body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": fullSystemPrompt],
                ["role": "user", "content": preset.buildUserPrompt(asrText: text)],
            ],
            "temperature": 0.3,
            "max_tokens": 256,
        ]

        // Seed 系列模型：关闭深度思考（文字纠错不需要推理链）
        if model.contains("seed") {
            body["thinking"] = ["type": "disabled"]
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            let respBody = String(data: data, encoding: .utf8) ?? ""
            throw LLMError.requestFailed("HTTP \(httpResponse.statusCode): \(respBody.prefix(200))")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw LLMError.invalidResponse
        }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
