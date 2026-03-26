import Foundation

public struct Config: Codable {
    public var hotkey: HotkeyConfig
    public var toggleMode: FlexBool?
    public var sonioxApiKey: String?
    public var llmApiKey: String?
    public var llmBaseURL: String?
    public var llmModel: String?
    /// 启用的 skill ID 列表（可同时开多个，prompt 会合并）
    /// 可选值: grammar, filter, structure, formal, simplify
    public var enabledSkills: [String]?
    public var startSound: FlexBool?
    public var stopSound: FlexBool?

    /// 获取启用的 skill 列表（默认开启 grammar + filter）
    public var effectiveSkills: [String] {
        return enabledSkills ?? ["grammar", "filter"]
    }

    public static let defaultConfig = Config(
        hotkey: HotkeyConfig(keyCode: 63, modifiers: []),
        toggleMode: FlexBool(false),
        sonioxApiKey: nil,
        llmApiKey: nil,
        llmBaseURL: "https://ark.cn-beijing.volces.com/api/v3",
        llmModel: "doubao-1.5-pro-32k",
        enabledSkills: ["grammar", "filter"],
        startSound: FlexBool(true),
        stopSound: FlexBool(true)
    )

    public static var configDir: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".config/voiceflow")
    }

    public static var configFile: URL {
        configDir.appendingPathComponent("config.json")
    }

    public static func load() -> Config {
        guard let data = try? Data(contentsOf: configFile) else {
            let config = Config.defaultConfig
            try? config.save()
            return config
        }

        do {
            return try JSONDecoder().decode(Config.self, from: data)
        } catch {
            fputs("Warning: unable to parse \(configFile.path): \(error.localizedDescription)\n", stderr)
            return Config.defaultConfig
        }
    }

    public func save() throws {
        try FileManager.default.createDirectory(at: Config.configDir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(self)
        try data.write(to: Config.configFile)
    }
}

public struct FlexBool: Codable {
    public let value: Bool

    public init(_ value: Bool) { self.value = value }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let b = try? container.decode(Bool.self) {
            value = b
        } else if let s = try? container.decode(String.self) {
            value = ["true", "yes", "1"].contains(s.lowercased())
        } else if let i = try? container.decode(Int.self) {
            value = i != 0
        } else {
            value = false
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

public struct HotkeyConfig: Codable {
    public var keyCode: UInt16
    public var modifiers: [String]

    public init(keyCode: UInt16, modifiers: [String]) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public var modifierFlags: UInt64 {
        var flags: UInt64 = 0
        for mod in modifiers {
            switch mod.lowercased() {
            case "cmd", "command": flags |= UInt64(1 << 20)
            case "shift": flags |= UInt64(1 << 17)
            case "ctrl", "control": flags |= UInt64(1 << 18)
            case "opt", "option", "alt": flags |= UInt64(1 << 19)
            default: break
            }
        }
        return flags
    }
}
