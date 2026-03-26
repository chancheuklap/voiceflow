import SwiftUI

/// 呼吸边框 — 柔光脉动，双层模拟光晕感
/// isRainbow=true 时每次呼吸在最暗点切换颜色，false 时单色呼吸
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
            breathingBorder(time: timeline.date.timeIntervalSinceReferenceDate)
        }
    }

    private func breathingBorder(time: Double) -> some View {
        let phase = time * 2.0
        let breathe = 0.1 + 0.9 * ((sin(phase) + 1.0) / 2.0)

        let currentColor: Color
        if isRainbow {
            let cyclePhase = phase + .pi / 2
            let cycleIndex = Int(floor(cyclePhase / (2.0 * .pi)))
            let colorIndex = abs(cycleIndex) % Self.smoothColors.count
            currentColor = Self.smoothColors[colorIndex]
        } else {
            currentColor = color
        }

        return ZStack {
            // 外层柔光
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(currentColor, lineWidth: 5)
                .opacity(breathe * 0.35)

            // 内层核心
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(currentColor, lineWidth: 1.5)
                .opacity(breathe)
        }
    }

    // 暖绿色系：偏黄绿的春天色调
    private static let smoothColors: [Color] = [
        Color(hue: 0.22, saturation: 0.35, brightness: 0.95),  // 嫩芽
        Color(hue: 0.25, saturation: 0.38, brightness: 0.93),  // 春绿
        Color(hue: 0.28, saturation: 0.35, brightness: 0.95),  // 新叶
        Color(hue: 0.31, saturation: 0.38, brightness: 0.93),  // 草绿
        Color(hue: 0.28, saturation: 0.35, brightness: 0.95),  // 新叶
        Color(hue: 0.25, saturation: 0.38, brightness: 0.93),  // 春绿
        Color(hue: 0.22, saturation: 0.35, brightness: 0.95),  // 嫩芽
    ]
}
