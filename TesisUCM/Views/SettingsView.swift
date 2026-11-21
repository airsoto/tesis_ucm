import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var library: LibraryStore

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Image(systemName: "books.vertical.fill")
                            .font(.title2)
                            .foregroundStyle(AppTheme.burgundy)
                            .frame(width: 42, height: 42)
                            .background(AppTheme.cream, in: RoundedRectangle(cornerRadius: 12))

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Tesis UCM")
                                .font(.headline)
                                .foregroundStyle(AppTheme.ink)
                            Text("Biblioteca académica para iPhone")
                                .font(.caption)
                                .foregroundStyle(AppTheme.muted)
                        }
                    }
                    .padding(.vertical, 5)
                }

                Section("Catálogo") {
                    LabeledContent("Registros disponibles", value: "\(library.theses.count)")
                    LabeledContent("Versión del catálogo", value: library.catalogManifest.map { String($0.version) } ?? "Sin cargar")
                    Button {
                        Task { await library.refreshCatalog() }
                    } label: {
                        HStack {
                            Label("Actualizar catálogo", systemImage: "arrow.clockwise")
                            Spacer()
                            if library.isRefreshing {
                                ProgressView()
                            }
                        }
                        .foregroundStyle(AppTheme.burgundy)
                    }
                    .disabled(library.isRefreshing)
                }

                Section("Aplicación") {
                    LabeledContent("Versión", value: appVersion)
                    LabeledContent("Plataforma", value: "iPhone")
                    LabeledContent("Lector", value: "PDFKit")
                }

                Section {
                    Text("Las notas, los marcadores, las tesis guardadas y el progreso de lectura se almacenan localmente en este dispositivo.")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.muted)

                    Text("Los documentos descargados se guardan en el espacio de almacenamiento de la aplicación para permitir su lectura sin conexión.")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.muted)
                } header: {
                    Text("Privacidad y almacenamiento")
                }

                if let error = library.lastError {
                    Section("Estado") {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.cream)
            .navigationTitle("Ajustes")
        }
    }
}
