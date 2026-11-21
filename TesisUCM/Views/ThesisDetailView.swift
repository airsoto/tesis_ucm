import SwiftUI

struct ThesisDetailView: View {
    let thesis: Thesis

    @EnvironmentObject private var library: LibraryStore
    @State private var noteText = ""
    @State private var isDownloading = false
    @State private var showDownloadError = false
    @State private var downloadError = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                titleBlock
                actionBlock
                metadataBlock

                if let abstract = thesis.abstract, !abstract.isEmpty {
                    VStack(alignment: .leading, spacing: 9) {
                        sectionTitle("Resumen")
                        Text(abstract)
                            .font(.body)
                            .foregroundStyle(AppTheme.ink)
                            .lineSpacing(4)
                    }
                }

                notesBlock

                if let landingURL = thesis.landingURL {
                    Link(destination: landingURL) {
                        Label("Consultar registro oficial", systemImage: "arrow.up.right.square")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.burgundy)
                    }
                    .padding(.top, 4)
                }
            }
            .padding(20)
        }
        .background(AppTheme.cream.ignoresSafeArea())
        .navigationTitle("Tesis")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    library.toggleSaved(thesis)
                } label: {
                    Image(systemName: library.isSaved(thesis) ? "bookmark.fill" : "bookmark")
                }
                .accessibilityLabel(library.isSaved(thesis) ? "Quitar de guardados" : "Guardar tesis")
            }
        }
        .onAppear {
            noteText = library.notes[thesis.id] ?? ""
        }
        .alert("No se ha podido descargar el PDF", isPresented: $showDownloadError) {
            Button("Aceptar", role: .cancel) {}
        } message: {
            Text(downloadError)
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                if let year = thesis.year {
                    Text(String(year))
                }
                if thesis.hasPDF {
                    Label("PDF", systemImage: "doc.richtext")
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(AppTheme.burgundy)

            Text(thesis.title)
                .font(.system(size: 29, weight: .regular, design: .serif))
                .foregroundStyle(AppTheme.ink)
                .fixedSize(horizontal: false, vertical: true)

            Text(thesis.authorsText)
                .font(.headline.weight(.regular))
                .foregroundStyle(AppTheme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private var actionBlock: some View {
        if thesis.hasPDF {
            VStack(spacing: 10) {
                NavigationLink {
                    PDFReaderView(thesis: thesis)
                } label: {
                    let savedPage = library.progress[thesis.id]?.page
                    VStack(spacing: 4) {
                        Label(savedPage == nil ? "Leer tesis" : "Continuar lectura", systemImage: "book.pages")
                            .font(.headline)
                        if let savedPage {
                            Text("Página \(savedPage)")
                                .font(.caption)
                        }
                    }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(AppTheme.burgundy, in: RoundedRectangle(cornerRadius: 14))
                }

                Button {
                    Task {
                        isDownloading = true
                        do {
                            _ = try await library.downloadPDF(for: thesis)
                        } catch {
                            downloadError = error.localizedDescription
                            showDownloadError = true
                        }
                        isDownloading = false
                    }
                } label: {
                    HStack(spacing: 8) {
                        if isDownloading {
                            ProgressView()
                                .tint(AppTheme.burgundy)
                        } else {
                            Image(systemName: library.isDownloaded(thesis) ? "checkmark.circle" : "arrow.down.circle")
                        }
                        Text(
                            isDownloading
                            ? "Descargando…"
                            : (library.isDownloaded(thesis) ? "Disponible sin conexión" : "Descargar para leer sin conexión")
                        )
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.burgundy)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(AppTheme.paper, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppTheme.line, lineWidth: 1))
                }
                .disabled(isDownloading || library.isDownloaded(thesis))
            }
        } else {
            Text("No hay un PDF disponible para esta tesis.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(15)
                .background(AppTheme.paper, in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private var metadataBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Datos académicos")

            metadataRow("Dirección", value: thesis.directorsText)

            if let defenseDate = thesis.defenseDate, !defenseDate.isEmpty {
                metadataRow("Fecha de defensa", value: defenseDate)
            }

            if let pubDate = thesis.pubDate, !pubDate.isEmpty {
                metadataRow("Fecha de publicación", value: pubDate)
            }

            if !thesis.subjectsUCM.isEmpty {
                metadataRow("Materias UCM", value: thesis.subjectsUCM.joined(separator: ", "))
            }

            if !thesis.subjectsUNESCO.isEmpty {
                metadataRow("Materias UNESCO", value: thesis.subjectsUNESCO.joined(separator: ", "))
            }

            if let year = thesis.year {
                metadataRow("Año", value: String(year))
            }
        }
        .padding(16)
        .background(AppTheme.paper, in: RoundedRectangle(cornerRadius: 16))
    }

    private var notesBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Mis notas")

            TextEditor(text: $noteText)
                .frame(minHeight: 120)
                .padding(8)
                .scrollContentBackground(.hidden)
                .background(AppTheme.paper, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.line, lineWidth: 1))

            Button {
                library.saveNote(noteText, for: thesis)
            } label: {
                Label("Guardar nota", systemImage: "square.and.arrow.down")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.burgundy)
            }
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 20, weight: .regular, design: .serif))
            .foregroundStyle(AppTheme.ink)
    }

    private func metadataRow(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .tracking(0.8)
                .foregroundStyle(AppTheme.muted)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(AppTheme.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
