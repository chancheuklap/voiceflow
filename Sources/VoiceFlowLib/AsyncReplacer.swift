import AppKit
import Foundation

/// 异步文本处理 — 等 LLM 润色完成后直接输出润色结果
/// 不先插入 ASR 原文，等润色完成后一次性插入最终结果
class AsyncReplacer {
    private let inserter: TextInserter

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
        // 无 LLM 或无预设 → 直接插入 ASR 原文
        guard let provider = llmProvider, let preset = preset else {
            inserter.insert(text: asrText)
            onComplete(asrText, false)
            return
        }

        // 有 LLM → 先显示"润色中"，等润色完成后插入
        onPolishStart?()

        Task {
            do {
                let polished = try await provider.process(text: asrText, preset: preset)
                let finalText = polished.isEmpty ? asrText : polished

                DispatchQueue.main.async {
                    self.inserter.insert(text: finalText)
                    onComplete(finalText, finalText != asrText)
                }
            } catch {
                print("LLM error: \(error.localizedDescription)")
                // 润色失败 → 插入 ASR 原文
                DispatchQueue.main.async {
                    self.inserter.insert(text: asrText)
                    onComplete(asrText, false)
                }
            }
        }
    }
}
