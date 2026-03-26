import Foundation

/// 内置 LLM 预设 — 定义 system prompt 和 user prompt 模板
/// 借鉴 Koe 的模板变量设计：{{asr_text}} 为 ASR 原文
public struct Preset {
    public let id: String
    public let name: String
    public let systemPrompt: String
    public let userPromptTemplate: String // 包含 {{asr_text}} 占位符

    public func buildUserPrompt(asrText: String) -> String {
        return userPromptTemplate.replacingOccurrences(of: "{{asr_text}}", with: asrText)
    }
}

public struct PresetManager {
    public static let presets: [Preset] = [
        Preset(
            id: "grammar",
            name: "语法纠错",
            systemPrompt: """
            你是一个中文文本校对助手。你的任务是修正语音识别产生的错误，包括：
            - 修正错别字和同音字错误
            - 修正标点符号
            - 修正语病和语序不通顺的地方
            - 去除口头禅和语气词（如"嗯""啊""那个""就是"）
            保持原文的意思和风格不变，只做最小限度的修正。
            直接输出修正后的文本，不要任何解释。
            """,
            userPromptTemplate: "{{asr_text}}"
        ),
        Preset(
            id: "formal",
            name: "正式化",
            systemPrompt: """
            你是一个中文文本改写助手。将口语化的文本改写为正式的书面语，适合用于邮件、报告或文档。
            要求：
            - 去除所有口头禅和语气词
            - 将口语表达改为书面表达
            - 保持原文的核心意思
            - 使用规范的标点符号
            直接输出改写后的文本，不要任何解释。
            """,
            userPromptTemplate: "{{asr_text}}"
        ),
        Preset(
            id: "simplify",
            name: "简化",
            systemPrompt: """
            你是一个中文文本精简助手。将冗长的口语表达精简为简洁的文字。
            要求：
            - 去除重复和冗余的表达
            - 保留核心信息
            - 使用简短的句式
            直接输出精简后的文本，不要任何解释。
            """,
            userPromptTemplate: "{{asr_text}}"
        ),
    ]

    /// 通过 ID 查找预设，找不到返回 nil（表示跳过 LLM 处理）
    public static func find(id: String?) -> Preset? {
        guard let id = id, id != "none" else { return nil }
        return presets.first { $0.id == id }
    }
}
