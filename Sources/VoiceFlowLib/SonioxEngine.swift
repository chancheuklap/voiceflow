import Foundation

/// Soniox 实时语音识别引擎 — WebSocket streaming
/// API 参考: https://soniox.com/docs/stt/api-reference/websocket-api
public class SonioxEngine: ASREngine {
    private let apiKey: String
    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession?
    private var finalTokens: [String] = []
    private var receiveTask: Task<Void, Never>?
    private var isFinished = false

    public var onInterimText: ((String) -> Void)?
    public var onFinalText: ((String) -> Void)?
    public var onComplete: ((String) -> Void)?
    public var onError: ((Error) -> Void)?

    public init(apiKey: String) {
        self.apiKey = apiKey
    }

    public func connect() async throws {
        finalTokens = []
        isFinished = false

        let url = URL(string: "wss://stt-rt.soniox.com/transcribe-websocket")!
        session = URLSession(configuration: .default)
        webSocketTask = session?.webSocketTask(with: url)
        webSocketTask?.resume()

        // 发送配置消息（必须是第一条消息）
        let config: [String: Any] = [
            "api_key": apiKey,
            "model": "stt-rt-v4",
            "audio_format": "pcm_s16le",
            "sample_rate": 16000,
            "num_channels": 1,
            "language_hints": ["zh", "en"],
        ]

        let configData = try JSONSerialization.data(withJSONObject: config)
        let configString = String(data: configData, encoding: .utf8)!
        try await webSocketTask?.send(.string(configString))

        // 启动后台接收循环
        startReceiving()
    }

    public func sendAudio(_ data: Data) async throws {
        guard let ws = webSocketTask else {
            throw ASRError.connectionFailed("WebSocket not connected")
        }
        try await ws.send(.data(data))
    }

    public func finishInput() async throws {
        // 发送空帧表示音频结束
        try await webSocketTask?.send(.string(""))
    }

    public func close() async throws {
        isFinished = true
        receiveTask?.cancel()
        receiveTask = nil
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        session?.invalidateAndCancel()
        session = nil
        onInterimText = nil
        onFinalText = nil
        onComplete = nil
        onError = nil
    }

    // MARK: - 后台接收循环

    private func startReceiving() {
        receiveTask = Task { [weak self] in
            guard let self = self else { return }

            while !Task.isCancelled {
                guard let ws = self.webSocketTask else { break }

                do {
                    let message = try await ws.receive()

                    switch message {
                    case .string(let text):
                        self.handleResponse(text)
                    case .data(let data):
                        if let text = String(data: data, encoding: .utf8) {
                            self.handleResponse(text)
                        }
                    @unknown default:
                        break
                    }
                } catch {
                    if !Task.isCancelled && !self.isFinished {
                        DispatchQueue.main.async {
                            self.onError?(ASRError.disconnected)
                        }
                    }
                    break
                }
            }
        }
    }

    private func handleResponse(_ jsonString: String) {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        // 检查错误
        if let errorCode = json["error_code"] as? Int {
            let errorMessage = json["error_message"] as? String ?? "Unknown error"

            // "No audio received" = 用户快速按松没说话，静默处理
            if errorMessage.contains("No audio received") {
                isFinished = true
                receiveTask?.cancel()
                DispatchQueue.main.async { [weak self] in
                    self?.onComplete?("")
                }
                return
            }

            DispatchQueue.main.async { [weak self] in
                if errorCode == 401 {
                    self?.onError?(ASRError.authenticationFailed)
                } else {
                    self?.onError?(ASRError.connectionFailed("\(errorCode): \(errorMessage)"))
                }
            }
            return
        }

        // 处理 tokens
        if let tokens = json["tokens"] as? [[String: Any]] {
            var interimParts: [String] = []

            for token in tokens {
                guard let text = token["text"] as? String else { continue }
                let isFinal = token["is_final"] as? Bool ?? false

                if isFinal {
                    finalTokens.append(text)
                } else {
                    interimParts.append(text)
                }
            }

            let finalText = finalTokens.joined()
            let interimText = interimParts.joined()

            // 回调: final 文字（确定的，累积）
            if !finalText.isEmpty {
                DispatchQueue.main.async { [weak self] in
                    self?.onFinalText?(finalText)
                }
            }

            // 回调: interim 文字（final + 当前 interim 拼接，用于实时显示）
            let displayText = finalText + interimText
            if !displayText.isEmpty {
                DispatchQueue.main.async { [weak self] in
                    self?.onInterimText?(displayText)
                }
            }
        }

        // 检查是否完成
        if json["finished"] as? Bool == true {
            guard !isFinished else {
                print("[SonioxEngine] ⚠️ finished=true received AGAIN, ignoring (防止双重回调)")
                return
            }
            isFinished = true
            receiveTask?.cancel()
            let completeText = finalTokens.joined()
            print("[SonioxEngine] finished, total text length=\(completeText.count)")
            DispatchQueue.main.async { [weak self] in
                self?.onComplete?(completeText)
            }
        }
    }
}
