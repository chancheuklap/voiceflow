import AppKit
import Foundation

/// 异步文本处理 — 等 LLM 润色完成后直接输出润色结果
/// 策略：ASR 完成 → LLM 润色 → 插入最终文本到光标
/// 降级：LLM 失败 → 插入 ASR 原文
class AsyncReplacer {
    private let inserter: TextInserter
    private var currentTask: Task<Void, Never>?

    init(inserter: TextInserter) {
        self.inserter = inserter
    }

    /// 处理 ASR 文本：有 LLM 时先润色再插入，无 LLM 时直接插入
    func processAndInsert(
        asrText: String,
        llmProvider: LLMProvider?,
        preset: Preset?,
        onPolishStart: (() -> Void)? = nil,
        onComplete: @escaping (String, Bool) -> Void // (最终文本, 是否润色)
    ) {
        // 取消前一个未完成的 LLM 任务
        currentTask?.cancel()
        currentTask = nil

        // 无 LLM 或无预设 → 直接插入 ASR 原文
        guard let provider = llmProvider, let preset = preset else {
            inserter.insert(text: asrText)
            onComplete(asrText, false)
            return
        }

        // 有 LLM → 等润色完成后插入
        onPolishStart?()
        let startTime = Date()

        currentTask = Task {
            do {
                let polished = try await provider.process(text: asrText, preset: preset)
                let elapsed = Date().timeIntervalSince(startTime)

                guard !Task.isCancelled else { return }

                let finalText = polished.isEmpty ? asrText : polished
                print("[LLM] \(String(format: "%.2f", elapsed))s | \(finalText == asrText ? "无变化" : "已润色")")

                DispatchQueue.main.async {
                    self.inserter.insert(text: finalText)
                    onComplete(finalText, finalText != asrText)
                }
            } catch {
                guard !Task.isCancelled else { return }
                print("[LLM] error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.inserter.insert(text: asrText)
                    onComplete(asrText, false)
                }
            }
        }
    }
}
