import AppKit

public class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBar: StatusBarController!
    var hotkeyManager: HotkeyManager?
    var recorder: AudioRecorder!
    var inserter: TextInserter!
    var config: Config!
    var asrEngine: SonioxEngine?
    var floatingPill: FloatingPill!
    var soundFeedback: SoundFeedback!
    var levelTimer: Timer?
    var isPressed = false
    var isReady = false
    public var lastTranscription: String?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        statusBar = StatusBarController()
        recorder = AudioRecorder()
        inserter = TextInserter()
        floatingPill = FloatingPill()
        soundFeedback = SoundFeedback()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.setup()
        }
    }

    private func setup() {
        do {
            try setupInner()
        } catch {
            print("Fatal setup error: \(error.localizedDescription)")
        }
    }

    private func setupInner() throws {
        config = Config.load()

        if Permissions.didUpgrade() {
            print("Upgrade detected")
        }

        if !AXIsProcessTrusted() {
            DispatchQueue.main.async {
                self.statusBar.state = .waitingForPermission
                self.statusBar.buildMenu()
            }
        }

        Permissions.ensureMicrophone()

        if !AXIsProcessTrusted() {
            print("Accessibility: not granted")
            Permissions.openAccessibilitySettings()
            print("Waiting for Accessibility permission...")
            while !AXIsProcessTrusted() {
                Thread.sleep(forTimeInterval: 0.5)
            }
            print("Accessibility: granted")
        } else {
            print("Accessibility: granted")
        }

        if let key = config.sonioxApiKey, !key.isEmpty {
            print("Soniox: API key configured")
        } else {
            print("Warning: Soniox API Key not set. Edit ~/.config/voiceflow/config.json")
        }

        DispatchQueue.main.async { [weak self] in
            self?.startListening()
        }
    }

    private func startListening() {
        hotkeyManager = HotkeyManager(
            keyCode: config.hotkey.keyCode,
            modifiers: config.hotkey.modifierFlags
        )

        hotkeyManager?.start(
            onKeyDown: { [weak self] in
                self?.handleKeyDown()
            },
            onKeyUp: { [weak self] in
                self?.handleKeyUp()
            }
        )

        isReady = true
        statusBar.state = .idle
        statusBar.buildMenu()

        let hotkeyDesc = KeyCodes.describe(keyCode: config.hotkey.keyCode, modifiers: config.hotkey.modifiers)
        print("VoiceFlow v\(VoiceFlow.version)")
        print("Hotkey: \(hotkeyDesc)")
        print("Ready.")
    }

    public func reloadConfig() {
        let newConfig = Config.load()
        applyConfigChange(newConfig)
    }

    func applyConfigChange(_ newConfig: Config) {
        guard isReady else { return }
        config = newConfig

        hotkeyManager?.stop()
        hotkeyManager = HotkeyManager(
            keyCode: config.hotkey.keyCode,
            modifiers: config.hotkey.modifierFlags
        )
        hotkeyManager?.start(
            onKeyDown: { [weak self] in self?.handleKeyDown() },
            onKeyUp: { [weak self] in self?.handleKeyUp() }
        )

        statusBar.buildMenu()
        let hotkeyDesc = KeyCodes.describe(keyCode: config.hotkey.keyCode, modifiers: config.hotkey.modifiers)
        print("Config updated: hotkey=\(hotkeyDesc)")
    }

    // MARK: - 热键处理

    private func handleKeyDown() {
        guard isReady else { return }

        let isToggle = config.toggleMode?.value ?? false

        if isToggle {
            if isPressed {
                handleRecordingStop()
            } else {
                handleRecordingStart()
            }
        } else {
            guard !isPressed else { return }
            handleRecordingStart()
        }
    }

    private func handleKeyUp() {
        let isToggle = config.toggleMode?.value ?? false
        if isToggle { return }
        handleRecordingStop()
    }

    // MARK: - Soniox Streaming 录音流程

    private func handleRecordingStart() {
        guard !isPressed else { return }
        guard let apiKey = config.sonioxApiKey, !apiKey.isEmpty else {
            print("Error: Soniox API Key not configured")
            floatingPill.showError("API Key 未配置")
            soundFeedback.playError()
            return
        }

        isPressed = true
        statusBar.state = .recording

        // 清理上一次的引擎（防止重复使用时连接残留）
        if let oldEngine = asrEngine {
            asrEngine = nil
            Task { try? await oldEngine.close() }
        }

        // 提示音 + 弹窗
        if config.startSound?.value ?? true {
            soundFeedback.playStart()
        }
        floatingPill.show(state: .recording)

        // 启动音频电平更新定时器（驱动波形动画）
        levelTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.floatingPill.updateAudioLevel(CGFloat(self.recorder.currentLevel))
        }

        // 创建 Soniox 引擎
        let engine = SonioxEngine(apiKey: apiKey)

        engine.onInterimText = { [weak self] text in
            self?.floatingPill.updateText(text)
        }

        engine.onFinalText = { _ in }

        engine.onComplete = { [weak self] text in
            guard let self = self else { return }

            if !text.isEmpty {
                self.lastTranscription = text
                self.inserter.insert(text: text)
                self.floatingPill.showDone(text)
            } else {
                self.floatingPill.hide()
            }

            self.statusBar.state = .idle
            self.statusBar.buildMenu()

            Task {
                try? await self.asrEngine?.close()
                self.asrEngine = nil
            }
        }

        engine.onError = { [weak self] error in
            guard let self = self else { return }
            self.floatingPill.showError(error.localizedDescription)
            self.soundFeedback.playError()
            self.statusBar.state = .idle
            self.isPressed = false
            self.recorder.stopStreaming()
            self.recorder.streamingCallback = nil
            self.stopLevelTimer()

            Task {
                try? await self.asrEngine?.close()
                self.asrEngine = nil
            }
        }

        self.asrEngine = engine

        // 关键：先开始录音（缓冲到内存），再连接 Soniox（防止首字丢失）
        do {
            try self.recorder.startStreaming()
        } catch {
            self.floatingPill.showError("麦克风启动失败")
            self.isPressed = false
            self.stopLevelTimer()
            return
        }

        Task {
            do {
                try await engine.connect()

                // 连接成功后设置 callback，缓冲区中的音频会自动发送
                self.recorder.streamingCallback = { [weak engine] data in
                    Task {
                        try? await engine?.sendAudio(data)
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.floatingPill.showError("连接失败")
                    self.soundFeedback.playError()
                    self.statusBar.state = .idle
                    self.isPressed = false
                    self.recorder.stopStreaming()
                    self.stopLevelTimer()
                }
            }
        }
    }

    private func handleRecordingStop() {
        guard isPressed else { return }
        isPressed = false

        // 提示音
        if config.stopSound?.value ?? true {
            soundFeedback.playStop()
        }

        // 弹窗切换到"识别中"
        floatingPill.show(state: .processing)
        statusBar.state = .transcribing

        // 延迟 300ms 再停止录音和发 finish（防止尾字丢失）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self = self else { return }
            self.recorder.stopStreaming()
            self.recorder.streamingCallback = nil
            self.stopLevelTimer()

            Task {
                do {
                    try await self.asrEngine?.finishInput()
                } catch {
                    self.floatingPill.showError("识别失败")
                    self.statusBar.state = .idle
                }
            }
        }
    }

    private func stopLevelTimer() {
        levelTimer?.invalidate()
        levelTimer = nil
    }
}
