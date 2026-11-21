import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            LibraryView()
                .tabItem {
                    Label("Biblioteca", systemImage: "books.vertical")
                }

            SavedView()
                .tabItem {
                    Label("Guardados", systemImage: "bookmark")
                }

            SettingsView()
                .tabItem {
                    Label("Ajustes", systemImage: "slider.horizontal.3")
                }
        }
        .task {
            await refreshIfNeeded()
        }
    }

    @EnvironmentObject private var library: LibraryStore

    private func refreshIfNeeded() async {
        if library.theses.isEmpty {
            await library.refreshCatalog()
        }
    }
}
