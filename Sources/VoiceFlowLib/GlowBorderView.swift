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

    // 优雅彩虹：Sonoma 风格色系，柔和过渡
    private static let elegantRainbow: [Color] = [
        Color(hue: 0.95, saturation: 0.85, brightness: 1.0),   // 玫红
        Color(hue: 0.05, saturation: 0.80, brightness: 1.0),   // 珊瑚橙
        Color(hue: 0.13, saturation: 0.75, brightness: 1.0),   // 暖金
        Color(hue: 0.42, saturation: 0.70, brightness: 0.95),  // 薄荷绿
        Color(hue: 0.55, saturation: 0.80, brightness: 1.0),   // 天青蓝
        Color(hue: 0.68, saturation: 0.75, brightness: 1.0),   // 薰衣紫
        Color(hue: 0.82, saturation: 0.80, brightness: 1.0),   // 洋红
        Color(hue: 0.95, saturation: 0.85, brightness: 1.0),   // 回到玫红
    ]
}
