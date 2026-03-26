import SwiftUI

/// Spokenly 风格竖向胶囊点阵波形
/// 动画速度快、对音量变化反应灵敏
struct WaveformView: View {
    let audioLevel: CGFloat
    let dotCount = 20

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            Canvas { context, size in
                let dotWidth: CGFloat = 3.5
                let gap: CGFloat = 3.5
                let totalWidth = CGFloat(dotCount) * dotWidth + CGFloat(dotCount - 1) * gap
                let startX = (size.width - totalWidth) / 2
                let centerY = size.height / 2
                let minHeight: CGFloat = 3.5
                let maxHeight: CGFloat = 16

                let time = timeline.date.timeIntervalSinceReferenceDate

                for i in 0..<dotCount {
                    let x = startX + CGFloat(i) * (dotWidth + gap)

                    // 多层波叠加 — 更灵动的效果
                    let phase1 = sin((time * 10.0) - Double(i) * 0.4)
                    let phase2 = sin((time * 7.0) - Double(i) * 0.6 + 1.0)
                    let combined = (phase1 * 0.6 + phase2 * 0.4)
                    let normalizedWave = CGFloat((combined + 1.0) / 2.0)

                    // 中心高、两端低的包络
                    let center = CGFloat(dotCount - 1) / 2.0
                    let distFromCenter = abs(CGFloat(i) - center) / center
                    let envelope = 1.0 - distFromCenter * 0.5

                    let level = max(audioLevel, 0.08) // 最小也有轻微动画
                    let dynamicHeight = minHeight + (maxHeight - minHeight) * level * normalizedWave * envelope
                    let height = max(minHeight, dynamicHeight)
                    let y = centerY - height / 2

                    let rect = CGRect(x: x, y: y, width: dotWidth, height: height)
                    let path = Path(roundedRect: rect, cornerRadius: dotWidth / 2)

                    let opacity = 0.4 + level * normalizedWave * 0.6
                    context.fill(path, with: .color(.primary.opacity(opacity)))
                }
            }
        }
        .frame(height: 20)
    }
}
