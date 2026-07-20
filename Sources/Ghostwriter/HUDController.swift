import AppKit
import SwiftUI

@MainActor
final class HUDController {
    private var panel: NSPanel?
    private let model = HUDModel()

    func showRecording() {
        model.phase = .recording
        model.levels = Array(repeating: 0.05, count: HUDModel.barCount)
        presentPanel()
    }
    func updateLevel(_ level: Float) {
        guard model.phase == .recording else { return }
        model.levels.removeFirst()
        model.levels.append(max(0.05, min(1, level)))
    }
    func showProcessing() { model.phase = .processing }
    func flashResult(fallback: Bool) {
        model.phase = fallback ? .doneRaw : .done
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in self?.hide() }
    }
    func hide() { panel?.orderOut(nil); panel = nil }

    private func presentPanel() {
        if panel != nil { return }
        let host = NSHostingView(rootView: HUDView(model: model))
        host.frame = NSRect(x: 0, y: 0, width: 220, height: 44)
        let p = NSPanel(contentRect: host.frame,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.level = .statusBar
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentView = host
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            p.setFrameOrigin(NSPoint(x: f.midX - 110, y: f.minY + 80))
        }
        p.orderFrontRegardless()
        panel = p
    }
}

@MainActor
final class HUDModel: ObservableObject {
    static let barCount = 24
    enum Phase { case recording, processing, done, doneRaw }
    @Published var phase: Phase = .recording
    @Published var levels: [Float] = Array(repeating: 0.05, count: barCount)
}

struct HUDView: View {
    @ObservedObject var model: HUDModel
    var body: some View {
        HStack(spacing: 8) {
            Text("👻").font(.system(size: 18))
            switch model.phase {
            case .recording:
                HStack(spacing: 2) {
                    ForEach(Array(model.levels.enumerated()), id: \.offset) { _, level in
                        Capsule().fill(.white.opacity(0.9))
                            .frame(width: 3, height: CGFloat(6 + level * 22))
                    }
                }
                .animation(.linear(duration: 0.05), value: model.levels)
            case .processing:
                ProgressView().controlSize(.small).tint(.white)
                Text("Transcribing…").font(.caption).foregroundStyle(.white.opacity(0.85))
            case .done:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .doneRaw:
                Image(systemName: "checkmark.circle").foregroundStyle(.yellow)
                Text("verbatim").font(.caption2).foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .frame(width: 220, height: 44)
        .background(.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 14))
    }
}
