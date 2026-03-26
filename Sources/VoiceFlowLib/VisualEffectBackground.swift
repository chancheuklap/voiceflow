import AppKit
import SwiftUI

/// 从 SwiftUI 内部清除 NSHostingView 的不透明背景
/// 原理：在 SwiftUI 视图树中插入一个 NSView，通过它向上遍历父视图，
/// 清除所有层的 backgroundColor，让底层的 NSVisualEffectView 透出来。
struct TransparentHostingFix: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = TransparentFixView()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // 每次 SwiftUI 更新时重新清除（因为 SwiftUI 可能重建子视图）
        DispatchQueue.main.async {
            (nsView as? TransparentFixView)?.clearParentBackgrounds()
        }
    }
}

private class TransparentFixView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // 加入窗口后清除所有父层背景
        DispatchQueue.main.async { [weak self] in
            self?.clearParentBackgrounds()
        }
    }

    override func layout() {
        super.layout()
        clearParentBackgrounds()
    }

    func clearParentBackgrounds() {
        var current: NSView? = self.superview
        while let view = current {
            view.wantsLayer = true
            view.layer?.backgroundColor = .clear
            view.layer?.isOpaque = false
            current = view.superview
        }
    }
}
