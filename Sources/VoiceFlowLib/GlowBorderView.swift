import SwiftUI

/// 跑马灯光晕边框 — 光点沿圆角矩形路径匀速移动
/// 使用 .trim() 保证匀速（不用 AngularGradient，避免角上慢边上快）
struct GlowBorderView: View {
    let color: Color
    let cornerRadius: CGFloat
    let speed: Double // 秒/圈

    init(color: Color, cornerRadius: CGFloat = 16, speed: Double = 1.2) {
        self.color = color
        self.cornerRadius = cornerRadius
        self.speed = speed
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let progress = fmod(time / speed, 1.0) // 0.0 ~ 1.0 匀速

            let tailLength = 0.25 // 光尾占路径 25%
            let head = progress
            let tail = progress - tailLength

            ZStack {
                // 外圈光晕溢出（向弹窗外部扩散的柔和发光）
                RoundedRectangle(cornerRadius: cornerRadius)
                    .trim(from: max(0, CGFloat(tail)), to: CGFloat(head))
                    .stroke(color.opacity(0.6), lineWidth: 8)
                    .blur(radius: 10)

                if tail < 0 {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .trim(from: CGFloat(1.0 + tail), to: 1.0)
                        .stroke(color.opacity(0.6), lineWidth: 8)
                        .blur(radius: 10)
                }

                // 锐利内边框
                RoundedRectangle(cornerRadius: cornerRadius)
                    .trim(from: max(0, CGFloat(tail)), to: CGFloat(head))
                    .stroke(
                        LinearGradient(
                            colors: [color.opacity(0.0), color.opacity(0.9)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round)
                    )

                if tail < 0 {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .trim(from: CGFloat(1.0 + tail), to: 1.0)
                        .stroke(
                            LinearGradient(
                                colors: [color.opacity(0.0), color.opacity(0.5)],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            style: StrokeStyle(lineWidth: 2, lineCap: .round)
                        )
                }

                // 底层微弱全边框（让整个边框有一丝存在感）
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(color.opacity(0.1), lineWidth: 0.5)
            }
        }
    }
}
