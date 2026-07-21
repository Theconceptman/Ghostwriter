import SwiftUI
import GhostwriterCore

struct DictionaryView: View {
    @State private var terms: [DictionaryTerm] = []
    @State private var newTerm = ""
    @State private var newAliases = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Terms are fed to the speech model so they transcribe correctly. Aliases are common mishearings, auto-corrected to the term.")
                .font(.caption).foregroundStyle(.secondary).padding(.horizontal)
            HStack {
                TextField("Term (e.g. Supabase)", text: $newTerm)
                    .textFieldStyle(.roundedBorder)
                TextField("Aliases, comma-separated (e.g. super base)", text: $newAliases)
                    .textFieldStyle(.roundedBorder)
                Button("Add") { add() }
                    .disabled(newTerm.trimmingCharacters(in: .whitespaces).isEmpty)
            }.padding(.horizontal)
            if terms.isEmpty {
                ContentUnavailableView("No terms yet", systemImage: "character.book.closed",
                    description: Text("Add the words Whisper keeps getting wrong — product names, libraries, people."))
                    .frame(maxHeight: .infinity)
            } else {
                List(terms, id: \.id) { term in
                    HStack {
                        Text(term.term).bold()
                        if !term.aliases.isEmpty {
                            Text("← " + term.aliases.joined(separator: ", "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { remove(term) } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                    }
                }
            }
        }
        .padding(.vertical)
        .onAppear(perform: reload)
    }

    private func reload() { terms = (try? AppState.shared.db.allTerms()) ?? [] }
    private func add() {
        let aliases = newAliases.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        try? AppState.shared.db.addTerm(DictionaryTerm(
            term: newTerm.trimmingCharacters(in: .whitespaces), aliases: aliases))
        newTerm = ""; newAliases = ""; reload()
    }
    private func remove(_ term: DictionaryTerm) {
        if let id = term.id { try? AppState.shared.db.deleteTerm(id: id) }
        reload()
    }
}
