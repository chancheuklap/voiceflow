# VoiceFlow

macOS 菜单栏按键说话语音输入工具。按住快捷键说话，松开后文字出现在光标处。

使用 Soniox 云端实时语音识别（ASR），可选火山引擎/豆包大模型对转录结果进行润色（语法纠正、口语过滤等）。支持日记模式——录音内容自动追加到 Apple 备忘录的每日日记中。

> 本项目 fork 自 [open-wispr](https://github.com/human37/open-wispr)，已完全分化：Whisper 替换为 Soniox 云端 ASR，新增 LLM 后处理管线和日记模式。

## 安装

### 前置条件

- macOS 13+（Apple Silicon）
- [Soniox API 密钥](https://soniox.com)（必需）
- 火山引擎/豆包 API 密钥（可选，用于 LLM 润色）

### 从源码构建

```bash
git clone <repo-url>
cd voiceflow
swift build -c release
.build/release/VoiceFlow start
```

### 权限要求

- **麦克风权限** — 录音需要
- **辅助功能权限** — 文本插入需要（CGEvent 模拟 Cmd+V）

如果 Globe 键会打开表情选择器：**系统设置 → 键盘 → "按下🌐键时" → "不执行任何操作"**

## 使用方式

默认按住 **Globe 键**（🌐，键盘左下角）说话，松开后文字插入光标位置。

```bash
voiceflow              # 启动（默认）
voiceflow status       # 查看当前配置
voiceflow --help       # 帮助信息
```

开发模式：

```bash
./dev.sh               # 编译 + 重启调试版本
```

## 配置

编辑 `~/.config/voiceflow/config.json`：

```json
{
  "hotkey": { "keyCode": 63, "modifiers": [] },
  "sonioxApiKey": "your-soniox-key",
  "llmApiKey": "your-volcengine-key",
  "llmModel": "doubao-1.5-pro-32k",
  "enabledSkills": ["grammar", "filter"],
  "toggleMode": false
}
```

| 选项 | 默认值 | 说明 |
|------|--------|------|
| **hotkey** | Globe 键 (`63`) | 任意按键码，可配合 `modifiers`（`"cmd"`/`"ctrl"`/`"shift"`/`"opt"`） |
| **sonioxApiKey** | 无 | Soniox API 密钥（必填） |
| **llmApiKey** | 无 | 火山引擎 API 密钥（可选，不填则跳过 LLM 润色） |
| **llmModel** | `doubao-1.5-pro-32k` | LLM 模型名称 |
| **enabledSkills** | `["grammar", "filter"]` | 启用的 LLM 技能组合 |
| **toggleMode** | `false` | `true` = 点按切换录音；`false` = 按住说话 |
| **journalHotkey** | 无 | 日记模式快捷键，录音内容保存到备忘录而非插入光标 |

### LLM 技能

多个技能可同时启用，提示词会自动合并为单次 API 调用。

| 技能 ID | 功能 |
|---------|------|
| `grammar` | 语法纠正 |
| `filter` | 口语填充词过滤 |
| `structure` | 自动分段结构化 |
| `formal` | 正式化表达 |
| `simplify` | 简化表达 |

### 附加文件

- `~/.config/voiceflow/dictionary.txt` — 专有名词词典（每行一个），注入 LLM 提示词纠正 ASR 错误
- `~/.config/voiceflow/preference.txt` — 个人偏好（自由文本），追加到 LLM 提示词
- `~/.config/voiceflow/recordings/` — 录音 WAV 文件，超过 7 天自动清理

## 菜单栏状态

| 状态 | 图标 |
|------|------|
| 待机 | 波形轮廓 |
| 录音中 | 跳动波形 |
| 转录中 | 跳动圆点 |
| 等待权限 | 锁 |

## 开机自启

通过菜单栏选项启用，管理方式为 LaunchAgents plist（`~/Library/LaunchAgents/com.voiceflow.app.plist`）。

## 许可证

MIT
