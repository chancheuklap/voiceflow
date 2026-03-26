import SwiftUI

/// Streaming 文字显示 — final 文字白色，interim 文字半透明
struct StreamingTextView: View {
    let text: String
    let state: PillState

    var body: some View {
        Group {
            switch state {
            case .recording:
                if text.isEmpty {
                    Text("正在聆听...")
                        .foregroundColor(.white.opacity(0.5))
                        .font(.system(size: 13))
                } else {
                    Text(text)
                        .foregroundColor(.white.opacity(0.7))
                        .font(.system(size: 13))
                }

            case .processing:
                HStack(spacing: 4) {
                    Text("识别中")
                        .foregroundColor(.white.opacity(0.6))
                    ProgressView()
                        .controlSize(.small)
                        .colorScheme(.dark)
                }
                .font(.system(size: 13))

            case .polishing:
                HStack(spacing: 4) {
                    Text("润色中")
                        .foregroundColor(.white.opacity(0.6))
                    ProgressView()
                        .controlSize(.small)
                        .colorScheme(.dark)
                }
                .font(.system(size: 13))

            case .done(let finalText):
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 14))
                    Text(finalText.prefix(50) + (finalText.count > 50 ? "..." : ""))
                        .foregroundColor(.white)
                        .font(.system(size: 13))
                }

            case .error(let message):
                HStack(spacing: 6) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                        .font(.system(size: 14))
                    Text(message)
                        .foregroundColor(.white.opacity(0.8))
                        .font(.system(size: 13))
                }

            case .idle:
                EmptyView()
            }
        }
        .lineLimit(2)
        .multilineTextAlignment(.center)
    }
}

/// 浮动胶囊的状态
enum PillState: Equatable {
    case idle
    case recording
    case processing
    case polishing
    case done(String)
    case error(String)
}
