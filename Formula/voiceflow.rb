class Voiceflow < Formula
  desc "macOS 菜单栏按键说话语音输入工具"
  homepage "https://github.com/chancheuklap/voiceflow"
  url "https://github.com/chancheuklap/voiceflow.git", tag: "v0.3.0"
  license "MIT"

  depends_on xcode: ["14.0", :build]
  depends_on macos: :ventura

  def install
    system "swift", "build", "-c", "release", "--disable-sandbox"
    bin.install ".build/release/VoiceFlow"
  end

  def caveats
    <<~EOS
      VoiceFlow 需要辅助功能和麦克风权限。
      首次运行时系统会弹窗请求授权。

      启动: VoiceFlow
      开机自启: 在菜单栏图标中开启 "Launch at Login"
    EOS
  end

  test do
    assert_match "VoiceFlow", shell_output("#{bin}/VoiceFlow --help 2>&1", 0)
  end
end
