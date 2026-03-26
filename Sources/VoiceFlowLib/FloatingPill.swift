import AppKit
import SwiftUI

/// 浮动状态胶囊 — Spokenly 风格磨砂玻璃弹窗
/// 屏幕底部居中，不抢焦点，跨 Space，自动调整高度
class FloatingPill {
    private var panel: NSPanel?
    private var hostingView: NSHostingView<AnyView>?
    private var container: NSView?
    private var viewModel = PillViewModel()
    private var hideTimer: Timer?

    private let panelWidth: CGFloat = 280

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
        // SwiftUI 内容用全屏填充（不带圆角），圆角由 container 层裁剪
        let contentView = PillContentView(viewModel: viewModel)
            .frame(width: panelWidth)

        let hosting = NSHostingView(rootView: AnyView(contentView))
        hosting.frame = NSRect(x: 0, y: 0, width: panelWidth, height: 80)

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

        // 用一个 container 做圆角裁剪，遮住 NSHostingView 的方角白边
        let container = NSView(frame: NSRect(x: 0, y: 0, width: panelWidth, height: 80))
        container.wantsLayer = true
        container.layer?.cornerRadius = 16
        container.layer?.masksToBounds = true
        container.autoresizesSubviews = true

        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)

        panel.contentView = container
        self.panel = panel
        self.hostingView = hosting
        self.container = container
    }

    private func updateGlow(for state: PillState) {
        // 光晕效果现在由 SwiftUI 的 GlowBorderView 处理
        // 通过 viewModel.state 自动驱动
    }

    private func updatePanelSize() {
        guard let hosting = hostingView, let panel = panel, let screen = NSScreen.main else { return }

        // 让 SwiftUI 计算内容需要的高度
        let fittingSize = hosting.fittingSize
        let height = max(70, fittingSize.height)

        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - panelWidth / 2
        // 距离屏幕底部（Dock 上方）60pt
        let y = screenFrame.origin.y + 60

        panel.setFrame(NSRect(x: x, y: y, width: panelWidth, height: height), display: true)
        hosting.frame = NSRect(x: 0, y: 0, width: panelWidth, height: height)
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
        // 毛玻璃背景（全屏填充，圆角由 NSView container 裁剪）
        .background(.ultraThinMaterial)
        // 跑马灯光晕边框
        .overlay(glowOverlay)
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

    @ViewBuilder
    private var glowOverlay: some View {
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
