import SwiftUI

/// 跑马灯边框 — 弧线沿边框匀速移动
/// isRainbow=true 时弧线沿路径显示彩虹渐变，false 时单色
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

    private let segmentCount = 8

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let progress = fmod(time / speed, 1.0)
            let arcLength = 0.3
            let head = progress
            let tail = progress - arcLength

            ZStack {
                if isRainbow {
                    // 底层微弱彩虹全边框
                    rainbowBaseBorder(time: time)

                    // 沿弧线路径的彩虹分段
                    ForEach(0..<segmentCount, id: \.self) { i in
                        let t0 = Double(i) / Double(segmentCount)
                        let t1 = Double(i + 1) / Double(segmentCount)
                        let segStart = tail + arcLength * t0
                        let segEnd = tail + arcLength * t1
                        // 色相沿弧线分布 + 随时间缓慢漂移
                        let hue = fmod(t0 + time * 0.12, 1.0)
                        // 尾暗头亮（彗星效果）
                        let brightness = 0.35 + 0.65 * t0
                        let segColor = Color(hue: hue, saturation: 0.85, brightness: 1.0)

                        arc(from: segStart, to: segEnd,
                            lineWidth: 1.5, opacity: brightness, fill: segColor)
                    }
                } else {
                    // 底层微弱单色全边框
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(color.opacity(0.15), lineWidth: 1)

                    // 单色弧线
                    arc(from: tail, to: head, lineWidth: 1.5, opacity: 0.7, fill: color)
                }
            }
        }
    }

    /// 彩虹底边框：6 段不同色相拼成完整边框
    private func rainbowBaseBorder(time: Double) -> some View {
        ZStack {
            ForEach(0..<6, id: \.self) { i in
                let start = Double(i) / 6.0
                let end = Double(i + 1) / 6.0
                let hue = fmod(Double(i) / 6.0 + time * 0.05, 1.0)

                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .trim(from: CGFloat(start), to: CGFloat(end))
                    .stroke(
                        Color(hue: hue, saturation: 0.7, brightness: 1.0).opacity(0.2),
                        style: StrokeStyle(lineWidth: 1, lineCap: .butt)
                    )
            }
        }
    }

    @ViewBuilder
    private func arc<S: ShapeStyle>(from start: Double, to end: Double,
                                     lineWidth: CGFloat, opacity: Double,
                                     fill: S) -> some View {
        if start >= 0 {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .trim(from: CGFloat(start), to: CGFloat(end))
                .stroke(fill, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .opacity(opacity)
        } else if end <= 0 {
            // 整段在跨界区
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .trim(from: CGFloat(1.0 + start), to: CGFloat(1.0 + end))
                .stroke(fill, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .opacity(opacity * 0.85)
        } else {
            // 跨越 0 点：拆成两段
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .trim(from: 0, to: CGFloat(end))
                .stroke(fill, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .opacity(opacity)
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .trim(from: CGFloat(1.0 + start), to: 1.0)
                .stroke(fill, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .opacity(opacity * 0.85)
        }
    }
}
