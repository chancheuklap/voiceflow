cask "voiceflow" do
  version "0.3.1"
  sha256 "be99da579d258cc8bd4523e26258c85f2442ac8a435c6ad4e96d91ce94726d04"

  url "https://github.com/chancheuklap/voiceflow/releases/download/v#{version}/VoiceFlow.app.zip"
  name "VoiceFlow"
  desc "macOS 菜单栏按键说话语音输入工具"
  homepage "https://github.com/chancheuklap/voiceflow"

  app "VoiceFlow.app"

  postflight do
    # 移除 Gatekeeper 隔离标记（未签名应用）
    system_command "/usr/bin/xattr", args: ["-cr", "/Applications/VoiceFlow.app"]

    # 安装 LaunchAgent（开机自启 + 崩溃重启）
    plist_path = "#{Dir.home}/Library/LaunchAgents/com.voiceflow.app.plist"
    File.write(plist_path, <<~PLIST)
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

  uninstall launchctl: "com.voiceflow.app"

  caveats <<~EOS
    ⚠️  首次使用需要设置：

    1. 启动 VoiceFlow（在启动台点击图标）
    2. 编辑配置文件，填入 API 密钥：
       nano ~/.config/voiceflow/config.json
    3. 授权辅助功能和麦克风权限（系统自动弹窗）
  EOS
end
