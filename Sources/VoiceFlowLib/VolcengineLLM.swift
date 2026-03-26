import Foundation

/// 豆包/火山引擎 LLM — OpenAI 兼容接口
public class VolcengineLLM: LLMProvider {
    private let apiKey: String
    private let baseURL: String
    private let model: String

    public init(apiKey: String, baseURL: String, model: String) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.model = model
    }

    public func process(text: String, preset: Preset) async throws -> String {
        let url = URL(string: "\(baseURL)/chat/completions")!

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": preset.systemPrompt],
                ["role": "user", "content": preset.buildUserPrompt(asrText: text)],
            ],
            "temperature": 0.3,
            "max_tokens": 2048,
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw LLMError.requestFailed("HTTP \(httpResponse.statusCode): \(body.prefix(200))")
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
