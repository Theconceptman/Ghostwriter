import SwiftUI

struct MainWindow: View {
    var body: some View {
        TabView {
            HistoryView().tabItem { Label("History", systemImage: "clock") }
            DictionaryView().tabItem { Label("Dictionary", systemImage: "character.book.closed") }
            SettingsView().tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .frame(minWidth: 700, minHeight: 500)
    }
}
