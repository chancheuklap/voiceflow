# VoiceFlow

macOS 菜单栏语音输入工具。按住快捷键说话，松开后文字自动出现在光标处。

支持实时语音识别 + AI 文本润色，让你的语音输入像打字一样自然。

<p align="center">
  <img src="assets/icon.png" width="128" alt="VoiceFlow Icon">
</p>

## 功能特性

- **按键说话** — 按住快捷键说话，松开即输入，无需切换窗口
- **实时识别** — Soniox 云端 ASR，边说边显示识别结果
- **AI 润色** — 可选接入大模型，自动纠正语法、过滤口语词、结构化文本
- **日记模式** — 独立快捷键，录音内容自动保存到 Apple 备忘录每日日记
- **专有名词词典** — 自定义词典纠正 ASR 对人名、术语的识别错误
- **水晶毛玻璃弹窗** — 深色半透明玻璃效果，呼吸灯边框，弹簧动画过渡
- **菜单栏常驻** — 不占 Dock，不干扰其他应用

## 安装

### 方式一：Homebrew（推荐）

```bash
brew tap chancheuklap/voiceflow
brew install --cask voiceflow
```

安装后在启动台即可看到 VoiceFlow 图标。

### 方式二：手动下载

1. 前往 [Releases](https://github.com/chancheuklap/voiceflow/releases) 下载 `VoiceFlow.app.zip`
2. 解压后将 `VoiceFlow.app` 拖入 `/Applications`
3. 终端运行 `xattr -cr /Applications/VoiceFlow.app`（移除 macOS 隔离标记）
4. 在启动台点击 VoiceFlow 启动

### 系统要求

- macOS 13 Ventura 或更高版本
- Apple Silicon（M1/M2/M3/M4）

## 首次设置

### 第一步：获取 API 密钥

- [Soniox](https://soniox.com) — 注册获取语音识别 API 密钥（**必需**）
- [火山引擎](https://www.volcengine.com/product/doubao) — 获取豆包大模型 API 密钥（可选，用于文本润色）

### 第二步：启动并配置

1. 在启动台点击 VoiceFlow 启动应用
2. 首次启动会自动创建配置文件，编辑它：

```bash
nano ~/.config/voiceflow/config.json
```

3. 填入你的 API 密钥：

```json
{
  "sonioxApiKey": "你的 Soniox 密钥",
  "llmApiKey": "你的火山引擎密钥（可选）",
  "llmModel": "doubao-seed-2-0-lite-260215",
  "enabledSkills": ["grammar", "filter"]
}
```

### 第三步：授权系统权限

首次启动时系统会弹窗请求授权，两项都需要允许：

| 权限 | 用途 | 设置路径 |
|------|------|----------|
| **辅助功能** | 将文字插入光标位置 | 系统设置 → 隐私与安全性 → 辅助功能 |
| **麦克风** | 录音 | 系统设置 → 隐私与安全性 → 麦克风 |

## 使用方法

### 语音输入

1. 将光标放在任意文本输入框中
2. **按住 Globe 键**（🌐，键盘左下角）开始说话
3. **松开**，识别结果自动插入光标处

> 如果 Globe 键会打开表情选择器：**系统设置 → 键盘 → "按下🌐键时" → "不执行任何操作"**

### 弹窗状态

| 状态 | 边框效果 | 说明 |
|------|----------|------|
| 录音中 | 绿色呼吸灯 | 正在聆听你的声音 |
| 识别中 | 金色呼吸灯 | 语音转文字处理中 |
| 润色中 | 金色呼吸灯 | AI 正在优化文本 |
| 完成 | 绿色静态边框 | 文字已插入 |
| 错误 | 红色静态边框 | 出现问题 |

### 菜单栏操作

点击菜单栏的 VoiceFlow 图标可以：

- 查看当前状态和快捷键
- 切换 LLM 技能（语法纠正、口语过滤等）
- 开启/关闭 Toggle 模式（点按切换 vs 按住说话）
- 复制上一次的识别结果
- 重试上一次录音
- 编辑词典
- 重载/打开配置文件

## 配置详解

配置文件位于 `~/.config/voiceflow/config.json`，修改后在菜单栏选择 "Reload Configuration" 即可生效。

### 基础配置

| 选项 | 默认值 | 说明 |
|------|--------|------|
| `sonioxApiKey` | 无 | Soniox API 密钥（**必填**） |
| `llmApiKey` | 无 | 火山引擎 API 密钥（不填则跳过润色） |
| `llmModel` | `doubao-seed-2-0-lite-260215` | LLM 模型名称 |
| `hotkey` | Globe 键 | 录音快捷键 |
| `toggleMode` | `false` | `true` = 点按切换录音，`false` = 按住说话 |
| `journalHotkey` | 无 | 日记模式快捷键 |
| `enabledSkills` | `["grammar", "filter"]` | 启用的 LLM 技能 |

### 快捷键配置示例

```json
// Globe 键（默认）
"hotkey": { "keyCode": 63, "modifiers": [] }

// Right Option 键
"hotkey": { "keyCode": 61, "modifiers": [] }

// Ctrl + Shift + S
"hotkey": { "keyCode": 1, "modifiers": ["ctrl", "shift"] }
```

### LLM 技能

多个技能可同时启用，会自动合并为单次 API 调用：

| 技能 | 功能 | 适用场景 |
|------|------|----------|
| `grammar` | 语法纠正 | 日常输入 |
| `filter` | 口语填充词过滤 | 去除"嗯""那个"等口语词 |
| `structure` | 自动分段 | 长文本输入 |
| `formal` | 正式化表达 | 邮件、公文 |
| `simplify` | 简化表达 | 精简冗长表述 |

### 附加文件

| 文件 | 用途 |
|------|------|
| `~/.config/voiceflow/dictionary.txt` | 专有名词词典（每行一个），帮助 ASR 正确识别人名、术语 |
| `~/.config/voiceflow/preference.txt` | 个人偏好描述（自由文本），影响 AI 润色风格 |
| `~/.config/voiceflow/recordings/` | 录音文件，超过 7 天自动清理 |

## 开机自启

通过 Homebrew 安装时自动配置 LaunchAgent，开机后自动启动，崩溃后自动重启。

手动管理：

```bash
# 启动
launchctl kickstart gui/$(id -u)/com.voiceflow.app

# 重启
launchctl kickstart -k gui/$(id -u)/com.voiceflow.app

# 停止（从菜单栏 Quit 即可）
```

## 开发

```bash
git clone https://github.com/chancheuklap/voiceflow.git
cd voiceflow
./dev.sh              # 编译 + 重启调试版本
swift build            # 仅编译
VoiceFlow status       # 查看配置摘要
```

## 许可证

MIT
