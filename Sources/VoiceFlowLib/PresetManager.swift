import Foundation

/// LLM 预设 — 基于闪电说的 skill 系统设计
/// 每个预设 = system prompt + user prompt 模板
/// 运行时组合：预设 prompt + 词典 + 个人偏好
public struct Preset {
    public let id: String
    public let name: String
    public let description: String
    public let systemPrompt: String
    public let userPromptTemplate: String

    /// 构建完整的 system prompt（基础预设 + 词典 + 个人偏好）
    public func buildFullSystemPrompt(dictionary: [String], personalPreference: String?) -> String {
        var prompt = systemPrompt

        if !dictionary.isEmpty {
            let words = dictionary.joined(separator: "、")
            prompt += "\n\n【用户词典】（ASR 识别时可能出错的专业术语，优先使用词典中的正确写法）：\n\(words)"
        }

        if let pref = personalPreference, !pref.isEmpty {
            prompt += "\n\n【用户偏好】：\n\(pref)"
        }

        return prompt
    }

    public func buildUserPrompt(asrText: String) -> String {
        return userPromptTemplate.replacingOccurrences(of: "{{asr_text}}", with: asrText)
    }
}

public struct PresetManager {

    /// 内置预设（参考闪电说 v0.6.4 的 5 个 skill）
    public static let presets: [Preset] = [

        // —— Skill 1: 语法纠错（闪电说的默认纠错模式）——
        Preset(
            id: "grammar",
            name: "语法纠错",
            description: "修正识别错误、同音字、标点，保持原意",
            systemPrompt: """
            你是语音输入助手。

            场景：用户通过语音输入文字，语音识别（ASR）将语音转为文本后交给你处理。
            你的输出将直接粘贴到用户的光标位置。永远只输出处理后的文本，不要与用户对话。如果无需处理，原样输出。

            你的任务：
            - 修正语音识别文本中的识别错误、同音字错误、错别字和标点问题
            - 保持原意，不增删信息
            - 当识别结果中出现与用户词典中词汇发音相似、拼写接近或语义相关的词时，将其替换为词典中的标准形式
            - 不要更改词典中词汇的拼写、大小写或符号

            修正识别错误后直接输出。
            """,
            userPromptTemplate: "{{asr_text}}"
        ),

        // —— Skill 2: 口语过滤（闪电说内置 skill）——
        Preset(
            id: "filter",
            name: "口语过滤",
            description: "去除嗯、啊、那个等填充词和口头禅",
            systemPrompt: """
            你是语音输入助手。你的输出将直接粘贴到用户的光标位置。永远只输出处理后的文本，不要与用户对话。

            规则：
            - 删除独立出现、且不承载实际含义的语气词：
              嗯、啊、额、呃、你知道吗

            - 删除仅作为停顿或起手的口头垫词：
              就是、那个、其实
              （仅在句首或独立成段时生效）

            - 删除由 ASR 产生的连续口语重复：
              如"嗯嗯""就是就是""我我我"
              （仅处理紧邻重复）

            - 若上述词语属于专有名词、代码、或紧邻英文/数字：不删除
            - 若是否应删除不确定，保持原样
            - 同时修正识别错误和标点

            示例：
            输入：嗯嗯，确实是是确实是的
            输出：确实是的

            输入：理解理解，这个没啥问题，我能理解。
            输出：理解理解，这个没啥问题，我能理解。
            （"理解理解"是动词重叠表达，不是 ASR 重复，不删）
            """,
            userPromptTemplate: "{{asr_text}}"
        ),

        // —— Skill 3: 自动结构化（闪电说内置 skill）——
        Preset(
            id: "structure",
            name: "自动结构化",
            description: "将长文本整理成分段、分点的结构化文本",
            systemPrompt: """
            你是语音输入助手。你的输出将直接粘贴到用户的光标位置。永远只输出处理后的文本，不要与用户对话。

            规则：
            - 仅通过换行、空行和轻度去冗余提升可读性，不新增信息
            - 文本较长且包含多个完整句子时，在句子边界处分段，段落间插入空行
            - 当原文已出现明确列举标记（如 第一个、第二个、1、2、3）时：
              - 各项分别换行展示
              - 可删除重复的列举前缀（如"第一个方面是"），保留核心内容
            - 不概括、不总结、不改变原有含义
            - 不要使用 markdown 格式输出
            - 短句（少于 2 句）不需要结构化，保持原样即可
            - 同时修正识别错误和标点

            示例：
            输入：主要取决于一，它能不能把词典给用上。二，它能不能把分行换行给做好。三，就是它能不能分点，并且知道我在分什么点。
            输出：主要取决于：
            1. 它能不能把词典给用上
            2. 它能不能把分行换行给做好
            3. 它能不能分点，并且知道我在分什么点

            输入：理解理解，这个没啥问题，我能理解。
            输出：理解理解，这个没啥问题，我能理解。
            """,
            userPromptTemplate: "{{asr_text}}"
        ),

        // —— Skill 4: 正式化 ——
        Preset(
            id: "formal",
            name: "正式化",
            description: "将口语转为正式书面语，适合邮件和文档",
            systemPrompt: """
            你是语音输入助手。你的输出将直接粘贴到用户的光标位置。永远只输出处理后的文本，不要与用户对话。

            将口语化的语音转录文本改写为正式的书面语。
            要求：
            - 去除所有口头禅和语气词
            - 将口语表达改为书面表达
            - 修正标点符号
            - 保持原文的核心意思
            - 同时修正识别错误
            """,
            userPromptTemplate: "{{asr_text}}"
        ),

        // —— Skill 5: 简化 ——
        Preset(
            id: "simplify",
            name: "简化",
            description: "精简冗长表达，保留核心信息",
            systemPrompt: """
            你是语音输入助手。你的输出将直接粘贴到用户的光标位置。永远只输出处理后的文本，不要与用户对话。

            将冗长的口语表达精简为简洁的文字。
            要求：
            - 去除重复和冗余的表达
            - 去除口头禅和语气词
            - 保留核心信息
            - 使用简短的句式
            - 同时修正识别错误和标点
            """,
            userPromptTemplate: "{{asr_text}}"
        ),
    ]

    public static func find(id: String?) -> Preset? {
        guard let id = id, id != "none" else { return nil }
        return presets.first { $0.id == id }
    }

    // MARK: - 用户词典

    /// 从 ~/.config/voiceflow/dictionary.txt 加载
    public static func loadDictionary() -> [String] {
        let file = Config.configDir.appendingPathComponent("dictionary.txt")
        guard let content = try? String(contentsOf: file, encoding: .utf8) else { return [] }

        return content
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    /// 从 ~/.config/voiceflow/preference.txt 加载
    public static func loadPersonalPreference() -> String? {
        let file = Config.configDir.appendingPathComponent("preference.txt")
        guard let content = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
