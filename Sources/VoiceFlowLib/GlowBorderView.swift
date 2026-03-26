import SwiftUI

/// 极简跑马灯边框 — 细线条，沿路径匀速移动，无外溢光晕
struct GlowBorderView: View {
    let color: Color
    let cornerRadius: CGFloat
    let speed: Double

    init(color: Color, cornerRadius: CGFloat = 22, speed: Double = 2.0) {
        self.color = color
        self.cornerRadius = cornerRadius
        self.speed = speed
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let progress = fmod(time / speed, 1.0)
            let tailLength = 0.3
            let head = progress
            let tail = progress - tailLength

            ZStack {
                // 底层微弱全边框
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(color.opacity(0.15), lineWidth: 1)

                // 跑马灯光线
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .trim(from: max(0, CGFloat(tail)), to: CGFloat(head))
                    .stroke(color.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))

                // 跨越边界段
                if tail < 0 {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .trim(from: CGFloat(1.0 + tail), to: 1.0)
                        .stroke(color.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                }
            }
        }
    }
}
