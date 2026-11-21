import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var library: LibraryStore
    @State private var searchText = ""
    @State private var selectedYear = "Todos"
    @State private var selectedFaculty = "Todas"
    @State private var selectedSubject = "Todas"

    private var years: [String] {
        Set(library.theses.compactMap { $0.year }.map(String.init))
            .sorted(by: >)
    }

    private var faculties: [String] {
        Set(library.theses.compactMap(\.faculty).filter { !$0.isEmpty })
            .sorted()
    }

    private var subjects: [String] {
        Set(library.theses.flatMap(\.subjects).filter { !$0.isEmpty })
            .sorted()
    }

    private var filteredTheses: [Thesis] {
        library.theses.filter { thesis in
            let searchableText = (
                [thesis.title, thesis.faculty ?? ""] +
                thesis.authors +
                thesis.directors +
                thesis.subjects
            )
            .joined(separator: " ")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)

            let matchesSearch = searchText.isEmpty ||
                searchableText.contains(searchText.folding(
                    options: [.diacriticInsensitive, .caseInsensitive],
                    locale: .current
                ))

            let matchesYear = selectedYear == "Todos" || String(thesis.year ?? 0) == selectedYear
            let matchesFaculty = selectedFaculty == "Todas" || thesis.faculty == selectedFaculty
            let matchesSubject = selectedSubject == "Todas" || thesis.subjects.contains(selectedSubject)

            return matchesSearch && matchesYear && matchesFaculty && matchesSubject
        }
        .sorted {
            if $0.year != $1.year {
                return ($0.year ?? 0) > ($1.year ?? 0)
            }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    private var hasActiveFilters: Bool {
        selectedYear != "Todos" || selectedFaculty != "Todas" || selectedSubject != "Todas"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    introduction
                    filterBar

                    if library.isRefreshing {
                        ProgressView("Actualizando catálogo…")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .tint(AppTheme.burgundy)
                    }

                    if filteredTheses.isEmpty {
                        emptyState
                    } else {
                        VStack(spacing: 12) {
                            HStack {
                                Text("\(filteredTheses.count) tesis")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(AppTheme.muted)
                                Spacer()
                            }

                            ForEach(filteredTheses) { thesis in
                                NavigationLink {
                                    ThesisDetailView(thesis: thesis)
                                } label: {
                                    ThesisCardView(thesis: thesis)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .background(AppTheme.cream.ignoresSafeArea())
            .navigationTitle("Biblioteca")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $searchText, prompt: "Título, autor, director o materia")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await library.refreshCatalog() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Actualizar catálogo")
                    .disabled(library.isRefreshing)
                }
            }
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TESIS UCM")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .tracking(2.4)
                .foregroundStyle(AppTheme.burgundy)

            Text("Conocimiento para consultar, explorar y leer.")
                .font(.system(size: 25, weight: .regular, design: .serif))
                .foregroundStyle(AppTheme.ink)
                .fixedSize(horizontal: false, vertical: true)

            Text("Una biblioteca académica en tu iPhone.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Menu {
                    Picker("Año", selection: $selectedYear) {
                        Text("Todos los años").tag("Todos")
                        ForEach(years, id: \.self) { year in
                            Text(year).tag(year)
                        }
                    }
                } label: {
                    filterLabel(selectedYear == "Todos" ? "Año" : selectedYear, icon: "calendar")
                }

                Menu {
                    Picker("Facultad", selection: $selectedFaculty) {
                        Text("Todas las facultades").tag("Todas")
                        ForEach(faculties, id: \.self) { faculty in
                            Text(faculty).tag(faculty)
                        }
                    }
                } label: {
                    filterLabel(selectedFaculty == "Todas" ? "Facultad" : selectedFaculty, icon: "building.columns")
                }

                Menu {
                    Picker("Materia", selection: $selectedSubject) {
                        Text("Todas las materias").tag("Todas")
                        ForEach(subjects, id: \.self) { subject in
                            Text(subject).tag(subject)
                        }
                    }
                } label: {
                    filterLabel(selectedSubject == "Todas" ? "Materia" : selectedSubject, icon: "tag")
                }

                if hasActiveFilters {
                    Button("Limpiar") {
                        selectedYear = "Todos"
                        selectedFaculty = "Todas"
                        selectedSubject = "Todas"
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.burgundy)
                }
            }
        }
    }

    private func filterLabel(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.caption.weight(.medium))
            .foregroundStyle(AppTheme.burgundy)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(AppTheme.paper, in: Capsule())
            .overlay(Capsule().stroke(AppTheme.line, lineWidth: 1))
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: library.theses.isEmpty ? "books.vertical" : "magnifyingglass")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(AppTheme.burgundy)
                .padding(.bottom, 4)

            Text(library.theses.isEmpty ? "La biblioteca está preparada" : "No hay resultados")
                .font(.system(size: 20, weight: .regular, design: .serif))
                .foregroundStyle(AppTheme.ink)

            Text(
                library.theses.isEmpty
                ? "El catálogo todavía no contiene tesis. Cuando incorporemos los registros al repositorio, aparecerán aquí."
                : "Prueba con otras palabras o elimina alguno de los filtros."
            )
            .font(.subheadline)
            .foregroundStyle(AppTheme.muted)
            .multilineTextAlignment(.center)

            if library.theses.isEmpty {
                Button {
                    Task { await library.refreshCatalog() }
                } label: {
                    Label("Actualizar catálogo", systemImage: "arrow.clockwise")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 11)
                        .background(AppTheme.burgundy, in: Capsule())
                }
                .padding(.top, 4)
            } else if hasActiveFilters || !searchText.isEmpty {
                Button("Borrar búsqueda y filtros") {
                    searchText = ""
                    selectedYear = "Todos"
                    selectedFaculty = "Todas"
                    selectedSubject = "Todas"
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.burgundy)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 42)
        .background(AppTheme.paper, in: RoundedRectangle(cornerRadius: 22))
    }
}

private struct ThesisCardView: View {
    let thesis: Thesis

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 8) {
                if let year = thesis.year {
                    metadataPill(String(year))
                }
                if thesis.hasPDF {
                    metadataPill("PDF disponible", icon: "doc.richtext")
                }
                Spacer(minLength: 0)
                if thesis.isPDFAvailable == false {
                    Image(systemName: "doc")
                        .foregroundStyle(AppTheme.muted)
                }
            }

            Text(thesis.title)
                .font(.system(size: 18, weight: .semibold, design: .serif))
                .foregroundStyle(AppTheme.ink)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(thesis.authorsText)
                .font(.subheadline)
                .foregroundStyle(AppTheme.muted)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let faculty = thesis.faculty, !faculty.isEmpty {
                Label(faculty, systemImage: "building.columns")
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
                    .lineLimit(1)
            }

            HStack {
                if let firstSubject = thesis.subjects.first {
                    Text(firstSubject)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppTheme.burgundy)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.burgundy)
            }
        }
        .padding(16)
        .background(AppTheme.paper, in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(AppTheme.line.opacity(0.8), lineWidth: 1)
        }
    }

    private func metadataPill(_ title: String, icon: String? = nil) -> some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
            }
            Text(title)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(AppTheme.burgundy)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(AppTheme.cream, in: Capsule())
    }
}
