import SwiftUI

@main
struct TesisUCMApp: App {
    @StateObject private var library = LibraryStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(library)
                .tint(AppTheme.burgundy)
                .preferredColorScheme(.light)
        }
    }
}
