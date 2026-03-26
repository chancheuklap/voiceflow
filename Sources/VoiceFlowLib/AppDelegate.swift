import AppKit

public class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBar: StatusBarController!
    var hotkeyManager: HotkeyManager?
    var recorder: AudioRecorder!
    var inserter: TextInserter!
    var config: Config!
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

        if config.sonioxApiKey == nil || config.sonioxApiKey!.isEmpty {
            print("Warning: Soniox API Key not configured. Set it in ~/.config/voiceflow/config.json")
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

    private func handleRecordingStart() {
        guard !isPressed else { return }
        isPressed = true
        statusBar.state = .recording

        do {
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("voiceflow-\(UUID().uuidString).wav")
            try recorder.startRecording(to: tempURL)
        } catch {
            print("Error: \(error.localizedDescription)")
            isPressed = false
            statusBar.state = .idle
        }
    }

    private func handleRecordingStop() {
        guard isPressed else { return }
        isPressed = false

        guard let audioURL = recorder.stopRecording() else {
            statusBar.state = .idle
            return
        }

        statusBar.state = .transcribing

        // Phase 1 临时实现: 录音完成后插入占位文字
        // Phase 2 将替换为 Soniox streaming ASR
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let fileSize = (try? FileManager.default.attributesOfItem(atPath: audioURL.path)[.size] as? Int) ?? 0
            let duration = Double(fileSize) / (16000.0 * 2.0)
            print("Recorded: \(String(format: "%.1f", duration))s (\(fileSize) bytes)")

            DispatchQueue.main.async {
                self.lastTranscription = "[VoiceFlow: recording captured]"
                self.inserter.insert(text: "[录音已捕获 \(String(format: "%.1f", duration))秒]")
                self.statusBar.state = .idle
                self.statusBar.buildMenu()
            }

            try? FileManager.default.removeItem(at: audioURL)
        }
    }
}
