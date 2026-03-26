import SwiftUI

/// 呼吸边框 — 柔和脉动
/// isRainbow=true 时彩虹色缓慢流动，false 时单色呼吸
struct GlowBorderView: View {
    let color: Color
    let cornerRadius: CGFloat
    let speed: Double
    let isRainbow: Bool

    init(color: Color, cornerRadius: CGFloat = 22, speed: Double = 2.0, isRainbow: Bool = false) {
        self.color = color
        self.cornerRadius = cornerRadius
        self.speed = speed
        self.isRainbow = isRainbow
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let breathe = 0.35 + 0.6 * ((sin(time * 2.0) + 1.0) / 2.0)

            if isRainbow {
                // 旋转线性渐变 — 颜色在宽扁 pill 上分布均匀
                let angle = time * 0.5
                let gradient = LinearGradient(
                    gradient: Gradient(colors: Self.elegantRainbow),
                    startPoint: UnitPoint(
                        x: 0.5 + 0.5 * cos(angle),
                        y: 0.5 + 0.5 * sin(angle)
                    ),
                    endPoint: UnitPoint(
                        x: 0.5 - 0.5 * cos(angle),
                        y: 0.5 - 0.5 * sin(angle)
                    )
                )

                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(gradient, lineWidth: 2)
                    .opacity(breathe)
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(color, lineWidth: 2)
                    .opacity(breathe)
            }
        }
    }

    // 淡雅彩虹：低饱和度柔光色系
    private static let elegantRainbow: [Color] = [
        Color(hue: 0.95, saturation: 0.50, brightness: 1.0),   // 淡玫红
        Color(hue: 0.06, saturation: 0.50, brightness: 1.0),   // 淡珊瑚
        Color(hue: 0.14, saturation: 0.45, brightness: 1.0),   // 淡暖金
        Color(hue: 0.42, saturation: 0.45, brightness: 0.95),  // 淡薄荷
        Color(hue: 0.55, saturation: 0.50, brightness: 1.0),   // 淡天青
        Color(hue: 0.70, saturation: 0.45, brightness: 1.0),   // 淡薰紫
        Color(hue: 0.83, saturation: 0.50, brightness: 1.0),   // 淡洋红
        Color(hue: 0.95, saturation: 0.50, brightness: 1.0),   // 回到淡玫红
    ]
}
