# SPEC：LLM 管线优化

**状态**：待执行
**创建日期**：2026-03-27
**背景**：基于对 8 个开源竞品的源码分析 + 现有代码的静态审查，识别出若干影响正确性、可靠性和性能的问题。

---

## 问题清单（按优先级）

| # | 文件 | 严重程度 | 问题描述 |
|---|------|----------|---------|
| P0-1 | `PresetManager.swift:233` | 严重 | `buildCombinedPreset()` 按行首前缀过滤规则，导致 `filter` 技能的词汇表、`correction` 技能的标志词列表等关键内容在多技能合并时丢失 |
| P0-2 | `VolcengineLLM.swift:42` | 严重 | `max_tokens` 硬编码为 256，`structure` 技能处理长段落时输出被截断，且无任何报错 |
| P1-1 | `VolcengineLLM.swift:14` | 中 | 超时配置错误：`timeoutIntervalForRequest=10` 控制包间沉默，不是总超时；`timeoutIntervalForResource` 未设置（默认 7 天），挂起请求永不超时 |
| P1-2 | `VolcengineLLM.swift:56` | 中 | 无重试机制，一次 429/503 或网络抖动直接降级为原始 ASR 文本 |
| P1-3 | `VolcengineLLM.swift:28` | 中 | 词典和偏好文件每次 LLM 调用都同步读磁盘，且在一次录音中被调用 2 次（ASR 连接时 + LLM 处理时） |
| P1-4 | `AppDelegate.swift:492` | 中 | `buildCombinedPreset()` 在每次录音完成时重新计算，skill 配置在会话内不变，应缓存 |
| P2-1 | `VolcengineLLM.swift:41` | 低 | `temperature: 0.3`，竞品共识是 0.1（文本纠错非创意写作） |
| P2-2 | `AppDelegate.swift:528` | 低 | 日记模式绕过 `AsyncReplacer`，快速连续触发时可能产生两个并发 LLM 调用都写入备忘录 |
| P2-3 | `AppDelegate.swift:506` | 低 | 每次 LLM 完成后都调用 `statusBar.buildMenu()`，menu 内容未变化时重复重建 |
| P2-4 | `PresetManager.swift` | 低 | 合并提示词中各技能重复出现「同时修正识别错误和标点」，冗余 token |

---

## 实施计划

### 阶段一：P0 修复（正确性问题）

#### 任务 1：重写 `buildCombinedPreset()` 合并算法

**文件**：`Sources/VoiceFlowLib/PresetManager.swift`

**当前问题**：按行首前缀（`-`、`规则`、`要求`、`示例`、`输入：`、`输出：` 等）逐行过滤，会丢失：
- `filter` 技能的具体词汇表（`嗯、啊、额、呃`，`就是、那个、其实`）
- `correction` 技能的标志词列表（`不对、不是、我是说...`）
- 所有以 `（` 开头的反例说明行
- 子弹点缩进的续行内容

**新方案**：每个 `Preset` 新增 `ruleBlock: String` 字段，只存"规则正文"（不含通用角色前缀）。合并时把各技能的 `ruleBlock` 直接拼接到统一前缀模板后，不做行级解析。

**具体改动**：

1. `Preset` 结构体新增字段：
   ```swift
   public let ruleBlock: String   // 纯规则内容，用于多技能合并
   ```

2. 每个内置 skill 拆分为：
   - `systemPrompt`：保持现状（单独使用时的完整提示，含角色前缀）
   - `ruleBlock`：只含规则、示例，去掉「你是语音输入助手...你的输出将直接粘贴...」等重复前缀

3. `buildCombinedPreset()` 改为直接拼接 `ruleBlock`：
   ```swift
   let basePrompt = """
   你是语音输入助手。
   场景：用户通过语音输入文字，ASR 将语音转为文本后交给你处理。
   你的输出将直接粘贴到用户的光标位置。永远只输出处理后的文本，不要与用户对话。
   如果无需处理，原样输出。

   你需要同时执行以下处理任务：
   """

   let taskBlocks = enabledPresets.enumerated().map { i, preset in
       "\n\n【任务\(i+1): \(preset.name)】\n\(preset.ruleBlock)"
   }

   let fullPrompt = basePrompt + taskBlocks.joined()
   ```

4. 各技能提示词同步清理：将「同时修正识别错误和标点」从各技能 `ruleBlock` 中删除（移到 `basePrompt` 统一声明一次），避免重复。

#### 任务 2：`max_tokens` 动态计算

**文件**：`Sources/VoiceFlowLib/VolcengineLLM.swift`

**改动**：
```swift
// 旧：
"max_tokens": 256,

// 新：动态计算，至少 300，最多 1024，按输入长度 ×3 估算
let inputLength = text.count
let dynamicMaxTokens = min(1024, max(300, inputLength * 3))
"max_tokens": dynamicMaxTokens,
```

同时在 `Config` 中新增可选字段 `maxTokens: Int?`，允许用户配置覆盖。

---

### 阶段二：P1 修复（可靠性 + 效率）

#### 任务 3：修复超时配置 + 增加重试

**文件**：`Sources/VoiceFlowLib/VolcengineLLM.swift`

**URLSession 超时改动**：
```swift
// 旧：
config.timeoutIntervalForRequest = 10

// 新：
config.timeoutIntervalForRequest = 10      // 保留：包间沉默超时（防止 hang）
config.timeoutIntervalForResource = 30     // 新增：总请求超时 30 秒
```

**重试逻辑**（在 `process()` 内，1 次指数退避）：
```swift
// 可重试的状态码
let retryableCodes: Set<Int> = [429, 500, 502, 503, 504]

// 首次请求失败且状态码可重试时，等待 1 秒后重试一次
if retryableCodes.contains(statusCode) {
    try await Task.sleep(nanoseconds: 1_000_000_000)
    // 重新发送同一请求
    (data, response) = try await session.data(for: request)
}
```

#### 任务 4：词典 + 偏好文件缓存；combined preset 缓存

**文件**：`Sources/VoiceFlowLib/VolcengineLLM.swift`、`Sources/VoiceFlowLib/AppDelegate.swift`

**词典缓存**：将 `loadDictionary()` 和 `loadPersonalPreference()` 调用从 `VolcengineLLM.process()` 内部移出。在 `AppDelegate` 启动时加载并缓存，`applyConfigChange()` 时刷新。`process()` 接受已加载的数据作为参数（或通过 `LLMProvider` 协议更新后传入）。

**combined preset 缓存**：
```swift
// AppDelegate 新增两个缓存属性
private var cachedCombinedPreset: Preset? = nil
private var cachedSkillIds: [String] = []

// 获取合并 preset（命中缓存时不重新计算）
private func getCombinedPreset() -> Preset? {
    let currentSkills = config.effectiveSkills
    if currentSkills != cachedSkillIds || cachedCombinedPreset == nil {
        cachedCombinedPreset = PresetManager.buildCombinedPreset(enabledSkillIds: currentSkills)
        cachedSkillIds = currentSkills
    }
    return cachedCombinedPreset
}

// applyConfigChange() 时清除缓存
cachedCombinedPreset = nil
```

---

### 阶段三：P2 改进（质量 + 体验）

#### 任务 5：temperature 从 0.3 降至 0.1

**文件**：`Sources/VoiceFlowLib/VolcengineLLM.swift:41`

```swift
// 旧：
"temperature": 0.3,

// 新：
"temperature": 0.1,
```

依据：8 个竞品中，纯文本纠错场景的 temperature 范围是 0.0 ~ 0.1，0.3 会增加不必要的改写风险。

#### 任务 6：日记模式复用 AsyncReplacer

**文件**：`Sources/VoiceFlowLib/AppDelegate.swift`

将 `processForJournal()` 中的裸 `Task { provider.process() }` 替换为通过 `AsyncReplacer` 的新 `processAndSave()` 路径（或复用现有 `processAndInsert` 并在 `onComplete` 回调里调用 `NotesIntegration`），使日记模式同样受益于 `currentTask?.cancel()` 的去重保护。

#### 任务 7：`statusBar.buildMenu()` 仅在配置变更时调用

**文件**：`Sources/VoiceFlowLib/AppDelegate.swift`

从 `processForCursor` 的 `onComplete` 回调中删除 `self.statusBar.buildMenu()` 调用。只在 `applyConfigChange()` 和 `launchAtLogin` 状态变更时调用。

---

## 不在本 SPEC 范围内

- 上下文感知（当前窗口 / 截图注入）— 用户明确排除
- streaming LLM 输出 — 需要重构 TextInserter 的光标追踪逻辑，范围较大，单独评估
- `<TRANSCRIPT>` 标签 prompt injection 防护 — 低优先级，单独处理

---

## 验证方式

每个阶段完成后：

1. `swift build` 编译通过，无新增 warning
2. 启动 app（`./dev.sh`），分别测试：
   - 单 skill 模式（只开语法纠错）
   - 多 skill 模式（默认 4 个）：验证 filter 技能仍能去除「嗯啊那个」等词
   - 长段落测试（>100 字）：验证 structure 技能不被截断
   - 快速连续录音：验证取消逻辑正常工作
   - 日记模式快速双击：验证不产生重复条目
3. `.build/debug/VoiceFlow status` 打印配置摘要正常
