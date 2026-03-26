# VoiceFlow

macOS 菜单栏语音输入工具。按一下快捷键开始说话，再按一下结束，文字自动出现在光标处。

支持实时语音识别 + AI 润色，语音输入像打字一样自然。

<p align="center">
  <img src="assets/icon.png" width="128" alt="VoiceFlow">
</p>

## 安装

```bash
brew tap chancheuklap/voiceflow
brew install --cask voiceflow
```

安装完成后在启动台可以看到 VoiceFlow 图标。

> 没有 Homebrew？先安装：`/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"`
>
> 也可以在 [Releases](https://github.com/chancheuklap/voiceflow/releases) 手动下载 .app，解压拖入 `/Applications` 后运行 `xattr -cr /Applications/VoiceFlow.app`。

## 设置（只需做一次）

### 1. 获取 API 密钥

你需要注册两个服务来获取密钥：

| 服务 | 用途 | 注册地址 |
|------|------|----------|
| **Soniox**（必需） | 语音识别 | [soniox.com](https://soniox.com) |
| **火山引擎**（推荐） | AI 文本润色 | [volcengine.com/product/doubao](https://www.volcengine.com/product/doubao) |

> 不配置火山引擎也能用，但语音转出的文字不会经过 AI 润色。

### 2. 填入密钥

启动 VoiceFlow 后，打开终端输入：

```bash
nano ~/.config/voiceflow/config.json
```

找到这两行，把 `null` 替换成你的密钥（保留引号）：

```json
"sonioxApiKey": "粘贴你的 Soniox 密钥",
"llmApiKey": "粘贴你的火山引擎密钥",
```

保存（`Ctrl+O` → 回车 → `Ctrl+X`），然后在菜单栏点击 VoiceFlow 图标 → **Reload Configuration**。

### 3. 授权权限

首次使用时系统会弹窗，两项都要允许：

- **辅助功能** — 系统设置 → 隐私与安全性 → 辅助功能 → 开启 VoiceFlow
- **麦克风** — 系统设置 → 隐私与安全性 → 麦克风 → 开启 VoiceFlow

设置完毕，可以开始用了。

## 使用方法

### 语音输入

1. 把光标放在任意输入框（微信、备忘录、浏览器等都行）
2. 按一下 **右 Option 键**（⌥，键盘右下角）开始说话
3. 说完后再按一下 **右 Option 键**，文字自动插入

### 日记模式

按一下 **右 Command 键**（⌘）开始说话，再按一下结束。录音内容会自动保存到 Apple 备忘录的 "VoiceFlow" 文件夹中，按日期归档。

### 弹窗含义

| 边框颜色 | 含义 |
|----------|------|
| 绿色呼吸 | 正在录音 |
| 金色呼吸 | 识别中 / AI 润色中 |
| 绿色常亮 | 完成，文字已插入 |
| 红色常亮 | 出错了 |

### 菜单栏

点击菜单栏的 VoiceFlow 波形图标，可以：

- 切换 AI 技能（语法纠正 / 口语过滤 / 自动分段）
- 复制上一次识别的文字
- 重新识别上一次录音
- 编辑词典 / 重载配置

## 用户词典

如果 VoiceFlow 经常把某些人名、产品名、术语识别错，可以添加到词典里：

```bash
nano ~/.config/voiceflow/dictionary.txt
```

每行写一个词，例如：

```
张伟
VoiceFlow
Soniox
豆包
```

保存后立即生效，不需要重启。

## 系统要求

- macOS 13 Ventura 或更高版本
- Apple Silicon（M1 / M2 / M3 / M4）

## 许可证

MIT
