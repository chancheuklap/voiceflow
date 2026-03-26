import AppKit

class MenuItemTarget: NSObject {
    let handler: () -> Void
    init(handler: @escaping () -> Void) { self.handler = handler }
    @objc func invoke() { handler() }
}

class StatusBarController: NSObject {
    private var statusItem: NSStatusItem
    private var animationTimer: Timer?
    private var animationFrame = 0
    private var animationFrames: [NSImage] = []
    private var menuItemTargets: [MenuItemTarget] = []

    var onConfigChange: ((Config) -> Void)?

    enum State {
        case idle
        case recording
        case transcribing
        case waitingForPermission
        case error(String)
    }

    var state: State = .idle {
        didSet { updateIcon() }
    }

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.image = StatusBarController.drawLogo(active: false)
            button.image?.isTemplate = true
        }

        buildMenu()
    }

    @objc private func copyLastTranscription() {
        guard let delegate = NSApplication.shared.delegate as? AppDelegate,
              let text = delegate.lastTranscription else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    func buildMenu() {
        menuItemTargets = []

        let config = Config.load()
        let hotkeyDesc = KeyCodes.describe(keyCode: config.hotkey.keyCode, modifiers: config.hotkey.modifiers)
        let enabledSkills = config.effectiveSkills

        let menu = NSMenu()

        let titleItem = NSMenuItem(title: "VoiceFlow v\(VoiceFlow.version)", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)

        menu.addItem(NSMenuItem.separator())

        let stateLabel: String
        switch state {
        case .idle: stateLabel = "Ready"
        case .recording: stateLabel = "Recording..."
        case .transcribing: stateLabel = "Processing..."
        case .waitingForPermission: stateLabel = "Waiting for Accessibility permission..."
        case .error(let message): stateLabel = "Error: \(message)"
        }

        if case .waitingForPermission = state {
            let target = MenuItemTarget {
                Permissions.openAccessibilitySettings()
            }
            menuItemTargets.append(target)
            let stateItem = NSMenuItem(title: "Grant Accessibility Permission...", action: #selector(MenuItemTarget.invoke), keyEquivalent: "")
            stateItem.target = target
            menu.addItem(stateItem)
        } else {
            let stateItem = NSMenuItem(title: "\(stateLabel) (hotkey: \(hotkeyDesc))", action: nil, keyEquivalent: "")
            stateItem.isEnabled = false
            menu.addItem(stateItem)
        }

        // ── Skills 区域 ──

        menu.addItem(NSMenuItem.separator())

        let skillsHeader = NSMenuItem(title: "文本处理", action: nil, keyEquivalent: "")
        skillsHeader.isEnabled = false
        menu.addItem(skillsHeader)

        for preset in PresetManager.presets {
            let isEnabled = enabledSkills.contains(preset.id)
            let skillTarget = MenuItemTarget { [weak self] in
                var cfg = Config.load()
                var skills = cfg.effectiveSkills
                if let index = skills.firstIndex(of: preset.id) {
                    skills.remove(at: index)
                } else {
                    skills.append(preset.id)
                }
                cfg.enabledSkills = skills
                try? cfg.save()
                self?.onConfigChange?(cfg)
            }
            menuItemTargets.append(skillTarget)
            let skillItem = NSMenuItem(title: "  \(preset.name)", action: #selector(MenuItemTarget.invoke), keyEquivalent: "")
            skillItem.target = skillTarget
            skillItem.state = isEnabled ? .on : .off
            menu.addItem(skillItem)
        }

        // ── 模式设置 ──

        menu.addItem(NSMenuItem.separator())

        let toggleTarget = MenuItemTarget { [weak self] in
            var cfg = Config.load()
            let current = cfg.toggleMode?.value ?? false
            cfg.toggleMode = FlexBool(!current)
            try? cfg.save()
            self?.onConfigChange?(cfg)
        }
        menuItemTargets.append(toggleTarget)
        let toggleItem = NSMenuItem(title: "Toggle Mode", action: #selector(MenuItemTarget.invoke), keyEquivalent: "")
        toggleItem.target = toggleTarget
        toggleItem.state = (config.toggleMode?.value ?? false) ? .on : .off
        menu.addItem(toggleItem)

        let launchTarget = MenuItemTarget { [weak self] in
            LaunchAtLogin.toggle()
            self?.buildMenu()
        }
        menuItemTargets.append(launchTarget)
        let launchItem = NSMenuItem(title: "Launch at Login", action: #selector(MenuItemTarget.invoke), keyEquivalent: "")
        launchItem.target = launchTarget
        launchItem.state = LaunchAtLogin.isEnabled ? .on : .off
        menu.addItem(launchItem)

        // ── 工具 ──

        menu.addItem(NSMenuItem.separator())

        let lastText = (NSApplication.shared.delegate as? AppDelegate)?.lastTranscription
        let copyItem = NSMenuItem(title: "Copy Last Dictation", action: lastText != nil ? #selector(copyLastTranscription) : nil, keyEquivalent: "c")
        copyItem.target = self
        if lastText == nil { copyItem.isEnabled = false }
        menu.addItem(copyItem)

        let hasRecording = (NSApplication.shared.delegate as? AppDelegate)?.lastRecordingURL != nil
        let retryTarget = MenuItemTarget {
            (NSApplication.shared.delegate as? AppDelegate)?.retryLastRecording()
        }
        menuItemTargets.append(retryTarget)
        let retryItem = NSMenuItem(title: "Retry Last Recording", action: hasRecording ? #selector(MenuItemTarget.invoke) : nil, keyEquivalent: "t")
        retryItem.target = retryTarget
        if !hasRecording { retryItem.isEnabled = false }
        menu.addItem(retryItem)

        let dictTarget = MenuItemTarget {
            StatusBarController.openDictionary()
        }
        menuItemTargets.append(dictTarget)
        let dictItem = NSMenuItem(title: "Edit Dictionary...", action: #selector(MenuItemTarget.invoke), keyEquivalent: "d")
        dictItem.target = dictTarget
        menu.addItem(dictItem)

        // ── 配置 ──

        menu.addItem(NSMenuItem.separator())

        let reloadItem = NSMenuItem(title: "Reload Configuration", action: #selector(reloadConfiguration), keyEquivalent: "r")
        reloadItem.target = self
        menu.addItem(reloadItem)

        let openItem = NSMenuItem(title: "Open Configuration", action: #selector(openConfiguration), keyEquivalent: "o")
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    @objc private func reloadConfiguration() {
        guard let delegate = NSApplication.shared.delegate as? AppDelegate else { return }
        delegate.reloadConfig()
    }

    @objc private func openConfiguration() {
        let configFile = Config.configFile
        if !FileManager.default.fileExists(atPath: configFile.path) {
            let config = Config.defaultConfig
            try? config.save()
        }
        NSWorkspace.shared.open(configFile)
    }

    /// 打开用户词典文件（不存在时创建模板）
    static func openDictionary() {
        let dictFile = Config.configDir.appendingPathComponent("dictionary.txt")
        if !FileManager.default.fileExists(atPath: dictFile.path) {
            let template = """
            # VoiceFlow 用户词典
            # 每行一个词语，ASR 识别时会优先匹配这些词
            # 以 # 开头的行为注释
            #
            # 示例：
            # Claude
            # VoiceFlow
            # GPT-4

            """
            try? FileManager.default.createDirectory(at: Config.configDir, withIntermediateDirectories: true)
            try? template.write(to: dictFile, atomically: true, encoding: .utf8)
        }
        NSWorkspace.shared.open(dictFile)
    }

    private func updateIcon() {
        stopAnimation()

        switch state {
        case .idle:
            setIcon(StatusBarController.drawLogo(active: false))
        case .recording:
            startRecordingAnimation()
        case .transcribing:
            startTranscribingAnimation()
        case .waitingForPermission:
            setIcon(StatusBarController.drawLockIcon())
        case .error:
            setIcon(StatusBarController.drawWarningIcon())
        }
    }

    // MARK: - Recording animation: wave

    private static let waveFrameCount = 30

    private static func prerenderWaveFrames() -> [NSImage] {
        let count = waveFrameCount
        let baseHeights: [CGFloat] = [4, 8, 12, 8, 4]
        let minScale: CGFloat = 0.3
        let phaseOffsets: [Double] = [0.0, 0.15, 0.3, 0.45, 0.6]

        return (0..<count).map { frame in
            let t = Double(frame) / Double(count)
            let size = NSSize(width: 18, height: 18)
            let image = NSImage(size: size, flipped: false) { rect in
                NSColor.black.setFill()
                let barWidth: CGFloat = 2.0
                let gap: CGFloat = 2.5
                let radius: CGFloat = 1.5
                let centerX = rect.midX
                let centerY = rect.midY
                let totalWidth = CGFloat(baseHeights.count) * barWidth + CGFloat(baseHeights.count - 1) * gap
                let startX = centerX - totalWidth / 2

                for (i, baseHeight) in baseHeights.enumerated() {
                    let phase = t - phaseOffsets[i]
                    let scale = minScale + (1.0 - minScale) * CGFloat((sin(phase * 2.0 * .pi) + 1.0) / 2.0)
                    let height = baseHeight * scale
                    let x = startX + CGFloat(i) * (barWidth + gap)
                    let y = centerY - height / 2
                    let barRect = NSRect(x: x, y: y, width: barWidth, height: height)
                    NSBezierPath(roundedRect: barRect, xRadius: radius, yRadius: radius).fill()
                }
                return true
            }
            image.isTemplate = true
            return image
        }
    }

    private func startRecordingAnimation() {
        animationFrame = 0
        animationFrames = StatusBarController.prerenderWaveFrames()
        setIcon(animationFrames[0])

        animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.animationFrame = (self.animationFrame + 1) % StatusBarController.waveFrameCount
            self.setIcon(self.animationFrames[self.animationFrame])
        }
    }

    // MARK: - Transcribing animation: bouncing dots

    private static let transcribeFrameCount = 30

    private static func prerenderTranscribeFrames() -> [NSImage] {
        let count = transcribeFrameCount
        let maxBounce: CGFloat = 3.0
        return (0..<count).map { frame in
            let t = Double(frame) / Double(count)
            let size = NSSize(width: 18, height: 18)
            let image = NSImage(size: size, flipped: false) { rect in
                NSColor.black.setFill()
                let dotSize: CGFloat = 3
                let gap: CGFloat = 3.0
                let centerY = rect.midY - dotSize / 2
                let totalWidth = 3 * dotSize + 2 * gap
                let startX = rect.midX - totalWidth / 2

                for i in 0..<3 {
                    let phase = t - Double(i) * 0.15
                    let bounce = maxBounce * CGFloat(max(0, sin(phase * 2.0 * .pi)))
                    let x = startX + CGFloat(i) * (dotSize + gap)
                    let y = centerY + bounce
                    let dotRect = NSRect(x: x, y: y, width: dotSize, height: dotSize)
                    NSBezierPath(ovalIn: dotRect).fill()
                }
                return true
            }
            image.isTemplate = true
            return image
        }
    }

    private func startTranscribingAnimation() {
        animationFrame = 0
        animationFrames = StatusBarController.prerenderTranscribeFrames()
        setIcon(animationFrames[0])

        animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.animationFrame = (self.animationFrame + 1) % StatusBarController.transcribeFrameCount
            self.setIcon(self.animationFrames[self.animationFrame])
        }
    }

    private func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
        animationFrames = []
    }

    private func setIcon(_ image: NSImage) {
        DispatchQueue.main.async {
            if let button = self.statusItem.button {
                button.image = image
                button.image?.isTemplate = true
            }
        }
    }

    // MARK: - Custom drawn icons

    static func drawLogo(active: Bool) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setFill()
            let barWidth: CGFloat = 2.0
            let gap: CGFloat = 2.5
            let radius: CGFloat = 1.5
            let heights: [CGFloat] = [4, 8, 12, 8, 4]
            let totalWidth = CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * gap
            let startX = rect.midX - totalWidth / 2

            for (i, height) in heights.enumerated() {
                let x = startX + CGFloat(i) * (barWidth + gap)
                let y = rect.midY - height / 2
                let barRect = NSRect(x: x, y: y, width: barWidth, height: height)
                NSBezierPath(roundedRect: barRect, xRadius: radius, yRadius: radius).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    static func drawLockIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setStroke()
            NSColor.black.setFill()
            let centerX = rect.midX
            let bodyRect = NSRect(x: centerX - 4, y: 2, width: 8, height: 7)
            NSBezierPath(roundedRect: bodyRect, xRadius: 1.5, yRadius: 1.5).fill()
            let shacklePath = NSBezierPath()
            shacklePath.move(to: NSPoint(x: centerX - 2.5, y: 9))
            shacklePath.curve(to: NSPoint(x: centerX + 2.5, y: 9),
                              controlPoint1: NSPoint(x: centerX - 2.5, y: 15),
                              controlPoint2: NSPoint(x: centerX + 2.5, y: 15))
            shacklePath.lineWidth = 1.8
            shacklePath.lineCapStyle = .round
            shacklePath.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }

    static func drawWarningIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setStroke()
            NSColor.black.setFill()
            let centerX = rect.midX
            let triangle = NSBezierPath()
            triangle.move(to: NSPoint(x: centerX, y: 16))
            triangle.line(to: NSPoint(x: centerX - 7, y: 3))
            triangle.line(to: NSPoint(x: centerX + 7, y: 3))
            triangle.close()
            triangle.lineWidth = 1.5
            triangle.lineJoinStyle = .round
            triangle.stroke()
            let stemRect = NSRect(x: centerX - 0.75, y: 7, width: 1.5, height: 5)
            NSBezierPath(roundedRect: stemRect, xRadius: 0.75, yRadius: 0.75).fill()
            let dotRect = NSRect(x: centerX - 1, y: 4.5, width: 2, height: 2)
            NSBezierPath(ovalIn: dotRect).fill()
            return true
        }
        image.isTemplate = true
        return image
    }
}
