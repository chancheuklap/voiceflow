import SwiftUI

/// 跑马灯光晕边框 — 彩色光点沿圆角矩形边缘旋转
struct GlowBorderView: View {
    let color: Color
    let cornerRadius: CGFloat
    let speed: Double // 旋转一周的秒数

    init(color: Color, cornerRadius: CGFloat = 16, speed: Double = 2.0) {
        self.color = color
        self.cornerRadius = cornerRadius
        self.speed = speed
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let rotation = Angle.degrees((time / speed) * 360.0)

            ZStack {
                // 外发光层（模糊的光晕）
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(lineWidth: 3)
                    .fill(
                        AngularGradient(
                            colors: [
                                color.opacity(0.9),
                                color.opacity(0.5),
                                color.opacity(0.1),
                                .clear,
                                .clear,
                                .clear,
                                .clear,
                                color.opacity(0.1),
                                color.opacity(0.5),
                                color.opacity(0.9),
                            ],
                            center: .center,
                            angle: rotation
                        )
                    )
                    .blur(radius: 4)

                // 锐利内边框层
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(lineWidth: 1.5)
                    .fill(
                        AngularGradient(
                            colors: [
                                color.opacity(0.8),
                                color.opacity(0.4),
                                color.opacity(0.05),
                                .clear,
                                .clear,
                                .clear,
                                .clear,
                                color.opacity(0.05),
                                color.opacity(0.4),
                                color.opacity(0.8),
                            ],
                            center: .center,
                            angle: rotation
                        )
                    )
            }
        }
    }
}
