import Foundation

/// 内置 LLM 预设 — 定义 system prompt 和 user prompt 模板
/// 借鉴闪电说：词典 + 个人偏好 + 预设三层组合
public struct Preset {
    public let id: String
    public let name: String
    public let systemPrompt: String
    public let userPromptTemplate: String

    /// 构建完整的 system prompt（基础预设 + 词典 + 个人偏好）
    public func buildFullSystemPrompt(dictionary: [String], personalPreference: String?) -> String {
        var prompt = systemPrompt

        if !dictionary.isEmpty {
            let words = dictionary.joined(separator: "、")
            prompt += "\n\n用户词典（ASR 识别时可能出错的专业术语，请优先使用词典中的正确写法）：\n\(words)"
        }

        if let pref = personalPreference, !pref.isEmpty {
            prompt += "\n\n用户偏好：\n\(pref)"
        }

        return prompt
    }

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
            你是语音输入助手。用户通过语音输入文字，语音识别（ASR）将语音转为文本后交给你处理。\
            你的输出将直接粘贴到用户的光标位置。永远只输出处理后的文本，不要与用户对话。

            你的任务：
            - 修正语音识别文本中的识别错误、同音字错误、错别字
            - 修正标点符号，确保断句合理
            - 去除口头禅和语气词（嗯、啊、那个、就是、然后）
            - 当识别结果中出现与用户词典中词汇发音相似的词时，替换为词典中的标准形式
            - 保持原意，不增删信息
            """,
            userPromptTemplate: "{{asr_text}}"
        ),
        Preset(
            id: "formal",
            name: "正式化",
            systemPrompt: """
            你是语音输入助手。将口语化的语音转录文本改写为正式的书面语。

            要求：
            - 去除所有口头禅和语气词
            - 将口语表达改为书面表达
            - 修正标点符号
            - 保持原文的核心意思
            - 永远只输出处理后的文本，不要与用户对话
            """,
            userPromptTemplate: "{{asr_text}}"
        ),
        Preset(
            id: "simplify",
            name: "简化",
            systemPrompt: """
            你是语音输入助手。将冗长的口语表达精简为简洁的文字。

            要求：
            - 去除重复和冗余的表达
            - 去除口头禅和语气词
            - 保留核心信息
            - 使用简短的句式
            - 永远只输出处理后的文本，不要与用户对话
            """,
            userPromptTemplate: "{{asr_text}}"
        ),
    ]

    public static func find(id: String?) -> Preset? {
        guard let id = id, id != "none" else { return nil }
        return presets.first { $0.id == id }
    }

    // MARK: - 用户词典

    /// 从 ~/.config/voiceflow/dictionary.txt 加载用户词典
    /// 每行一个词，空行和 # 开头的行忽略
    public static func loadDictionary() -> [String] {
        let file = Config.configDir.appendingPathComponent("dictionary.txt")
        guard let content = try? String(contentsOf: file, encoding: .utf8) else { return [] }

        return content
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    /// 从 ~/.config/voiceflow/preference.txt 加载个人偏好
    public static func loadPersonalPreference() -> String? {
        let file = Config.configDir.appendingPathComponent("preference.txt")
        guard let content = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
