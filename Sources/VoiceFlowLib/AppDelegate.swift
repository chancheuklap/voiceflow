import AppKit

public class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBar: StatusBarController!
    var hotkeyManager: HotkeyManager?
    var journalHotkeyManager: HotkeyManager?
    /// 当前是否处于日记模式（录音结果保存到备忘录而非插入光标）
    var isJournalMode = false
    var recorder: AudioRecorder!
    var inserter: TextInserter!
    var config: Config!
    var asrEngine: SonioxEngine?
    var llmProvider: LLMProvider?
    var asyncReplacer: AsyncReplacer!
    var floatingPill: FloatingPill!
    var soundFeedback: SoundFeedback!
    var levelTimer: Timer?
    var isPressed = false
    var isReady = false
    public var lastTranscription: String?
    /// 上一次录音的本地文件路径（用于重试）
    public var lastRecordingURL: URL?

    // MARK: - 缓存：combined preset（skill 配置不变时无需每次重算）
    private var cachedCombinedPreset: Preset?
    private var cachedSkillIds: [String] = []

    /// 日记模式的 in-flight LLM task（防止快速连续触发产生重复条目）
    private var journalTask: Task<Void, Never>?

    /// 获取合并 preset，命中缓存时直接返回，skill 列表变更时自动重算
    private func getCombinedPreset() -> Preset? {
        let currentSkills = config.effectiveSkills
        if currentSkills != cachedSkillIds || cachedCombinedPreset == nil {
            cachedCombinedPreset = PresetManager.buildCombinedPreset(enabledSkillIds: currentSkills)
            cachedSkillIds = currentSkills
        }
        return cachedCombinedPreset
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // 设置应用图标
        loadAppIcon()

        statusBar = StatusBarController()
        recorder = AudioRecorder()
        inserter = TextInserter()
        floatingPill = FloatingPill()
        soundFeedback = SoundFeedback()
        asyncReplacer = AsyncReplacer(inserter: inserter)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.setup()
        }
    }

    private func loadAppIcon() {
        // 按优先级查找图标：Homebrew Cellar → 配置目录 → 可执行文件同级
        let candidates = [
            "/opt/homebrew/share/voiceflow/icon.png",
            Config.configDir.appendingPathComponent("icon.png").path,
            Bundle.main.bundlePath + "/../share/voiceflow/icon.png",
        ]
        for path in candidates {
            if let image = NSImage(contentsOfFile: path) {
                NSApplication.shared.applicationIconImage = image
                return
            }
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

        // 启动时清理 7 天前的录音
        RecordingStore.cleanupOldRecordings()

        // 在备忘录中创建今天的日记（如果还没有）
        NotesIntegration.ensureTodayNote()

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

        // 初始化 LLM
        if let key = config.llmApiKey, !key.isEmpty,
           let baseURL = config.llmBaseURL, !baseURL.isEmpty,
           let model = config.llmModel, !model.isEmpty {
            llmProvider = VolcengineLLM(apiKey: key, baseURL: baseURL, model: model)
            let skillNames = config.effectiveSkills.compactMap { PresetManager.find(id: $0)?.name }
            print("LLM: configured (\(model), skills: \(skillNames.joined(separator: " + ")))")
        } else {
            print("LLM: not configured (ASR text will be used as-is)")
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

        // 注册日记模式快捷键
        setupJournalHotkey()

        isReady = true
        statusBar.state = .idle
        statusBar.onConfigChange = { [weak self] config in
            self?.applyConfigChange(config)
        }
        statusBar.buildMenu()

        let hotkeyDesc = KeyCodes.describe(keyCode: config.hotkey.keyCode, modifiers: config.hotkey.modifiers)
        print("VoiceFlow v\(VoiceFlow.version)")
        print("Hotkey: \(hotkeyDesc)")
        if let jh = config.journalHotkey {
            let jhDesc = KeyCodes.describe(keyCode: jh.keyCode, modifiers: jh.modifiers)
            print("Journal hotkey: \(jhDesc)")
        }
        print("Ready.")
    }

    /// 重新识别上一次的录音
    public func retryLastRecording() {
        guard let url = lastRecordingURL,
              let pcmData = RecordingStore.loadPCM(from: url),
              let apiKey = config.sonioxApiKey, !apiKey.isEmpty else {
            floatingPill.showError("无可重试的录音")
            soundFeedback.playError()
            return
        }

        print("Retrying recording: \(url.lastPathComponent)")
        floatingPill.show(state: .processing)
        statusBar.state = .transcribing

        let engine = SonioxEngine(apiKey: apiKey)

        engine.onInterimText = { [weak self] text in
            self?.floatingPill.updateText(text)
        }
        engine.onFinalText = { _ in }

        engine.onComplete = { [weak self] text in
            guard let self = self else { return }
            if !text.isEmpty {
                self.lastTranscription = text
                self.asyncReplacer.processAndInsert(
                    asrText: text,
                    llmProvider: self.llmProvider,
                    preset: self.getCombinedPreset(),
                    onPolishStart: { self.floatingPill.show(state: .polishing) },
                    onComplete: { finalText, _ in
                        self.lastTranscription = finalText
                        self.floatingPill.hide()
                        self.statusBar.state = .idle
                    }
                )
            } else {
                self.floatingPill.showError("重试未识别到内容")
                self.statusBar.state = .idle
            }
            Task { try? await engine.close() }
        }

        engine.onError = { [weak self] error in
            self?.floatingPill.showError("重试失败")
            self?.soundFeedback.playError()
            self?.statusBar.state = .idle
            Task { try? await engine.close() }
        }

        // 发送保存的音频数据
        Task {
            do {
                let terms = PresetManager.loadDictionary()
                try await engine.connect(terms: terms)
                // 分块发送（每次 3200 bytes = 100ms @16kHz mono s16le）
                let chunkSize = 3200
                var offset = 0
                while offset < pcmData.count {
                    let end = min(offset + chunkSize, pcmData.count)
                    let chunk = pcmData[offset..<end]
                    try await engine.sendAudio(Data(chunk))
                    offset = end
                }
                try await engine.finishInput()
            } catch {
                DispatchQueue.main.async {
                    self.floatingPill.showError("重试连接失败")
                    self.statusBar.state = .idle
                }
            }
        }
    }

    // MARK: - 日记模式

    private func setupJournalHotkey() {
        journalHotkeyManager?.stop()
        journalHotkeyManager = nil

        guard let jh = config.journalHotkey else { return }

        journalHotkeyManager = HotkeyManager(
            keyCode: jh.keyCode,
            modifiers: jh.modifierFlags
        )
        journalHotkeyManager?.start(
            onKeyDown: { [weak self] in
                self?.isJournalMode = true
                self?.handleKeyDown()
            },
            onKeyUp: { [weak self] in
                self?.handleKeyUp()
            }
        )
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

        // 重新注册日记快捷键
        setupJournalHotkey()

        // 重新初始化 LLM
        if let key = config.llmApiKey, !key.isEmpty,
           let baseURL = config.llmBaseURL, !baseURL.isEmpty,
           let model = config.llmModel, !model.isEmpty {
            llmProvider = VolcengineLLM(apiKey: key, baseURL: baseURL, model: model)
            let skillNames = config.effectiveSkills.compactMap { PresetManager.find(id: $0)?.name }
            print("LLM skills: \(skillNames.joined(separator: " + "))")
        } else {
            llmProvider = nil
        }

        // 配置变更时清除缓存的 combined preset
        cachedCombinedPreset = nil
        cachedSkillIds = []

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

        // 清理上一次的引擎和状态（防止快速连按时冲突）
        if let oldEngine = asrEngine {
            asrEngine = nil
            Task { try? await oldEngine.close() }
        }
        recorder.stopStreaming()
        recorder.streamingCallback = nil
        stopLevelTimer()
        floatingPill.hide() // 强制关闭之前的弹窗（包括取消 hideTimer）

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

            // 保存录音到本地（无论成功与否，用于重试）
            let recordingData = self.recorder.lastRecordingData
            if !recordingData.isEmpty {
                self.lastRecordingURL = RecordingStore.save(pcmData: recordingData)
            }

            if !text.isEmpty {
                self.lastTranscription = text

                if self.isJournalMode {
                    // 日记模式：保存到备忘录
                    self.isJournalMode = false
                    self.processForJournal(asrText: text)
                } else {
                    // 普通模式：插入到光标
                    self.processForCursor(asrText: text)
                }
            } else {
                self.isJournalMode = false
                self.floatingPill.hide()
                self.statusBar.state = .idle
                self.statusBar.buildMenu()
            }

            Task {
                try? await self.asrEngine?.close()
                self.asrEngine = nil
            }
        }

        engine.onError = { [weak self] error in
            guard let self = self else { return }

            // 识别失败时也保存录音（重试用）
            let recordingData = self.recorder.lastRecordingData
            if !recordingData.isEmpty {
                self.lastRecordingURL = RecordingStore.save(pcmData: recordingData)
            }

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
                let terms = PresetManager.loadDictionary()
                try await engine.connect(terms: terms)

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

    // MARK: - 文本处理路由

    /// 普通模式：LLM 润色后插入光标
    private func processForCursor(asrText: String) {
        asyncReplacer.processAndInsert(
            asrText: asrText,
            llmProvider: llmProvider,
            preset: getCombinedPreset(),
            onPolishStart: {
                self.floatingPill.show(state: .polishing)
            },
            onComplete: { finalText, _ in
                self.lastTranscription = finalText
                self.floatingPill.hide()
                self.statusBar.state = .idle
            }
        )
    }

    /// 日记模式：LLM 润色后保存到备忘录
    private func processForJournal(asrText: String) {
        // 取消上一个未完成的日记 LLM 任务，防止快速连续触发产生重复条目
        journalTask?.cancel()

        guard let provider = llmProvider, let preset = getCombinedPreset() else {
            // 无 LLM，直接保存原文到备忘录
            NotesIntegration.appendToDaily(text: asrText)
            floatingPill.showDone("已保存到备忘录")
            statusBar.state = .idle
            return
        }

        floatingPill.show(state: .polishing)

        journalTask = Task {
            let finalText: String
            do {
                let polished = try await provider.process(text: asrText, preset: preset)
                guard !Task.isCancelled else { return }
                finalText = polished.isEmpty ? asrText : polished
            } catch {
                guard !Task.isCancelled else { return }
                finalText = asrText
            }

            NotesIntegration.appendToDaily(text: finalText)

            DispatchQueue.main.async { [weak self] in
                self?.lastTranscription = finalText
                self?.floatingPill.showDone("已保存到备忘录")
                self?.statusBar.state = .idle
            }
        }
    }

    private func stopLevelTimer() {
        levelTimer?.invalidate()
        levelTimer = nil
    }
}
