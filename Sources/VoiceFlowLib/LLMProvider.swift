import Foundation

/// LLM 后处理协议 — 所有文本润色服务商实现此接口
public protocol LLMProvider {
    func process(text: String, preset: Preset) async throws -> String
}

public enum LLMError: LocalizedError {
    case notConfigured
    case requestFailed(String)
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .notConfigured: return "LLM API Key 未配置"
        case .requestFailed(let detail): return "润色失败: \(detail)"
        case .invalidResponse: return "润色返回格式异常"
        }
    }
}
