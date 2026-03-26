import AppKit
import VoiceFlowLib

setvbuf(stdout, nil, _IOLBF, 0)
setvbuf(stderr, nil, _IOLBF, 0)

let args = CommandLine.arguments
let command = args.count > 1 ? args[1] : nil

switch command {
case "start", nil:
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)

    let delegate = AppDelegate()
    app.delegate = delegate

    signal(SIGINT) { _ in
        print("\nStopping VoiceFlow...")
        exit(0)
    }

    app.run()

case "status":
    let config = Config.load()
    let hotkeyDesc = KeyCodes.describe(keyCode: config.hotkey.keyCode, modifiers: config.hotkey.modifiers)
    print("VoiceFlow v\(VoiceFlow.version)")
    print("Config:      \(Config.configFile.path)")
    print("Hotkey:      \(hotkeyDesc)")
    print("Soniox key:  \(config.sonioxApiKey != nil ? "configured" : "not set")")
    print("LLM key:     \(config.llmApiKey != nil ? "configured" : "not set")")
    print("LLM model:   \(config.llmModel ?? "default")")
    let skillNames = config.effectiveSkills.compactMap { PresetManager.find(id: $0)?.name }
    print("Skills:      \(skillNames.isEmpty ? "none" : skillNames.joined(separator: " + "))")

case "--help", "-h", "help":
    print("""
    VoiceFlow v\(VoiceFlow.version) — Push-to-talk voice input with Soniox ASR + LLM polish

    USAGE:
        voiceflow              Start the voice input daemon (default)
        voiceflow start        Same as above
        voiceflow status       Show configuration
        voiceflow --help       Show this help message

    CONFIGURATION:
        Edit ~/.config/voiceflow/config.json to set:
        - sonioxApiKey:  Your Soniox API key
        - llmApiKey:     Your LLM API key (e.g. Volcengine/Doubao)
        - llmModel:      LLM model name
        - enabledSkills:  ["grammar", "filter", "structure", "formal", "simplify"]
    """)

default:
    print("Unknown command: \(command!)")
    print("Run 'voiceflow --help' for usage")
    exit(1)
}
