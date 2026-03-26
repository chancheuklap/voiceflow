import AppKit
import SwiftUI

/// 浮动状态胶囊 — Spokenly 风格磨砂玻璃弹窗
/// 屏幕底部居中，不抢焦点，跨 Space，自动调整高度
class FloatingPill {
    private var panel: NSPanel?
    private var hostingView: NSHostingView<AnyView>?
    private var glowHostingView: NSHostingView<AnyView>?
    private var container: NSView?
    private var viewModel = PillViewModel()
    private var hideTimer: Timer?

    private let panelWidth: CGFloat = 280
    private let glowPadding: CGFloat = 12 // 光晕向外扩展的距离

    init() {
        setupPanel()
    }

    // MARK: - 公开接口

    func show(state: PillState) {
        viewModel.state = state

        if let frontApp = NSWorkspace.shared.frontmostApplication {
            viewModel.appName = frontApp.localizedName ?? ""
            viewModel.appIcon = frontApp.icon
        }

        if panel?.isVisible != true {
            panel?.orderFrontRegardless()
        }
        updatePanelSize()
        updateGlow(for: state)
    }

    func updateText(_ text: String) {
        viewModel.currentText = text
        updatePanelSize()
    }

    func updateAudioLevel(_ level: CGFloat) {
        viewModel.audioLevel = level
    }

    func showDone(_ text: String, autoDismiss: TimeInterval = 1.5) {
        viewModel.state = .done(text)
        updatePanelSize()
        updateGlow(for: .done(text))
        scheduleHide(after: autoDismiss)
    }

    func showError(_ message: String, autoDismiss: TimeInterval = 3.0) {
        viewModel.state = .error(message)
        updatePanelSize()
        updateGlow(for: .error(message))
        scheduleHide(after: autoDismiss)
    }

    func hide() {
        hideTimer?.invalidate()
        hideTimer = nil
        panel?.orderOut(nil)
        viewModel.state = .idle
        viewModel.currentText = ""
        viewModel.audioLevel = 0
    }

    // MARK: - Panel 创建

    private func setupPanel() {
        let gp = glowPadding
        let totalWidth = panelWidth + gp * 2
        let contentHeight: CGFloat = 80
        let totalHeight = contentHeight + gp * 2

        // SwiftUI 内容（不含光晕，光晕单独一层）
        let contentView = PillContentView(viewModel: viewModel)
            .frame(width: panelWidth)

        let hosting = NSHostingView(rootView: AnyView(contentView))
        hosting.frame = NSRect(x: gp, y: gp, width: panelWidth, height: contentHeight)

        // 光晕层（SwiftUI GlowBorderView，不受 masksToBounds 裁剪）
        let glowView = GlowContainerView(viewModel: viewModel)
            .frame(width: panelWidth, height: contentHeight)
        let glowHosting = NSHostingView(rootView: AnyView(glowView))
        glowHosting.frame = NSRect(x: gp, y: gp, width: panelWidth, height: contentHeight)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: totalWidth, height: totalHeight),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )

        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false // 阴影由光晕代替
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = false

        // 外层容器（不裁剪，让光晕溢出）
        let outer = NSView(frame: NSRect(x: 0, y: 0, width: totalWidth, height: totalHeight))
        outer.wantsLayer = true
        outer.autoresizesSubviews = false

        // 光晕层（在内容下面，不裁剪，向外扩散）
        glowHosting.wantsLayer = true
        glowHosting.layer?.backgroundColor = .clear
        outer.addSubview(glowHosting)

        // 内容容器（裁剪圆角，包含毛玻璃 + 文字）
        let container = NSView(frame: NSRect(x: gp, y: gp, width: panelWidth, height: contentHeight))
        container.wantsLayer = true
        container.layer?.cornerRadius = 16
        container.layer?.masksToBounds = true

        let blur = NSVisualEffectView(frame: container.bounds)
        blur.autoresizingMask = [.width, .height]
        blur.blendingMode = .behindWindow
        blur.material = .fullScreenUI
        blur.state = .active
        blur.isEmphasized = true
        container.addSubview(blur)

        hosting.frame = NSRect(x: 0, y: 0, width: panelWidth, height: contentHeight)
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)

        outer.addSubview(container)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.forceTransparent(hosting)
            self.forceTransparent(glowHosting)
        }

        panel.contentView = outer
        self.panel = panel
        self.hostingView = hosting
        self.glowHostingView = glowHosting
        self.container = container
    }

    /// 递归清除 NSHostingView 及其子视图的不透明背景
    private func forceTransparent(_ view: NSView) {
        view.wantsLayer = true
        view.layer?.backgroundColor = .clear
        view.layer?.isOpaque = false
        if let sv = view as? NSScrollView {
            sv.drawsBackground = false
        }
        for subview in view.subviews {
            forceTransparent(subview)
        }
    }

    private func updateGlow(for state: PillState) {
        // 光晕效果现在由 SwiftUI 的 GlowBorderView 处理
        // 通过 viewModel.state 自动驱动
    }

    private func updatePanelSize() {
        guard let hosting = hostingView, let panel = panel, let screen = NSScreen.main else { return }

        let gp = glowPadding
        let fittingSize = hosting.fittingSize
        let contentHeight = max(70, fittingSize.height)
        let totalWidth = panelWidth + gp * 2
        let totalHeight = contentHeight + gp * 2

        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - totalWidth / 2
        let y = screenFrame.origin.y + 60

        panel.setFrame(NSRect(x: x, y: y, width: totalWidth, height: totalHeight), display: true)

        // 光晕层和内容层都需要更新位置
        glowHostingView?.frame = NSRect(x: gp, y: gp, width: panelWidth, height: contentHeight)
        container?.frame = NSRect(x: gp, y: gp, width: panelWidth, height: contentHeight)
        hosting.frame = NSRect(x: 0, y: 0, width: panelWidth, height: contentHeight)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in
            if let hosting = self?.hostingView { self?.forceTransparent(hosting) }
            if let glow = self?.glowHostingView { self?.forceTransparent(glow) }
        }
    }

    private func scheduleHide(after seconds: TimeInterval) {
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            self?.hide()
        }
    }
}

// MARK: - SwiftUI ViewModel

private class PillViewModel: ObservableObject {
    @Published var state: PillState = .idle
    @Published var currentText: String = ""
    @Published var audioLevel: CGFloat = 0
    @Published var appName: String = ""
    @Published var appIcon: NSImage?
}

// MARK: - SwiftUI 内容视图

private struct PillContentView: View {
    @ObservedObject var viewModel: PillViewModel

    var body: some View {
        VStack(spacing: 6) {
            topRow
            bottomRow
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // 背景透明（毛玻璃由底层 AppKit NSVisualEffectView 提供）
    }

    @ViewBuilder
    private var topRow: some View {
        switch viewModel.state {
        case .recording:
            if viewModel.currentText.isEmpty {
                appInfoRow
            } else {
                Text(viewModel.currentText)
                    .font(.system(size: 13))
                    .foregroundColor(.primary.opacity(0.8))
                    .lineLimit(5)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

        case .processing:
            HStack {
                Text("识别中")
                    .font(.system(size: 13))
                    .foregroundColor(.primary.opacity(0.6))
                Spacer()
                ProgressView()
                    .controlSize(.small)
            }

        case .polishing:
            HStack {
                Text("润色中")
                    .font(.system(size: 13))
                    .foregroundColor(.primary.opacity(0.6))
                Spacer()
                ProgressView()
                    .controlSize(.small)
            }

        case .done(let text):
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 14))
                Text(text)
                    .font(.system(size: 13))
                    .foregroundColor(.primary.opacity(0.8))
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case .error(let msg):
            HStack(spacing: 6) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                    .font(.system(size: 14))
                Text(msg)
                    .font(.system(size: 13))
                    .foregroundColor(.primary.opacity(0.8))
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case .idle:
            EmptyView()
        }
    }

    @ViewBuilder
    private var bottomRow: some View {
        switch viewModel.state {
        case .recording:
            WaveformView(audioLevel: viewModel.audioLevel)
                .frame(height: 20)
        case .processing, .polishing:
            WaveformView(audioLevel: 0.08)
                .frame(height: 20)
        default:
            EmptyView()
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
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary.opacity(0.8))
                    .lineLimit(1)
            }
            Spacer()
            Text("VoiceFlow")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.primary.opacity(0.4))
        }
    }
}

// MARK: - 独立光晕容器（不被 masksToBounds 裁剪，光晕向外扩散）

private struct GlowContainerView: View {
    @ObservedObject var viewModel: PillViewModel

    var body: some View {
        ZStack {
            switch viewModel.state {
            case .recording:
                GlowBorderView(color: .green, speed: 2.0)
            case .processing, .polishing:
                GlowBorderView(color: .blue, speed: 1.5)
            case .done:
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.green.opacity(0.3), lineWidth: 1.5)
            case .error:
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.red.opacity(0.4), lineWidth: 1.5)
            case .idle:
                EmptyView()
            }
        }
    }
}
