import AppKit
import SwiftUI

/// 浮动状态胶囊 — 水晶毛玻璃 + 跑马灯边框 + 弹簧动画
class FloatingPill {
    private var panel: NSPanel?
    private var hostingView: NSHostingView<AnyView>?
    private var viewModel = PillViewModel()
    private var hideTimer: Timer?
    private var isHiding = false

    private let panelWidth: CGFloat = 300
    private let cornerRadius: CGFloat = 22

    init() {
        setupPanel()
    }

    // MARK: - 公开接口

    func show(state: PillState) {
        hideTimer?.invalidate()
        hideTimer = nil

        // 取消正在进行的隐藏动画
        if isHiding {
            panel?.alphaValue = 1.0
            isHiding = false
        }

        // 弹簧动画驱动状态切换
        withAnimation(.spring(response: 0.4, dampingFraction: 0.72)) {
            viewModel.state = state
        }

        if let frontApp = NSWorkspace.shared.frontmostApplication {
            viewModel.appName = frontApp.localizedName ?? ""
            viewModel.appIcon = frontApp.icon
        }

        let wasHidden = panel?.isVisible != true
        if wasHidden {
            panel?.alphaValue = 0
            panel?.orderFrontRegardless()
        }

        updatePanelSize(animated: !wasHidden)

        // 淡入出现
        if wasHidden {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.3
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                self.panel?.animator().alphaValue = 1.0
            }
        }
    }

    func updateText(_ text: String) {
        // SwiftUI 弹簧独自驱动布局过渡，面板即时缩放不打架
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            viewModel.currentText = text
        }
        updatePanelSize(animated: false)
    }

    func updateAudioLevel(_ level: CGFloat) {
        viewModel.audioLevel = level
    }

    func showDone(_ text: String, autoDismiss: TimeInterval = 1.5) {
        hideTimer?.invalidate()
        hideTimer = nil
        if isHiding {
            panel?.alphaValue = 1.0
            isHiding = false
        }

        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            viewModel.state = .done(text)
        }

        if panel?.isVisible != true {
            panel?.alphaValue = 0
            panel?.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.3
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                self.panel?.animator().alphaValue = 1.0
            }
        }
        updatePanelSize(animated: true)
        scheduleHide(after: autoDismiss)
    }

    func showError(_ message: String, autoDismiss: TimeInterval = 3.0) {
        hideTimer?.invalidate()
        hideTimer = nil
        if isHiding {
            panel?.alphaValue = 1.0
            isHiding = false
        }

        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            viewModel.state = .error(message)
        }

        if panel?.isVisible != true {
            panel?.alphaValue = 0
            panel?.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.3
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                self.panel?.animator().alphaValue = 1.0
            }
        }
        updatePanelSize(animated: true)
        scheduleHide(after: autoDismiss)
    }

    func hide() {
        hideTimer?.invalidate()
        hideTimer = nil

        guard !isHiding else { return }
        isHiding = true

        // 淡出消失
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.panel?.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self = self, self.isHiding else { return }
            self.panel?.orderOut(nil)
            self.panel?.alphaValue = 1.0
            self.viewModel.state = .idle
            self.viewModel.currentText = ""
            self.viewModel.audioLevel = 0
            self.isHiding = false
        })
    }

    // MARK: - Panel 创建

    private func setupPanel() {
        let contentView = PillContentView(viewModel: viewModel, cornerRadius: cornerRadius)
            .frame(width: panelWidth)

        let hosting = NSHostingView(rootView: AnyView(contentView))

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: 80),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )

        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = false

        // 容器：连续曲线圆角 + 深色外观
        let container = NSView(frame: NSRect(x: 0, y: 0, width: panelWidth, height: 80))
        container.wantsLayer = true
        container.layer?.cornerRadius = cornerRadius
        container.layer?.cornerCurve = .continuous
        container.layer?.masksToBounds = true
        container.appearance = NSAppearance(named: .vibrantDark)

        // 毛玻璃
        let blur = NSVisualEffectView(frame: container.bounds)
        blur.autoresizingMask = [.width, .height]
        blur.blendingMode = .behindWindow
        blur.material = .hudWindow
        blur.state = .active
        blur.alphaValue = 0.88
        container.addSubview(blur)

        // SwiftUI 内容层
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)

        panel.contentView = container
        self.panel = panel
        self.hostingView = hosting

        clearHostingBackground()
    }

    private func clearHostingBackground() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let hosting = self?.hostingView else { return }
            self?.forceTransparent(hosting)
        }
    }

    private func forceTransparent(_ view: NSView) {
        view.wantsLayer = true
        view.layer?.backgroundColor = .clear
        view.layer?.isOpaque = false
        for subview in view.subviews {
            forceTransparent(subview)
        }
    }

    private func updatePanelSize(animated: Bool = false) {
        guard let hosting = hostingView, let panel = panel, let screen = NSScreen.main else { return }

        let fittingSize = hosting.fittingSize
        let height = max(70, fittingSize.height)

        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - panelWidth / 2
        let y = screenFrame.origin.y + 60

        let newFrame = NSRect(x: x, y: y, width: panelWidth, height: height)

        if animated && panel.isVisible {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.3
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(newFrame, display: true)
            }
        } else {
            panel.setFrame(newFrame, display: true)
        }

        clearHostingBackground()
    }

    private func scheduleHide(after seconds: TimeInterval) {
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            self?.hide()
        }
    }
}

// MARK: - ViewModel

private class PillViewModel: ObservableObject {
    @Published var state: PillState = .idle
    @Published var currentText: String = ""
    @Published var audioLevel: CGFloat = 0
    @Published var appName: String = ""
    @Published var appIcon: NSImage?
}

// MARK: - SwiftUI 内容

private struct PillContentView: View {
    @ObservedObject var viewModel: PillViewModel
    let cornerRadius: CGFloat

    var body: some View {
        ZStack {
            // NSHostingView 透明背景修复
            TransparentHostingFix()
                .frame(width: 0, height: 0)

            VStack(spacing: 6) {
                topRow
                bottomRow
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(glassHighlight)
        .overlay(glowOverlay)
    }

    /// 玻璃高光内边框 — 顶部亮、底部暗的渐变细线，模拟水晶棱角折射
    private var glassHighlight: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.5),
                        Color.white.opacity(0.2),
                        Color.white.opacity(0.08)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 0.5
            )
    }

    @ViewBuilder
    private var glowOverlay: some View {
        switch viewModel.state {
        case .recording:
            GlowBorderView(color: .green, cornerRadius: cornerRadius, speed: 2.0, isRainbow: true)
        case .processing, .polishing:
            GlowBorderView(color: .blue, cornerRadius: cornerRadius, speed: 1.5)
        case .done:
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.green.opacity(0.4), lineWidth: 1)
        case .error:
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.red.opacity(0.4), lineWidth: 1)
        case .idle:
            EmptyView()
        }
    }

    @ViewBuilder
    private var topRow: some View {
        switch viewModel.state {
        case .recording:
            if viewModel.currentText.isEmpty {
                appInfoRow
                    .transition(.opacity)
            } else {
                Text(viewModel.currentText)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundColor(.primary.opacity(0.85))
                    .lineLimit(5)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            }

        case .processing:
            HStack {
                Text("识别中")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.primary.opacity(0.6))
                Spacer()
                PulsingDotsView()
            }
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 0.95)),
                removal: .opacity
            ))

        case .polishing:
            HStack {
                Text("润色中")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.primary.opacity(0.6))
                Spacer()
                PulsingDotsView()
            }
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 0.95)),
                removal: .opacity
            ))

        case .done(let text):
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 14, design: .rounded))
                Text(text)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundColor(.primary.opacity(0.85))
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 0.95)),
                removal: .opacity
            ))

        case .error(let msg):
            HStack(spacing: 6) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                    .font(.system(size: 14, design: .rounded))
                Text(msg)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundColor(.primary.opacity(0.85))
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 0.95)),
                removal: .opacity
            ))

        case .idle:
            EmptyView()
        }
    }

    @ViewBuilder
    private var bottomRow: some View {
        // 统一 WaveformView 实例，避免 recording→processing 切换时重建视图
        let showWaveform = viewModel.state == .recording
            || viewModel.state == .processing
            || viewModel.state == .polishing

        if showWaveform {
            let level: CGFloat = viewModel.state == .recording ? viewModel.audioLevel : 0.08
            WaveformView(audioLevel: level)
                .frame(height: 20)
                .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .center)))
        }
    }

    private var appInfoRow: some View {
        HStack {
            HStack(spacing: 6) {
                if let icon = viewModel.appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 20, height: 20)
                        .cornerRadius(4)
                }
                Text(viewModel.appName)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.primary.opacity(0.85))
                    .lineLimit(1)
            }
            Spacer()
            Text("VoiceFlow")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(.primary.opacity(0.4))
        }
    }
}

// MARK: - 三点脉冲加载指示器（类似 iMessage 输入动画）

private struct PulsingDotsView: View {
    @State private var activeIndex = 0
    private let dotCount = 3
    private let dotSize: CGFloat = 4
    private let timer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<dotCount, id: \.self) { index in
                Circle()
                    .fill(Color.primary.opacity(index == activeIndex ? 0.8 : 0.3))
                    .frame(width: dotSize, height: dotSize)
                    .scaleEffect(index == activeIndex ? 1.3 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: activeIndex)
            }
        }
        .onReceive(timer) { _ in
            activeIndex = (activeIndex + 1) % dotCount
        }
    }
}
