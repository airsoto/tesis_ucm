import SwiftUI

struct CatalogFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    let page: CatalogSheet
    let theses: [Thesis]
    @Binding var filters: CatalogFilters

    var body: some View {
        NavigationStack {
            Form {
                if page == .advanced {
                    Section("Datos de la tesis") {
                        TextField("Autor", text: $filters.author)
                        TextField("Director", text: $filters.director)
                        choice("Año", options: Set(theses.compactMap(\.year)).sorted(by: >).map(String.init), value: $filters.year)
                    }
                }
                if page != .centres {
                    Section("Materias") {
                        choice("Materia UCM", options: options(theses.flatMap(\.subjectsUCM)), value: $filters.subject)
                        choice("Materia UNESCO", options: options(theses.flatMap(\.subjectsUNESCO)), value: $filters.unescoSubject)
                    }
                }
                if page != .subjects {
                    Section("Facultades y centros") {
                        let faculties = options(theses.compactMap(\.faculty))
                        if faculties.isEmpty {
                            Text("El catálogo actual no indica la facultad ni el centro de cada tesis.")
                                .foregroundStyle(AppTheme.muted)
                            Link("Consultar Docta Complutense", destination: URL(string: "https://docta.ucm.es/")!)
                        } else {
                            choice("Facultad o centro", options: faculties, value: $filters.faculty)
                        }
                        let languages = options(theses.compactMap(\.language))
                        if !languages.isEmpty {
                            choice("Idioma", options: languages, value: $filters.language)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.cream)
            .navigationTitle(page.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Limpiar") { filters = CatalogFilters(query: filters.query) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Hecho") { dismiss() }
                }
            }
        }
    }

    private func options(_ values: [String]) -> [String] {
        Set(values.filter { !$0.isEmpty }).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private func choice(_ title: String, options: [String], value: Binding<String>) -> some View {
        NavigationLink {
            CatalogFacet(title: title, options: options, selection: value)
        } label: {
            LabeledContent(title, value: value.wrappedValue.isEmpty ? "Cualquiera" : value.wrappedValue)
        }
    }
}

private struct CatalogFacet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let options: [String]
    @Binding var selection: String
    @State private var query = ""

    var body: some View {
        List {
            row("Cualquiera", value: "")
            ForEach(options.filter { query.isEmpty || $0.localizedStandardContains(query) }, id: \.self) { option in
                row(option, value: option)
            }
        }
        .searchable(text: $query, prompt: "Filtrar opciones")
        .navigationTitle(title)
    }

    private func row(_ label: String, value: String) -> some View {
        Button {
            selection = value
            dismiss()
        } label: {
            HStack {
                Text(label)
                Spacer()
                if selection == value { Image(systemName: "checkmark") }
            }
        }
        .accessibilityAddTraits(selection == value ? .isSelected : [])
    }
}
