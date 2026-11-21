import SwiftUI

struct SavedView: View {
    @EnvironmentObject private var library: LibraryStore
    var downloads = false
    @State private var pendingRemoval: Thesis?

    var body: some View {
        let theses = downloads ? library.downloadedTheses : library.savedTheses
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 11) {
                    if theses.isEmpty {
                        ContentUnavailableView(
                            downloads ? "Sin descargas" : "Tu biblioteca personal",
                            systemImage: downloads ? "arrow.down.to.line" : "star",
                            description: Text(downloads ? "Descarga un PDF desde la ficha de una tesis para leerlo sin conexión." : "Pulsa la estrella de una tesis para guardarla aquí.")
                        )
                    }
                    ForEach(theses) { thesis in
                        VStack(alignment: .trailing, spacing: 0) {
                            ThesisResultCard(thesis: thesis)
                            if downloads {
                                Button("Eliminar descarga", systemImage: "trash", role: .destructive) {
                                    pendingRemoval = thesis
                                }
                                .font(.footnote)
                                .padding(10)
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(AppTheme.cream.ignoresSafeArea())
            .navigationTitle(downloads ? "Descargas" : "Biblioteca")
            .confirmationDialog("¿Eliminar el PDF descargado?", isPresented: Binding(
                get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }
            ), titleVisibility: .visible, presenting: pendingRemoval) { thesis in
                Button("Eliminar descarga", role: .destructive) {
                    library.removeDownloadedPDF(for: thesis)
                    pendingRemoval = nil
                }
            }
        }
    }
}
