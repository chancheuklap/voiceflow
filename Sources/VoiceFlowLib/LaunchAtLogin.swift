import Foundation

/// 开机自启管理 — 通过 LaunchAgent plist 实现
struct LaunchAtLogin {
    private static let label = "com.voiceflow.app"

    private static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    /// 当前是否已设置开机自启
    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    /// 获取当前运行的二进制路径
    private static var executablePath: String {
        // 解析为绝对路径（swift run 可能传相对路径）
        let arg0 = ProcessInfo.processInfo.arguments[0]
        if arg0.hasPrefix("/") {
            return arg0
        }
        let cwd = FileManager.default.currentDirectoryPath
        return (cwd as NSString).appendingPathComponent(arg0)
    }

    /// 启用开机自启
    static func enable() {
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executablePath],
            "RunAtLoad": true,
            "KeepAlive": false,
        ]

        let dir = plistURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let data = try? PropertyListSerialization.data(
            fromPropertyList: plist, format: .xml, options: 0
        )
        try? data?.write(to: plistURL)

        // 注册到 launchctl
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["load", plistURL.path]
        try? process.run()
        process.waitUntilExit()

        print("Launch at login: enabled (\(executablePath))")
    }

    /// 禁用开机自启
    static func disable() {
        // 从 launchctl 注销
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["unload", plistURL.path]
        try? process.run()
        process.waitUntilExit()

        try? FileManager.default.removeItem(at: plistURL)
        print("Launch at login: disabled")
    }

    /// 切换开机自启状态
    static func toggle() {
        if isEnabled {
            disable()
        } else {
            enable()
        }
    }
}
