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

    # 同时保留命令行入口
    bin.install_symlink app_dir/"MacOS/VoiceFlow"
  end

  def post_install
    # 链接 .app 到 /Applications
    app_src = prefix/"VoiceFlow.app"
    app_dst = Pathname("/Applications/VoiceFlow.app")
    app_dst.unlink if app_dst.symlink?
    app_dst.make_symlink(app_src) unless app_dst.exist?
  end

  def caveats
    <<~EOS
      VoiceFlow 已安装到启动台（/Applications/VoiceFlow.app）。

      首次使用需授权：
        系统设置 → 隐私与安全性 → 辅助功能 → 添加 VoiceFlow

      开机自启（LaunchAgent）：
        在菜单栏 VoiceFlow 图标中开启 "Launch at Login"
    EOS
  end

  test do
    assert_match "VoiceFlow", shell_output("#{bin}/VoiceFlow --help 2>&1", 0)
  end
end
