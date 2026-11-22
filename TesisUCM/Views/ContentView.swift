import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var library: LibraryStore
    @State private var tab: Tab = .home
    @State private var search = CatalogFilters()
    @State private var filterSheet: CatalogSheet?

    private enum Tab { case home, search, library, downloads, settings }

    var body: some View {
        TabView(selection: $tab) {
            CatalogHomeView { shortcut in
                switch shortcut {
                case .favorites: tab = .library
                case .downloads: tab = .downloads
                default:
                    search = CatalogFilters()
                    switch shortcut {
                    case .advanced: filterSheet = .advanced
                    case .subjects: filterSheet = .subjects
                    case .centres: filterSheet = .centres
                    case let .search(query): search.query = query
                    default: break
                    }
                    tab = .search
                }
            }
            .tabItem { Label("Inicio", systemImage: "house") }
            .tag(Tab.home)

            LibraryView(filters: $search, sheet: $filterSheet)
                .tabItem { Label("Buscar", systemImage: "magnifyingglass") }
                .tag(Tab.search)

            SavedView()
                .tabItem { Label("Biblioteca", systemImage: "book") }
                .tag(Tab.library)

            SavedView(downloads: true)
                .tabItem { Label("Descargas", systemImage: "arrow.down.to.line") }
                .tag(Tab.downloads)

            SettingsView()
                .tabItem { Label("Ajustes", systemImage: "gearshape") }
                .tag(Tab.settings)
        }
        .tint(AppTheme.burgundy)
        .task { await library.refreshCatalog() }
    }
}
