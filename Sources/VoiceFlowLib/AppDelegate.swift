import AppKit

public class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBar: StatusBarController!
    var hotkeyManager: HotkeyManager?
    var recorder: AudioRecorder!
    var inserter: TextInserter!
    var config: Config!
    var asrEngine: SonioxEngine?
    var isPressed = false
    var isReady = false
    public var lastTranscription: String?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        statusBar = StatusBarController()
        recorder = AudioRecorder()
        inserter = TextInserter()

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
            statusBar.state = .error("API Key 未配置")
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                if case .error = self?.statusBar.state { self?.statusBar.state = .idle }
            }
            return
        }

        isPressed = true
        statusBar.state = .recording

        // 创建 Soniox 引擎（每次新建连接）
        let engine = SonioxEngine(apiKey: apiKey)

        engine.onInterimText = { [weak self] text in
            // 实时显示（Phase 3 将更新到 FloatingPill）
            print("\r\u{1B}[K[interim] \(text)", terminator: "")
            fflush(stdout)
        }

        engine.onFinalText = { text in
            print("\n[final] \(text)")
        }

        engine.onComplete = { [weak self] text in
            guard let self = self else { return }
            print("\n[complete] \(text)")

            if !text.isEmpty {
                self.lastTranscription = text
                self.inserter.insert(text: text)
            }

            self.statusBar.state = .idle
            self.statusBar.buildMenu()

            // 清理引擎
            Task {
                try? await self.asrEngine?.close()
                self.asrEngine = nil
            }
        }

        engine.onError = { [weak self] error in
            print("\n[error] \(error.localizedDescription)")
            self?.statusBar.state = .error(error.localizedDescription)
            self?.isPressed = false
            self?.recorder.stopStreaming()

            Task {
                try? await self?.asrEngine?.close()
                self?.asrEngine = nil
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                if case .error = self?.statusBar.state { self?.statusBar.state = .idle }
            }
        }

        self.asrEngine = engine

        // 连接 Soniox + 开始录音
        Task {
            do {
                try await engine.connect()
                print("Soniox: connected")

                // 设置音频 streaming callback
                self.recorder.streamingCallback = { [weak engine] data in
                    Task {
                        try? await engine?.sendAudio(data)
                    }
                }

                // 开始麦克风录音
                try self.recorder.startStreaming()
                print("Recording started...")
            } catch {
                print("Connection error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.statusBar.state = .error("连接失败")
                    self.isPressed = false
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                    if case .error = self?.statusBar.state { self?.statusBar.state = .idle }
                }
            }
        }
    }

    private func handleRecordingStop() {
        guard isPressed else { return }
        isPressed = false

        // 停止录音
        recorder.stopStreaming()
        recorder.streamingCallback = nil
        print("\nRecording stopped.")

        statusBar.state = .transcribing

        // 通知 Soniox 音频结束
        Task {
            do {
                try await asrEngine?.finishInput()
                print("Waiting for final result...")
                // onComplete 回调将处理最终结果
            } catch {
                print("Error finishing input: \(error.localizedDescription)")
                statusBar.state = .idle
            }
        }
    }
}
