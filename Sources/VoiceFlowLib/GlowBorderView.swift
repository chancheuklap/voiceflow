import SwiftUI

/// 跑马灯光晕边框 — 单个明亮光点沿圆角矩形边缘旋转
struct GlowBorderView: View {
    let color: Color
    let cornerRadius: CGFloat
    let speed: Double

    init(color: Color, cornerRadius: CGFloat = 16, speed: Double = 2.0) {
        self.color = color
        self.cornerRadius = cornerRadius
        self.speed = speed
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let rotation = Angle.degrees(fmod(time / speed * 360.0, 360.0))

            // 单个亮点 + 大段透明 = 明显的跑马灯效果
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(
                    AngularGradient(
                        stops: [
                            .init(color: color.opacity(0.8), location: 0.0),
                            .init(color: color.opacity(0.3), location: 0.08),
                            .init(color: color.opacity(0.05), location: 0.15),
                            .init(color: .clear, location: 0.25),
                            .init(color: .clear, location: 0.75),
                            .init(color: color.opacity(0.05), location: 0.85),
                            .init(color: color.opacity(0.3), location: 0.92),
                            .init(color: color.opacity(0.8), location: 1.0),
                        ],
                        center: .center,
                        angle: rotation
                    ),
                    lineWidth: 2
                )
        }
    }
}
