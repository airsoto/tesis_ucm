import SwiftUI

enum CatalogSheet: String, Identifiable {
    case advanced, subjects, centres
    var id: Self { self }
    var title: String {
        switch self {
        case .advanced: "Búsqueda avanzada"
        case .subjects: "Explorar por materias"
        case .centres: "Facultades y centros"
        }
    }
}

struct CatalogFilters: Equatable {
    var query = ""
    var author = ""
    var director = ""
    var year = ""
    var subject = ""
    var unescoSubject = ""
    var faculty = ""
    var language = ""

    private static func matches(_ value: String, in field: String) -> Bool {
        let term = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return term.isEmpty || field.localizedStandardContains(term)
    }

    func includes(_ thesis: Thesis) -> Bool {
        guard year.isEmpty || thesis.year.map(String.init) == year,
              subject.isEmpty || thesis.subjectsUCM.contains(subject),
              unescoSubject.isEmpty || thesis.subjectsUNESCO.contains(unescoSubject),
              faculty.isEmpty || thesis.faculty == faculty,
              language.isEmpty || thesis.language == language,
              Self.matches(author, in: thesis.authors.joined(separator: " ")),
              Self.matches(director, in: thesis.directors.joined(separator: " ")) else { return false }
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        let metadata = [thesis.title, thesis.defenseDate ?? "", thesis.pubDate ?? ""] +
            thesis.authors + thesis.directors + thesis.subjectsUCM + thesis.subjectsUNESCO
        return Self.matches(query, in: metadata.joined(separator: " ")) ||
            Self.matches(query, in: thesis.summary ?? "")
    }
}

struct LibraryView: View {
    @EnvironmentObject private var library: LibraryStore
    @Binding var filters: CatalogFilters
    @Binding var sheet: CatalogSheet?
    @AppStorage("catalog.searchHistory") private var historyData = Data()
    @State private var results = [Thesis]()
    @State private var withPDFCount = 0
    @State private var isSearching = false
    @State private var availability: Availability = .all
    @FocusState private var searchFocused: Bool

    private enum Availability: String, CaseIterable {
        case all = "Todas"
        case available = "Con PDF"
        case unavailable = "Sin PDF"
    }

    private struct Input: Equatable {
        let filters: CatalogFilters
        let version: Int?
    }

    private var history: [String] { (try? JSONDecoder().decode([String].self, from: historyData)) ?? [] }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                searchField.padding(.horizontal, 16)
                if searchFocused, filters.query.isEmpty, !history.isEmpty {
                    recentSearches
                } else {
                    availabilityBar
                    resultList
                }
            }
            .padding(.top, 8)
            .background(AppTheme.cream.ignoresSafeArea())
            .navigationTitle("Buscar tesis")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Filtros", systemImage: "line.3.horizontal.decrease") {
                        searchFocused = false
                        sheet = .advanced
                    }
                    .labelStyle(.iconOnly)
                }
            }
            .sheet(item: $sheet) { page in
                CatalogFilterSheet(page: page, theses: library.theses, filters: $filters)
            }
        }
        .task(id: Input(filters: filters, version: library.catalogManifest?.version)) {
            let input = filters
            let theses = library.theses
            isSearching = true
            do {
                try await Task.sleep(for: .milliseconds(100))
            } catch { return }

            let worker = Task.detached(priority: .userInitiated) {
                var matches = [Thesis]()
                var pdfCount = 0
                for thesis in theses {
                    if Task.isCancelled { break }
                    if input.includes(thesis) {
                        matches.append(thesis)
                        if thesis.hasPDF { pdfCount += 1 }
                    }
                }
                return (matches, pdfCount)
            }
            let (matches, pdfCount) = await withTaskCancellationHandler {
                await worker.value
            } onCancel: {
                worker.cancel()
            }
            guard !Task.isCancelled else { return }
            results = matches
            withPDFCount = pdfCount
            isSearching = false
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(AppTheme.muted)
                .accessibilityHidden(true)
            TextField("Título, autor, director o materia", text: $filters.query)
                .accessibilityLabel("Buscar tesis")
                .focused($searchFocused)
                .submitLabel(.search)
                .onSubmit { submit(filters.query) }
            if !filters.query.isEmpty {
                Button("Borrar búsqueda", systemImage: "xmark.circle.fill") { filters.query = "" }
                    .labelStyle(.iconOnly)
                    .frame(minWidth: 44, minHeight: 44)
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .frame(minHeight: 46)
        .background(AppTheme.paper, in: RoundedRectangle(cornerRadius: 15))
        .overlay { RoundedRectangle(cornerRadius: 15).strokeBorder(AppTheme.line) }
    }

    private var availabilityBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(Availability.allCases, id: \.self) { option in
                    let count = option == .all ? results.count : (option == .available ? withPDFCount : results.count - withPDFCount)
                    Button {
                        availability = option
                    } label: {
                        Text("\(option.rawValue) (\(count))")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 12)
                            .frame(minHeight: 44)
                            .foregroundStyle(availability == option ? .white : AppTheme.ink)
                            .background(availability == option ? AppTheme.burgundy : AppTheme.paper, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(availability == option ? .isSelected : [])
                }
            }
            .padding(.horizontal, 16)
        }
        .scrollIndicators(.hidden)
    }

    private var resultList: some View {
        let visible = results.filter {
            availability == .all || $0.hasPDF == (availability == .available)
        }
        return ScrollView {
            LazyVStack(spacing: 11) {
                if visible.isEmpty {
                    if library.isRefreshing || isSearching {
                        ProgressView(library.theses.isEmpty ? "Cargando catálogo…" : "Buscando…")
                            .padding(.top, 36)
                    } else {
                        ContentUnavailableView("Sin resultados", systemImage: "magnifyingglass",
                                               description: Text(library.theses.isEmpty ? (library.lastError ?? "El catálogo todavía no está disponible.") : "Prueba con otra búsqueda o cambia los filtros."))
                    }
                }
                ForEach(visible) { thesis in
                    ThesisResultCard(thesis: thesis, beforeOpen: { remember(filters.query) })
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .scrollDismissesKeyboard(.interactively)
        .refreshable { await library.refreshCatalog() }
    }

    private var recentSearches: some View {
        List {
            Section("Búsquedas recientes") {
                ForEach(history, id: \.self) { term in
                    Button(term, systemImage: "clock") { submit(term) }
                }
                Button("Borrar historial", role: .destructive) { historyData = Data() }
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func submit(_ query: String) {
        filters.query = query
        searchFocused = false
        remember(query)
    }

    private func remember(_ query: String) {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return }
        let updated = [term] + history.filter { $0.caseInsensitiveCompare(term) != .orderedSame }
        historyData = (try? JSONEncoder().encode(Array(updated.prefix(12)))) ?? Data()
    }
}

struct ThesisResultCard: View {
    @EnvironmentObject private var library: LibraryStore
    let thesis: Thesis
    var beforeOpen: () -> Void = {}

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            NavigationLink {
                ThesisDetailView(thesis: thesis)
                    .onAppear(perform: beforeOpen)
            } label: {
                HStack(alignment: .center, spacing: 12) {
                    VStack(spacing: 4) {
                        Image(systemName: thesis.hasPDF ? "doc.richtext" : "doc")
                            .font(.title2)
                        Text(thesis.hasPDF ? "PDF" : "Sin PDF")
                            .font(.caption2.bold())
                    }
                    .foregroundStyle(thesis.hasPDF ? AppTheme.burgundy : AppTheme.muted)
                    .frame(minWidth: 43)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(thesis.title).font(.headline)
                            .fixedSize(horizontal: false, vertical: true)
                        Label(thesis.authorsText, systemImage: "person")
                            .font(.subheadline).lineLimit(2)
                        if let year = thesis.year {
                            Label(String(year), systemImage: "calendar").font(.caption)
                        }
                    }
                    .foregroundStyle(AppTheme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .multilineTextAlignment(.leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                library.toggleSaved(thesis)
            } label: {
                Image(systemName: library.isSaved(thesis) ? "star.fill" : "star")
                    .foregroundStyle(library.isSaved(thesis) ? Color(red: 0.60, green: 0.34, blue: 0.05) : AppTheme.muted)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(library.isSaved(thesis) ? "Quitar de favoritas" : "Añadir a favoritas")
        }
        .padding(12)
        .background(AppTheme.paper, in: RoundedRectangle(cornerRadius: 19))
        .overlay { RoundedRectangle(cornerRadius: 19).strokeBorder(AppTheme.line.opacity(0.65)) }
    }
}
