# CLAUDE.md

本文件为 Claude Code (claude.ai/code) 在此仓库工作时提供上下文指引。

## 项目概述

VoiceFlow 是一个 macOS 菜单栏常驻的按键说话（Push-to-Talk）语音输入工具。通过 WebSocket 将音频实时流式传输至 Soniox 云端语音识别（ASR），可选用火山引擎/豆包大模型（LLM）对转录文本进行润色，最终将文本插入光标位置，或追加到 Apple 备忘录的每日日记中。

本项目 fork 自 open-wispr 但已完全分化：Whisper 替换为 Soniox，新增 LLM 后处理管线和日记模式。README 仍描述上游项目，内容已过时。

## 构建与开发命令

```bash
swift build                    # 调试构建
swift build -c release         # 发布构建
swift test                     # 运行测试（当前不可用，见"已知问题"）
./dev.sh                       # 编译 + 杀掉旧进程 + 重新启动调试版本
.build/debug/VoiceFlow status  # 打印配置摘要
```

无 CI/CD 管线，无 Makefile——纯 Swift Package Manager（swift-tools-version 6.0，语言模式 v5）。

**构建目标**（定义在 `Package.swift`）：
- `VoiceFlowLib` — 核心逻辑库（Sources/VoiceFlowLib）
- `VoiceFlow` — 可执行入口（Sources/VoiceFlow）
- `VoiceFlowTests` — XCTest 测试（Tests/VoiceFlowTests）

## 架构

### 入口与命令行分发

`Sources/VoiceFlow/main.swift` — 以 `NSApplication.shared` + `.accessory` 激活策略运行（仅菜单栏，无 Dock 图标）。子命令：`start`（默认）、`status`、`--help`。

### 核心数据流（录音会话）

```
HotkeyManager（全局 NSEvent 监听）
  │ keyDown
  ▼
AppDelegate.handleRecordingStart()
  ├─ AudioRecorder.startStreaming()        ← AVAudioEngine tap, float32→int16, 16kHz 单声道
  │    └─ startupBuffer（WebSocket 连接前暂存音频）
  └─ SonioxEngine.connect()               ← wss://stt-rt.soniox.com, 模型 stt-rt-v4
       └─ 连接成功后刷入 startupBuffer

AudioRecorder tap → streamingCallback → SonioxEngine.sendAudio()  [实时流式]

  │ keyUp（+300ms 尾部延迟）
  ▼
SonioxEngine.finishInput()
  └─ onComplete(fullText)
       ├─ RecordingStore.save()            ← WAV 存至 ~/.config/voiceflow/recordings/
       └─ 按模式路由：
            ├─ 普通模式 → AsyncReplacer.processAndInsert()
            │    ├─ VolcengineLLM.process()   ← POST /chat/completions
            │    └─ TextInserter.insert()      ← CGEvent 模拟 Cmd+V 粘贴
            └─ 日记模式 → NotesIntegration.appendToDaily()
                 └─ AppleScript → macOS 备忘录 "VoiceFlow" 文件夹
```

### 关键设计决策

- **WebSocket 前音频缓冲**：keyDown 立即开始录音，音频暂存内存；WebSocket 连接后刷入缓冲区，防止丢失第一个音节
- **300ms 尾部延迟**：keyUp 后等待 300ms 再发送 finishInput()，避免截断最后一个字
- **LLM 可选**：未配置 LLM 密钥时，直接插入原始 ASR 文本
- **技能合并提示词**：多个 LLM 技能通过 `PresetManager.buildCombinedPreset()` 合并为单次 API 调用

### 扩展点（协议）

- `ASREngine`（ASREngine.swift）— 语音识别后端协议；唯一实现：`SonioxEngine`
- `LLMProvider`（LLMProvider.swift）— LLM 后处理协议；唯一实现：`VolcengineLLM`

### 界面层

AppKit + SwiftUI 混合架构：
- `StatusBarController` — NSStatusItem 菜单栏，带动画状态图标（波形/跳动圆点/锁）
- `FloatingPill` — NSPanel + NSVisualEffectView（毛玻璃），显示实时转录/进度/错误
- `WaveformView` — SwiftUI Canvas 多层正弦波动画，由实际音频电平驱动
- `GlowBorderView` — SwiftUI 跑马灯边框动画

## 配置

运行时配置文件：`~/.config/voiceflow/config.json`（首次运行自动创建）

关键字段：`sonioxApiKey`（必填）、`llmApiKey`（可选）、`llmBaseURL`、`llmModel`（默认 `doubao-1.5-pro-32k`）、`hotkey`（默认 Globe/Fn 键）、`toggleMode`（默认 false = 按住说话）、`enabledSkills`（默认 `["grammar", "filter"]`）、`journalHotkey`。

可用 LLM 技能：`grammar`、`filter`、`structure`、`formal`、`simplify`。

附加用户文件：
- `~/.config/voiceflow/dictionary.txt` — 专有名词词典，注入 LLM 提示词以纠正 ASR 识别错误
- `~/.config/voiceflow/preference.txt` — 自由文本个人偏好，追加到 LLM 提示词
- `~/.config/voiceflow/recordings/` — 录音 WAV 文件，超过 7 天自动清理

`FlexBool` 是自定义 Codable 类型，接受 Bool、String（"true"/"yes"/"1"）或 Int，提供配置灵活性。

## 已知问题

**测试不可编译**：三个测试文件均使用 `@testable import OpenWisprLib`（旧模块名）。此外 `ConfigTests.swift` 引用了 fork 迁移中已删除的属性和方法（`modelSize`、`language`、`maxRecordings`、`supportedLanguages`、`supportedModels`、`Config.decode(from:)`、`Config.effectiveMaxRecordings()`）。测试需要按照当前 `VoiceFlowLib` API 重写才能通过编译。

## 约定

- 仅支持 macOS 13+，Apple Silicon 为主要目标平台
- 系统框架直接链接：CoreAudio、AVFoundation、AppKit
- 文本插入使用无障碍 API（CGEvent 模拟 Cmd+V）— 需要辅助功能权限
- 开机自启通过 LaunchAgents plist 管理：`~/Library/LaunchAgents/com.voiceflow.app.plist`
- 版本号维护在 `Sources/VoiceFlowLib/Version.swift`，运行时通过 `~/.config/voiceflow/.last-version` 检测升级
