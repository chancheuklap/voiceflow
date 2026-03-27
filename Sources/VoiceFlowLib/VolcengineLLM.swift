import Foundation

/// 豆包/火山引擎 LLM — OpenAI 兼容接口
/// 支持 Seed 系列模型的 thinking 控制
public class VolcengineLLM: LLMProvider {
    private let apiKey: String
    private let baseURL: String
    private let model: String

    /// 可重试的 HTTP 状态码（服务端临时故障）
    private let retryableStatusCodes: Set<Int> = [429, 500, 502, 503, 504]

    /// 复用 URLSession（HTTP 连接池，避免每次请求重建 TLS）
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 2
        config.timeoutIntervalForRequest = 10   // 包间沉默超时：防止 hang
        config.timeoutIntervalForResource = 30  // 总请求超时：30 秒
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

        // max_tokens 动态计算：至少 300，最多 1024，按输入字符数 ×3 估算
        let dynamicMaxTokens = min(1024, max(300, text.count * 3))

        var body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": fullSystemPrompt],
                ["role": "user", "content": preset.buildUserPrompt(asrText: text)],
            ],
            "temperature": 0.1,
            "max_tokens": dynamicMaxTokens,
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

        // 首次请求
        var (data, response) = try await session.data(for: request)

        // 遇到可重试状态码时，等 1 秒后重试一次
        if let httpResp = response as? HTTPURLResponse,
           retryableStatusCodes.contains(httpResp.statusCode) {
            try await Task.sleep(nanoseconds: 1_000_000_000)
            (data, response) = try await session.data(for: request)
        }

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
