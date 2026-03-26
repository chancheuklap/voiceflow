import AppKit
import Foundation

/// 异步文本替换 — ASR 结果插入后，等 LLM 润色完成再替换
/// 降级策略：如果用户已移动光标，改为复制到剪贴板
class AsyncReplacer {
    private let inserter: TextInserter

    init(inserter: TextInserter) {
        self.inserter = inserter
    }

    /// 插入 ASR 原文并异步等待 LLM 润色结果替换
    /// 返回最终插入的文本（润色后的或原始的）
    func insertAndPolish(
        asrText: String,
        llmProvider: LLMProvider?,
        preset: Preset?,
        onPolishStart: (() -> Void)? = nil,
        onComplete: @escaping (String, Bool) -> Void // (最终文本, 是否润色成功)
    ) {
        // 如果没有 LLM 或没有预设，直接插入原文
        guard let provider = llmProvider, let preset = preset else {
            inserter.insert(text: asrText)
            onComplete(asrText, false)
            return
        }

        // 先插入 ASR 原文（用户立刻看到结果）
        inserter.insert(text: asrText)
        onPolishStart?()

        // 异步润色
        Task {
            do {
                let polished = try await provider.process(text: asrText, preset: preset)

                if polished != asrText && !polished.isEmpty {
                    // 润色有变化，复制到剪贴板并提示用户
                    // （V1 保守策略：不做原地替换，避免光标已移动导致替换错误）
                    DispatchQueue.main.async {
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(polished, forType: .string)
                        onComplete(polished, true)
                    }
                } else {
                    DispatchQueue.main.async {
                        onComplete(asrText, false)
                    }
                }
            } catch {
                print("LLM error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    onComplete(asrText, false)
                }
            }
        }
    }
}
