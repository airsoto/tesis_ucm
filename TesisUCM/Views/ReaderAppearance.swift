import SwiftUI

enum ReaderTypeface: String, CaseIterable, Identifiable {
    case georgia
    case newYork = "serif"
    case sanFrancisco = "sans"

    var id: Self { self }

    var label: String {
        switch self {
        case .georgia: "Georgia"
        case .newYork: "New York"
        case .sanFrancisco: "San Francisco"
        }
    }

    var detail: String {
        switch self {
        case .georgia: "Clásica, ideal para libros"
        case .newYork: "Elegante, estilo editorial"
        case .sanFrancisco: "Moderna y muy clara"
        }
    }

    func font(size: CGFloat) -> Font {
        switch self {
        case .georgia: .custom("Georgia", fixedSize: size)
        case .newYork: .system(size: size, design: .serif)
        case .sanFrancisco: .system(size: size)
        }
    }
}

enum ReaderPalette: String, CaseIterable, Identifiable {
    case light, sepia, dark

    var id: Self { self }

    var label: String {
        switch self {
        case .light: "Blanco"
        case .sepia: "Papel"
        case .dark: "Oscuro"
        }
    }

    var background: Color {
        switch self {
        case .light: .white
        case .sepia: AppTheme.cream
        case .dark: Color(red: 0.115, green: 0.095, blue: 0.10)
        }
    }

    var foreground: Color {
        self == .dark ? AppTheme.cream : AppTheme.ink
    }
}

struct ReaderAppearanceView: View {
    @Binding var typeface: ReaderTypeface
    @Binding var size: Double
    @Binding var spacing: Double
    @Binding var margins: Double
    @Binding var palette: ReaderPalette
    @Binding var speechRate: Double
    var appearanceOnly = false

    var body: some View {
        Form {
            if !appearanceOnly {
                Section("Tipografía") {
                    ForEach(ReaderTypeface.allCases) { option in
                        Button {
                            typeface = option
                        } label: {
                            HStack {
                                Text("Aa").font(option.font(size: 25))
                                    .frame(width: 44)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(option.label).font(.headline)
                                    Text(option.detail).font(.footnote).foregroundStyle(AppTheme.muted)
                                }
                                .accessibilityElement(children: .combine)
                                Spacer()
                                if option == typeface { Image(systemName: "checkmark") }
                            }
                            .foregroundStyle(AppTheme.ink)
                        }
                        .accessibilityAddTraits(option == typeface ? .isSelected : [])
                    }
                }

            }
            Section("Página") {
                if !appearanceOnly {
                    Stepper("Tamaño de letra: \(Int(size)) pt", value: $size, in: 14...36, step: 1)
                }
                Stepper("Interlineado: \(Int(spacing)) pt", value: $spacing, in: 2...16, step: 2)
                Stepper("Márgenes: \(Int(margins)) pt", value: $margins, in: 12...36, step: 4)
                Picker("Fondo", selection: $palette) {
                    ForEach(ReaderPalette.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Section("Vista previa") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Capítulo 1").font(.caption.bold()).textCase(.uppercase)
                    Text("Introducción").font(typeface.font(size: size + 8).bold())
                    Text("La investigación comienza con una pregunta. La lectura de trabajos previos ayuda a situarla y a definir cómo estudiarla.")
                        .font(typeface.font(size: size))
                        .lineSpacing(spacing)
                }
                .foregroundStyle(palette.foreground)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(palette.background, in: RoundedRectangle(cornerRadius: 14))
                .listRowInsets(EdgeInsets())
            }

            Section("Lectura en voz alta") {
                Picker("Velocidad", selection: $speechRate) {
                    Text("0,75×").tag(0.75)
                    Text("1×").tag(1.0)
                    Text("1,25×").tag(1.25)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.cream)
    }
}
