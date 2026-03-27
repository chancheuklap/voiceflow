import Foundation
import AppKit

struct UpdateInfo: Sendable {
    let version: String
    let downloadURL: URL
    let releasePageURL: URL
}

/// 负责检查 GitHub Releases 新版本、下载并原位替换安装
/// 原位替换（rsync --delete 覆盖同路径）可保留 macOS 辅助功能权限，无需重新授权
final class UpdateChecker {
    static let shared = UpdateChecker()
    private init() {}

    private let githubRepo = "chancheuklap/voiceflow"

    // 回调均在主线程调用
    var onUpdateAvailable: ((UpdateInfo) -> Void)?
    var onAlreadyUpToDate: (() -> Void)?
    var onCheckError: ((String) -> Void)?
    var onDownloadStarted: (() -> Void)?
    var onInstallError: ((String) -> Void)?

    private(set) var pendingUpdate: UpdateInfo?

    // MARK: - 检查更新

    /// silent=true：仅在发现新版本时回调，安静失败；silent=false：结果全部回调
    func checkForUpdates(silent: Bool) {
        Task {
            await performCheck(silent: silent)
        }
    }

    private func performCheck(silent: Bool) async {
        guard let apiURL = URL(string: "https://api.github.com/repos/\(githubRepo)/releases/latest") else { return }

        var request = URLRequest(url: apiURL, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("VoiceFlow/\(VoiceFlow.version)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String,
                  let htmlURL = json["html_url"] as? String,
                  let releasePageURL = URL(string: htmlURL),
                  let assets = json["assets"] as? [[String: Any]] else {
                if !silent { DispatchQueue.main.async { self.onCheckError?("无法解析版本信息") } }
                return
            }

            let latestVersion = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName

            guard isNewer(latestVersion, than: VoiceFlow.version) else {
                if !silent { DispatchQueue.main.async { self.onAlreadyUpToDate?() } }
                return
            }

            guard let asset = assets.first(where: { ($0["name"] as? String)?.hasSuffix(".zip") == true }),
                  let urlStr = asset["browser_download_url"] as? String,
                  let downloadURL = URL(string: urlStr) else {
                if !silent { DispatchQueue.main.async { self.onCheckError?("找不到下载资源") } }
                return
            }

            let info = UpdateInfo(version: latestVersion, downloadURL: downloadURL, releasePageURL: releasePageURL)
            DispatchQueue.main.async {
                self.pendingUpdate = info
                self.onUpdateAvailable?(info)
            }

        } catch {
            if !silent { DispatchQueue.main.async { self.onCheckError?("网络错误：\(error.localizedDescription)") } }
        }
    }

    // MARK: - 下载并安装

    func downloadAndInstall(_ info: UpdateInfo) {
        DispatchQueue.main.async { self.onDownloadStarted?() }
        Task {
            await performInstall(info)
        }
    }

    private func performInstall(_ info: UpdateInfo) async {
        let timestamp = Int(Date().timeIntervalSince1970)
        let tempDir = URL(fileURLWithPath: "/tmp/voiceflow-update-\(timestamp)")

        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

            // 下载 zip
            let (tmpURL, _) = try await URLSession.shared.download(from: info.downloadURL)
            let zipPath = tempDir.appendingPathComponent("VoiceFlow.app.zip")
            try? FileManager.default.removeItem(at: zipPath)
            try FileManager.default.moveItem(at: tmpURL, to: zipPath)

            // 解压（异步，不阻塞线程）
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                do {
                    let unzip = Process()
                    unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
                    unzip.arguments = ["-q", "-o", zipPath.path, "-d", tempDir.path]
                    unzip.terminationHandler = { proc in
                        if proc.terminationStatus == 0 {
                            continuation.resume()
                        } else {
                            continuation.resume(throwing: UpdateError.unzipFailed)
                        }
                    }
                    try unzip.run()
                } catch {
                    continuation.resume(throwing: error)
                }
            }

            // 找到 .app 包
            let contents = try FileManager.default.contentsOfDirectory(atPath: tempDir.path)
            guard let appName = contents.first(where: { $0.hasSuffix(".app") }) else {
                throw UpdateError.appNotFound
            }

            let newApp = tempDir.appendingPathComponent(appName).path
            let currentApp = Bundle.main.bundlePath

            // 写安装脚本：rsync 原位替换保证路径不变，辅助功能权限保留
            let scriptPath = "/tmp/vf_install_\(timestamp).sh"
            let script = """
            #!/bin/bash
            sleep 2
            /usr/bin/xattr -cr "\(newApp)"
            /usr/bin/rsync -a --delete "\(newApp)/" "\(currentApp)/"
            /usr/bin/open "\(currentApp)"
            /bin/rm -rf "\(tempDir.path)"
            /bin/rm -f "$0"
            """
            try script.write(toFile: scriptPath, atomically: true, encoding: .utf8)
            var attrs = try FileManager.default.attributesOfItem(atPath: scriptPath)
            attrs[.posixPermissions] = NSNumber(value: 0o755)
            try FileManager.default.setAttributes(attrs, ofItemAtPath: scriptPath)

            // 启动安装脚本后退出
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/bin/bash")
            proc.arguments = [scriptPath]
            try proc.run()

            DispatchQueue.main.async {
                NSApplication.shared.terminate(nil)
            }

        } catch {
            try? FileManager.default.removeItem(at: tempDir)
            let msg = (error as? UpdateError)?.localizedDescription ?? "安装失败：\(error.localizedDescription)"
            DispatchQueue.main.async { self.onInstallError?(msg) }
        }
    }

    // MARK: - 版本比较（semver）

    private func isNewer(_ candidate: String, than current: String) -> Bool {
        let c = candidate.split(separator: ".").compactMap { Int($0) }
        let r = current.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(c.count, r.count) {
            let cv = i < c.count ? c[i] : 0
            let rv = i < r.count ? r[i] : 0
            if cv != rv { return cv > rv }
        }
        return false
    }
}

private enum UpdateError: LocalizedError {
    case unzipFailed
    case appNotFound

    var errorDescription: String? {
        switch self {
        case .unzipFailed: return "解压失败"
        case .appNotFound: return "压缩包中未找到 .app 文件"
        }
    }
}
