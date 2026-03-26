import SwiftUI

/// 呼吸边框 — 柔和脉动
/// isRainbow=true 时每次呼吸切换一种颜色，false 时单色呼吸
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
            let phase = time * 2.0
            let breathe = 0.35 + 0.6 * ((sin(phase) + 1.0) / 2.0)

            if isRainbow {
                // 每次呼吸到最暗时切换颜色（过渡无感）
                let cycleIndex = Int(floor(phase / (2.0 * .pi)))
                let colorIndex = abs(cycleIndex) % Self.elegantColors.count
                let currentColor = Self.elegantColors[colorIndex]

                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(currentColor, lineWidth: 2)
                    .opacity(breathe)
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(color, lineWidth: 2)
                    .opacity(breathe)
            }
        }
    }

    // 高雅色轮：莫兰迪色调 + 珠宝色点缀
    private static let elegantColors: [Color] = [
        Color(hue: 0.58, saturation: 0.35, brightness: 0.92),  // 雾蓝
        Color(hue: 0.85, saturation: 0.30, brightness: 0.95),  // 藕粉
        Color(hue: 0.45, saturation: 0.30, brightness: 0.88),  // 灰豆绿
        Color(hue: 0.72, saturation: 0.35, brightness: 0.90),  // 烟紫
        Color(hue: 0.10, saturation: 0.30, brightness: 0.95),  // 裸杏
        Color(hue: 0.52, saturation: 0.25, brightness: 0.90),  // 青瓷
        Color(hue: 0.92, saturation: 0.30, brightness: 0.93),  // 暮玫
    ]
}
