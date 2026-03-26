import AppKit
import SwiftUI

/// 浮动状态胶囊 — 磨砂玻璃 + 跑马灯边框
class FloatingPill {
    private var panel: NSPanel?
    private var hostingView: NSHostingView<AnyView>?
    private var viewModel = PillViewModel()
    private var hideTimer: Timer?
    private var isHiding = false

    private let panelWidth: CGFloat = 280

    init() {
        setupPanel()
    }

    // MARK: - 公开接口

    func show(state: PillState) {
        hideTimer?.invalidate()
        hideTimer = nil
        cancelHideIfNeeded()

        viewModel.state = state

        if let frontApp = NSWorkspace.shared.frontmostApplication {
            viewModel.appName = frontApp.localizedName ?? ""
            viewModel.appIcon = frontApp.icon
        }

        if panel?.isVisible != true {
            panel?.orderFrontRegardless()
        }
        updatePanelSize()
    }

    func updateText(_ text: String) {
        viewModel.currentText = text
        updatePanelSize()
    }

    func updateAudioLevel(_ level: CGFloat) {
        viewModel.audioLevel = level
    }

    func showDone(_ text: String, autoDismiss: TimeInterval = 1.5) {
        hideTimer?.invalidate()
        hideTimer = nil
        cancelHideIfNeeded()
        viewModel.state = .done(text)
        if panel?.isVisible != true {
            panel?.orderFrontRegardless()
        }
        updatePanelSize()
        scheduleHide(after: autoDismiss)
    }

    func showError(_ message: String, autoDismiss: TimeInterval = 3.0) {
        hideTimer?.invalidate()
        hideTimer = nil
        cancelHideIfNeeded()
        viewModel.state = .error(message)
        if panel?.isVisible != true {
            panel?.orderFrontRegardless()
        }
        updatePanelSize()
        scheduleHide(after: autoDismiss)
    }

    func hide() {
        hideTimer?.invalidate()
        hideTimer = nil
        panel?.orderOut(nil)
        viewModel.state = .idle
        viewModel.currentText = ""
        viewModel.audioLevel = 0
        isHiding = false
    }

    // MARK: - 内部

    private func cancelHideIfNeeded() {
        // 取消定时器驱动的延迟隐藏
        hideTimer?.invalidate()
        hideTimer = nil
    }

    // MARK: - Panel 创建（完全复用 commit 2087078 的确认可用架构）

    private func setupPanel() {
        let contentView = PillContentView(viewModel: viewModel)
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

        // 容器：圆角裁剪
        let container = NSView(frame: NSRect(x: 0, y: 0, width: panelWidth, height: 80))
        container.wantsLayer = true
        container.layer?.cornerRadius = 16
        container.layer?.masksToBounds = true

        // 毛玻璃（AppKit 原生，这个组合确认可用）
        let blur = NSVisualEffectView(frame: container.bounds)
        blur.autoresizingMask = [.width, .height]
        blur.blendingMode = .behindWindow
        blur.material = .titlebar
        blur.state = .active
        blur.appearance = NSAppearance(named: .vibrantLight)
        container.addSubview(blur)

        // SwiftUI 内容
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)

        panel.contentView = container
        self.panel = panel
        self.hostingView = hosting

        // 清除 NSHostingView 不透明背景
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

    private func updatePanelSize() {
        guard let hosting = hostingView, let panel = panel, let screen = NSScreen.main else { return }

        let fittingSize = hosting.fittingSize
        let height = max(70, fittingSize.height)

        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - panelWidth / 2
        let y = screenFrame.origin.y + 60

        panel.setFrame(NSRect(x: x, y: y, width: panelWidth, height: height), display: true)
        panel.contentView?.frame = NSRect(x: 0, y: 0, width: panelWidth, height: height)

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

    var body: some View {
        ZStack {
            // 清除 NSHostingView 不透明背景
            TransparentHostingFix()
                .frame(width: 0, height: 0)

            VStack(spacing: 6) {
                topRow
                bottomRow
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(glowOverlay)
    }

    @ViewBuilder
    private var glowOverlay: some View {
        switch viewModel.state {
        case .recording:
            GlowBorderView(color: .green, speed: 2.0)
        case .processing, .polishing:
            GlowBorderView(color: .blue, speed: 1.5)
        case .done:
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.green.opacity(0.4), lineWidth: 1)
        case .error:
            RoundedRectangle(cornerRadius: 16)
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
