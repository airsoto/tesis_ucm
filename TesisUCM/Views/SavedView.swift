import SwiftUI

struct SavedView: View {
    @EnvironmentObject private var library: LibraryStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if library.savedTheses.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "bookmark")
                                .font(.system(size: 34, weight: .light))
                                .foregroundStyle(AppTheme.burgundy)

                            Text("Tu biblioteca personal")
                                .font(.system(size: 22, weight: .regular, design: .serif))
                                .foregroundStyle(AppTheme.ink)

                            Text("Guarda las tesis que quieras consultar más adelante. Aparecerán aquí.")
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.muted)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 52)
                        .background(AppTheme.paper, in: RoundedRectangle(cornerRadius: 20))
                    } else {
                        Text("\(library.savedTheses.count) tesis guardadas")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.muted)

                        ForEach(library.savedTheses) { thesis in
                            NavigationLink {
                                ThesisDetailView(thesis: thesis)
                            } label: {
                                SavedThesisRow(thesis: thesis)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(20)
            }
            .background(AppTheme.cream.ignoresSafeArea())
            .navigationTitle("Guardados")
        }
    }
}

private struct SavedThesisRow: View {
    let thesis: Thesis

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if let year = thesis.year {
                    Text(String(year))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.burgundy)
                }
                Spacer()
                Image(systemName: "bookmark.fill")
                    .font(.caption)
                    .foregroundStyle(AppTheme.burgundy)
            }

            Text(thesis.title)
                .font(.system(size: 18, weight: .semibold, design: .serif))
                .foregroundStyle(AppTheme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(thesis.authorsText)
                .font(.subheadline)
                .foregroundStyle(AppTheme.muted)
                .lineLimit(2)
        }
        .padding(16)
        .background(AppTheme.paper, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppTheme.line, lineWidth: 1))
    }
}
