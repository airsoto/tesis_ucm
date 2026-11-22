import SwiftUI

struct CatalogHomeView: View {
    enum Shortcut {
        case advanced, subjects, centres, recent, downloads, favorites, search(String)
    }

    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var query = ""
    let open: (Shortcut) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                header
                VStack(spacing: 6) {
                    Text("Catálogo de tesis doctorales")
                        .font(.title2.bold())
                        .foregroundStyle(AppTheme.ink)
                    if let count = library.catalogManifest?.total {
                        Text("\(count.formatted(.number.locale(Locale(identifier: "es_ES")))) tesis para explorar, buscar y consultar.")
                            .foregroundStyle(AppTheme.muted)
                    } else if library.isRefreshing {
                        ProgressView("Cargando catálogo…")
                    }
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
                searchField
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: typeSize.isAccessibilitySize ? 2 : 3), spacing: 10) {
                    tile("Búsqueda avanzada", "slider.horizontal.3", 0xF8E2E6, .burgundy, .advanced)
                    tile("Explorar por materias", "square.3.layers.3d", 0xE8EFFC, .blue, .subjects)
                    tile("Facultades y centros", "building.columns", 0xFBECD4, .ochre, .centres)
                    tile("Tesis recientes", "clock", 0xE7EFDE, .green, .recent)
                    tile("Mis descargas", "arrow.down.to.line", 0xF0E7FA, .violet, .downloads)
                    tile("Mis favoritas", "star", 0xFFF1D3, .ochre, .favorites)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .background(AppTheme.cream.ignoresSafeArea())
    }

    private var header: some View {
        ZStack(alignment: .topLeading) {
            GeometryReader { geometry in
                Image("LibraryHeader")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .accessibilityHidden(true)
            }
            LinearGradient(
                colors: [AppTheme.paper.opacity(0.58), .clear, AppTheme.burgundyDark.opacity(0.12)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            HStack(spacing: 12) {
                Image("AppIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 66, height: 66)
                    .padding(5)
                    .background(.white.opacity(0.88), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.95), lineWidth: 1.5))
                    .shadow(color: .black.opacity(0.16), radius: 7, x: 0, y: 4)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Tesis UCM")
                        .font(.system(size: 31, weight: .bold, design: .serif))
                        .foregroundStyle(AppTheme.burgundyDark)
                        .accessibilityAddTraits(.isHeader)
                    Text("Universidad Complutense\nde Madrid")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 28)
            VStack {
                Spacer()
                HeaderWave()
                    .fill(AppTheme.burgundy)
                    .frame(height: 34)
                    .shadow(color: AppTheme.burgundyDark.opacity(0.18), radius: 4, x: 0, y: -2)
            }
        }
        .frame(height: 232)
        .background(AppTheme.burgundyDark)
        .clipShape(.rect(bottomLeadingRadius: 27, bottomTrailingRadius: 27))
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            TextField("Buscar tesis, autor, director…", text: $query)
                .accessibilityLabel("Buscar tesis")
                .submitLabel(.search)
                .onSubmit { open(.search(query)) }
            Button {
                open(.search(query))
            } label: {
                Image(systemName: "magnifyingglass").frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("Mostrar resultados")
        }
        .padding(.leading, 14)
        .padding(.trailing, 4)
        .background(AppTheme.paper, in: RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(AppTheme.line) }
        .padding(.horizontal, 16)
    }

    private func tile(_ title: String, _ icon: String, _ fill: UInt32, _ tone: Tone, _ shortcut: Shortcut) -> some View {
        Button {
            open(shortcut)
        } label: {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2.weight(.medium))
                    .foregroundStyle(tone.color)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 106)
            .background(
                LinearGradient(
                    colors: [Color(rgb: fill).opacity(0.96), Color(rgb: fill)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 18)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(.white.opacity(0.82), lineWidth: 1)
            }
            .shadow(color: tone.color.opacity(0.18), radius: 1, x: 0, y: 3)
            .shadow(color: .black.opacity(0.10), radius: 7, x: 0, y: 5)
        }
        .buttonStyle(HomeTileButtonStyle())
    }

    private enum Tone {
        case burgundy, blue, ochre, green, violet
        var color: Color {
            switch self {
            case .burgundy: AppTheme.burgundy
            case .blue: Color(rgb: 0x214F87)
            case .ochre: Color(rgb: 0x825116)
            case .green: Color(rgb: 0x35582A)
            case .violet: Color(rgb: 0x663D95)
            }
        }
    }
}

private struct HomeTileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .offset(y: configuration.isPressed ? 2 : 0)
            .brightness(configuration.isPressed ? -0.025 : 0)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

private struct HeaderWave: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: 0, y: rect.height * 0.30))
            path.addCurve(
                to: CGPoint(x: rect.width, y: rect.height * 0.18),
                control1: CGPoint(x: rect.width * 0.28, y: rect.height * 1.12),
                control2: CGPoint(x: rect.width * 0.66, y: -rect.height * 0.38)
            )
            path.addLine(to: CGPoint(x: rect.width, y: rect.height))
            path.addLine(to: CGPoint(x: 0, y: rect.height))
            path.closeSubpath()
        }
    }
}

private extension Color {
    init(rgb: UInt32) {
        self.init(red: Double((rgb >> 16) & 255) / 255,
                  green: Double((rgb >> 8) & 255) / 255,
                  blue: Double(rgb & 255) / 255)
    }
}
