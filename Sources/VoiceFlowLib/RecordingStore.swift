import Foundation

/// 录音文件管理 — 本地保存 + 7 天自动清理
struct RecordingStore {
    static let recordingsDir: URL = Config.configDir.appendingPathComponent("recordings")

    /// 确保录音目录存在
    static func ensureDir() {
        try? FileManager.default.createDirectory(at: recordingsDir, withIntermediateDirectories: true)
    }

    /// 保存 PCM 数据为 WAV 文件，返回文件路径
    static func save(pcmData: Data, sampleRate: Int = 16000) -> URL? {
        ensureDir()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let filename = "\(formatter.string(from: Date())).wav"
        let fileURL = recordingsDir.appendingPathComponent(filename)

        let wavData = buildWAV(pcmData: pcmData, sampleRate: sampleRate)
        do {
            try wavData.write(to: fileURL)
            return fileURL
        } catch {
            print("Recording save failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// 删除 7 天前的录音
    static func cleanupOldRecordings(olderThanDays days: Int = 7) {
        ensureDir()
        let fm = FileManager.default
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date())!

        guard let files = try? fm.contentsOfDirectory(at: recordingsDir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }

        var removed = 0
        for file in files where file.pathExtension == "wav" {
            guard let attrs = try? fm.attributesOfItem(atPath: file.path),
                  let modDate = attrs[.modificationDate] as? Date,
                  modDate < cutoff else { continue }
            try? fm.removeItem(at: file)
            removed += 1
        }
        if removed > 0 {
            print("Recordings: cleaned up \(removed) file(s) older than \(days) days")
        }
    }

    /// 从 WAV 文件中提取 PCM 数据（跳过 44 字节头）
    static func loadPCM(from url: URL) -> Data? {
        guard let data = try? Data(contentsOf: url), data.count > 44 else { return nil }
        // Data() 重建确保 startIndex=0，避免 slice 下标越界
        return Data(data.dropFirst(44))
    }

    // MARK: - WAV 文件构建

    private static func buildWAV(pcmData: Data, sampleRate: Int) -> Data {
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = UInt32(sampleRate) * UInt32(channels) * UInt32(bitsPerSample / 8)
        let blockAlign = channels * (bitsPerSample / 8)
        let dataSize = UInt32(pcmData.count)
        let fileSize = 36 + dataSize

        var wav = Data()

        // RIFF header
        wav.append(contentsOf: "RIFF".utf8)
        wav.append(uint32LE: fileSize)
        wav.append(contentsOf: "WAVE".utf8)

        // fmt chunk
        wav.append(contentsOf: "fmt ".utf8)
        wav.append(uint32LE: 16)                    // chunk size
        wav.append(uint16LE: 1)                      // PCM format
        wav.append(uint16LE: channels)
        wav.append(uint32LE: UInt32(sampleRate))
        wav.append(uint32LE: byteRate)
        wav.append(uint16LE: blockAlign)
        wav.append(uint16LE: bitsPerSample)

        // data chunk
        wav.append(contentsOf: "data".utf8)
        wav.append(uint32LE: dataSize)
        wav.append(pcmData)

        return wav
    }
}

// MARK: - Data helpers for little-endian writing

private extension Data {
    mutating func append(uint16LE value: UInt16) {
        var v = value.littleEndian
        append(Data(bytes: &v, count: 2))
    }

    mutating func append(uint32LE value: UInt32) {
        var v = value.littleEndian
        append(Data(bytes: &v, count: 4))
    }
}
