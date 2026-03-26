class Voiceflow < Formula
  desc "macOS 菜单栏按键说话语音输入工具"
  homepage "https://github.com/chancheuklap/voiceflow"
  url "https://github.com/chancheuklap/voiceflow.git", tag: "v0.3.0"
  license "MIT"

  depends_on xcode: ["14.0", :build]
  depends_on macos: :ventura

  def install
    system "swift", "build", "-c", "release", "--disable-sandbox"

    # 构建 .app 包
    app_dir = prefix/"VoiceFlow.app/Contents"
    (app_dir/"MacOS").install ".build/release/VoiceFlow"
    (app_dir/"Resources").install "assets/VoiceFlow.icns" => "AppIcon.icns"
    (app_dir/"Resources").install "assets/icon.png"

    # Info.plist
    (app_dir/"Info.plist").write <<~PLIST
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0">
      <dict>
        <key>CFBundleName</key>
        <string>VoiceFlow</string>
        <key>CFBundleDisplayName</key>
        <string>VoiceFlow</string>
        <key>CFBundleIdentifier</key>
        <string>com.voiceflow.app</string>
        <key>CFBundleVersion</key>
        <string>#{version}</string>
        <key>CFBundleShortVersionString</key>
        <string>#{version}</string>
        <key>CFBundleExecutable</key>
        <string>VoiceFlow</string>
        <key>CFBundleIconFile</key>
        <string>AppIcon</string>
        <key>CFBundlePackageType</key>
        <string>APPL</string>
        <key>LSMinimumSystemVersion</key>
        <string>13.0</string>
        <key>LSUIElement</key>
        <true/>
        <key>NSMicrophoneUsageDescription</key>
        <string>VoiceFlow 需要麦克风权限来进行语音输入</string>
      </dict>
      </plist>
    PLIST

    # 命令行入口
    bin.install_symlink app_dir/"MacOS/VoiceFlow"

    # LaunchAgent 模板
    (share/"voiceflow").install_symlink \
      app_dir/"MacOS/VoiceFlow" => "VoiceFlow"
  end

  def post_install
    # 复制 .app 到 /Applications
    app_src = prefix/"VoiceFlow.app"
    app_dst = Pathname("/Applications/VoiceFlow.app")
    rm_rf app_dst if app_dst.exist?
    cp_r app_src, app_dst

    # 安装 LaunchAgent（开机自启 + 崩溃重启）
    plist_dir = Pathname(Dir.home)/"Library/LaunchAgents"
    plist_dir.mkpath
    plist_path = plist_dir/"com.voiceflow.app.plist"
    plist_path.write <<~PLIST
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0">
      <dict>
        <key>Label</key>
        <string>com.voiceflow.app</string>
        <key>ProgramArguments</key>
        <array>
          <string>/Applications/VoiceFlow.app/Contents/MacOS/VoiceFlow</string>
        </array>
        <key>RunAtLoad</key>
        <true/>
        <key>KeepAlive</key>
        <dict>
          <key>SuccessfulExit</key>
          <false/>
        </dict>
        <key>StandardOutPath</key>
        <string>/tmp/voiceflow.log</string>
        <key>StandardErrorPath</key>
        <string>/tmp/voiceflow.err</string>
      </dict>
      </plist>
    PLIST
  end

  def caveats
    <<~EOS
      ✅ VoiceFlow 已安装到启动台，开机自动启动。

      ⚠️  首次使用需要 2 步设置：

      1. 配置 API 密钥（编辑配置文件）：
         nano ~/.config/voiceflow/config.json
         填入 sonioxApiKey（必填）和 llmApiKey（可选，用于文本润色）

      2. 授权系统权限（首次运行时会自动弹窗）：
         · 辅助功能：系统设置 → 隐私与安全性 → 辅助功能 → 开启 VoiceFlow
         · 麦克风：系统设置 → 隐私与安全性 → 麦克风 → 开启 VoiceFlow

      启动：在启动台点击 VoiceFlow 图标，或运行 launchctl kickstart gui/$(id -u)/com.voiceflow.app
    EOS
  end

  test do
    assert_match "VoiceFlow", shell_output("#{bin}/VoiceFlow --help 2>&1", 0)
  end
end
