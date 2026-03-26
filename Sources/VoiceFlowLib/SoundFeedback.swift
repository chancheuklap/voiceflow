import AVFoundation
import Foundation

/// 录音提示音 — 使用 macOS 系统内置音效
class SoundFeedback {
    private var startPlayer: AVAudioPlayer?
    private var stopPlayer: AVAudioPlayer?
    private var errorPlayer: AVAudioPlayer?

    init() {
        startPlayer = loadSystemSound("Tink")
        stopPlayer = loadSystemSound("Pop")
        errorPlayer = loadSystemSound("Basso")

        // 预加载到内存，避免首次播放延迟
        startPlayer?.prepareToPlay()
        stopPlayer?.prepareToPlay()
        errorPlayer?.prepareToPlay()
    }

    func playStart() {
        startPlayer?.currentTime = 0
        startPlayer?.play()
    }

    func playStop() {
        stopPlayer?.currentTime = 0
        stopPlayer?.play()
    }

    func playError() {
        errorPlayer?.currentTime = 0
        errorPlayer?.play()
    }

    private func loadSystemSound(_ name: String) -> AVAudioPlayer? {
        let url = URL(fileURLWithPath: "/System/Library/Sounds/\(name).aiff")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try? AVAudioPlayer(contentsOf: url)
    }
}
