import AppKit
import SwiftUI

@MainActor
final class HUDController {
    private static let panelSize = NSSize(width: 148, height: 32)
    private var panel: NSPanel?
    private let model = HUDModel()
    private var smoothedLevel: Float = 0

    func showRecording() {
        model.phase = .recording
        smoothedLevel = 0
        model.levels = Array(repeating: 0, count: HUDModel.barCount)
        presentPanel()
    }
    func updateLevel(_ level: Float) {
        guard model.phase == .recording else { return }
        let target = pow(max(0, min(1, level)), 0.72)
        let response: Float = target > smoothedLevel ? 0.58 : 0.2
        smoothedLevel += (target - smoothedLevel) * response
        model.levels.removeFirst()
        model.levels.append(smoothedLevel)
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
        host.frame = NSRect(origin: .zero, size: Self.panelSize)
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
            p.setFrameOrigin(NSPoint(x: f.midX - Self.panelSize.width / 2, y: f.minY + 64))
        }
        p.orderFrontRegardless()
        panel = p
    }
}

@MainActor
final class HUDModel: ObservableObject {
    static let barCount = 15
    enum Phase { case recording, processing, done, doneRaw }
    @Published var phase: Phase = .recording
    @Published var levels: [Float] = Array(repeating: 0, count: barCount)
}

struct HUDView: View {
    @ObservedObject var model: HUDModel
    var body: some View {
        HStack(spacing: 6) {
            switch model.phase {
            case .recording:
                HStack(spacing: 2.5) {
                    ForEach(Array(model.levels.enumerated()), id: \.offset) { _, level in
                        Capsule().fill(.white.opacity(0.48 + Double(level) * 0.48))
                            .frame(width: 2, height: CGFloat(2 + level * 16))
                    }
                }
                .animation(.easeOut(duration: 0.08), value: model.levels)
            case .processing:
                ProgressView().controlSize(.small).tint(.white)
                Text("Transcribing…").font(.caption2).foregroundStyle(.white.opacity(0.82))
            case .done:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .doneRaw:
                Image(systemName: "checkmark.circle").foregroundStyle(.yellow)
                Text("verbatim").font(.caption2).foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .frame(width: 148, height: 32)
        .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 11))
    }
}
