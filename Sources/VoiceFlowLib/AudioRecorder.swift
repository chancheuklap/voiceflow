import AVFoundation
import Foundation

class AudioRecorder {
    private var audioEngine: AVAudioEngine?
    private var isRecording = false

    /// Streaming 模式的回调 — 每次音频 tap 触发时发送 PCM s16le 数据
    var streamingCallback: ((Data) -> Void)?

    /// 当前音频电平（0.0-1.0），用于驱动波形动画
    private(set) var currentLevel: Float = 0

    /// Streaming 模式录音 — 音频通过 callback 实时发送，不写文件
    func startStreaming() throws {
        guard !isRecording else { return }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        let recordingFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        )!

        let converter = AVAudioConverter(from: format, to: recordingFormat)

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            guard let self = self, let converter = converter else { return }

            let convertedBuffer = AVAudioPCMBuffer(
                pcmFormat: recordingFormat,
                frameCapacity: AVAudioFrameCount(
                    Double(buffer.frameLength) * 16000.0 / format.sampleRate
                )
            )!

            var error: NSError?
            converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }

            if error == nil && convertedBuffer.frameLength > 0 {
                // 计算音频电平（用于波形动画）
                self.updateLevel(from: convertedBuffer)

                // 将 Float32 PCM 转换为 Int16 LE 并通过 callback 发送
                if let callback = self.streamingCallback {
                    let int16Data = self.convertToInt16LE(convertedBuffer)
                    callback(int16Data)
                }
            }
        }

        engine.prepare()
        try engine.start()

        audioEngine = engine
        isRecording = true
    }

    func stopStreaming() {
        guard isRecording else { return }

        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        isRecording = false
        currentLevel = 0
    }

    // MARK: - Float32 → Int16 LE 转换

    private func convertToInt16LE(_ buffer: AVAudioPCMBuffer) -> Data {
        guard let floatData = buffer.floatChannelData else { return Data() }

        let frameCount = Int(buffer.frameLength)
        var int16Data = Data(count: frameCount * 2) // 每个 sample 2 bytes

        int16Data.withUnsafeMutableBytes { rawBuffer in
            let int16Buffer = rawBuffer.bindMemory(to: Int16.self)
            for i in 0..<frameCount {
                let sample = floatData[0][i]
                // 限幅到 [-1.0, 1.0] 再转 Int16
                let clamped = max(-1.0, min(1.0, sample))
                int16Buffer[i] = Int16(clamped * Float(Int16.max))
            }
        }

        return int16Data
    }

    // MARK: - 音频电平计算

    private func updateLevel(from buffer: AVAudioPCMBuffer) {
        guard let floatData = buffer.floatChannelData else { return }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }

        var sum: Float = 0
        for i in 0..<frameCount {
            let sample = floatData[0][i]
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(frameCount))
        // 简单的平滑 + 归一化到 0-1（RMS 通常在 0.0-0.3 范围）
        let normalized = min(1.0, rms * 4.0)
        currentLevel = currentLevel * 0.3 + normalized * 0.7
    }
}
