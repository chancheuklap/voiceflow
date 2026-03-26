import Foundation

/// ASR 引擎协议 — 所有语音识别后端必须实现此接口
/// 设计参考 Voxt TranscriberProtocol，接口隔离 ASR 实现细节
public protocol ASREngine: AnyObject {
    /// 建立连接（WebSocket 或初始化本地模型）
    /// - Parameter terms: 用户词典词条，用于 ASR 引擎的自定义词汇偏置
    func connect(terms: [String]) async throws
    /// 发送一段音频数据（PCM 16-bit, 16kHz, mono）
    func sendAudio(_ data: Data) async throws
    /// 通知 ASR 引擎音频输入结束
    func finishInput() async throws
    /// 关闭连接/释放资源
    func close() async throws

    /// 收到中间识别结果（实时更新，可能被后续结果覆盖）
    var onInterimText: ((String) -> Void)? { get set }
    /// 收到最终识别结果（确定的，累积拼接）
    var onFinalText: ((String) -> Void)? { get set }
    /// 识别完成（所有 final tokens 已返回）
    var onComplete: ((String) -> Void)? { get set }
    /// 发生错误
    var onError: ((Error) -> Void)? { get set }
}

public enum ASRError: LocalizedError {
    case connectionFailed(String)
    case authenticationFailed
    case disconnected
    case timeout

    public var errorDescription: String? {
        switch self {
        case .connectionFailed(let detail): return "ASR 连接失败: \(detail)"
        case .authenticationFailed: return "API Key 无效，请检查设置"
        case .disconnected: return "连接中断"
        case .timeout: return "连接超时"
        }
    }
}
