import SwiftUI
import GhostwriterCore

struct HistoryView: View {
    @State private var query = ""
    @State private var rows: [DictationRecord] = []
    @State private var expanded: Set<Int64> = []

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search dictations…", text: $query)
                .textFieldStyle(.roundedBorder).padding()
                .onChange(of: query) { _, _ in reload() }
            if rows.isEmpty {
                ContentUnavailableView(
                    query.isEmpty ? "No dictations yet" : "No matches",
                    systemImage: "waveform",
                    description: Text(query.isEmpty
                        ? "Hold your hotkey anywhere and start talking."
                        : "Try a different search."))
                    .frame(maxHeight: .infinity)
            } else {
                List(rows, id: \.id) { rec in row(rec) }
            }
        }
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: .gwHistoryChanged)) { _ in reload() }
    }

    @ViewBuilder
    private func row(_ rec: DictationRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                Text(rec.cleanedText)
                    .lineLimit(expanded.contains(rec.id ?? -1) ? nil : 2)
                    .textSelection(.enabled)
                Spacer()
                if rec.usedFallback {
                    Text("verbatim").font(.caption2).padding(3)
                        .background(.yellow.opacity(0.3), in: Capsule())
                        .help("Cleanup overreached; your exact words were used instead")
                }
                Button { copy(rec.cleanedText) } label: { Image(systemName: "doc.on.doc") }
                    .buttonStyle(.borderless)
                    .help("Copy")
            }
            HStack(spacing: 8) {
                Text(rec.createdAt, style: .date).font(.caption2).foregroundStyle(.secondary)
                Text(rec.createdAt, style: .time).font(.caption2).foregroundStyle(.secondary)
                if let app = rec.appBundleID {
                    Text(app.split(separator: ".").last.map(String.init) ?? app)
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Text(String(format: "%.1fs", rec.durationSec))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if expanded.contains(rec.id ?? -1) {
                GroupBox("Raw transcript") {
                    Text(rec.rawText).font(.callout).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { toggle(rec.id) }
        .padding(.vertical, 2)
    }

    private func toggle(_ id: Int64?) {
        guard let id else { return }
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
    }
    private func copy(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }
    private func reload() {
        let db = AppState.shared.db
        rows = (try? (query.isEmpty ? db.recentDictations() : db.searchDictations(query))) ?? []
    }
}
