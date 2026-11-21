import SwiftUI

enum ReaderTypeface: String, CaseIterable, Identifiable {
    case sans, serif, rounded

    var id: Self { self }

    var label: String {
        switch self {
        case .sans: "Sans serif"
        case .serif: "Serif"
        case .rounded: "Redondeada"
        }
    }

    var design: Font.Design {
        switch self {
        case .sans: .default
        case .serif: .serif
        case .rounded: .rounded
        }
    }
}

enum ReaderPalette: String, CaseIterable, Identifiable {
    case light, sepia, dark

    var id: Self { self }

    var label: String {
        switch self {
        case .light: "Claro"
        case .sepia: "Sepia"
        case .dark: "Oscuro"
        }
    }

    var background: Color {
        switch self {
        case .light: AppTheme.paper
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

    var body: some View {
        Form {
            Section("Tipografía") {
                ForEach(ReaderTypeface.allCases) { option in
                    Button {
                        typeface = option
                    } label: {
                        HStack {
                            Text("Aa").font(.system(.title2, design: option.design))
                                .frame(width: 44)
                            Text(option.label)
                            Spacer()
                            if option == typeface { Image(systemName: "checkmark") }
                        }
                        .foregroundStyle(AppTheme.ink)
                    }
                    .accessibilityAddTraits(option == typeface ? .isSelected : [])
                }
            }

            Section("Página") {
                Stepper("Tamaño de letra: \(Int(size)) pt", value: $size, in: 14...36, step: 2)
                Stepper("Interlineado: \(Int(spacing)) pt", value: $spacing, in: 2...16, step: 2)
                Stepper("Márgenes: \(Int(margins)) pt", value: $margins, in: 12...36, step: 4)
                Picker("Fondo", selection: $palette) {
                    ForEach(ReaderPalette.allCases) { Text($0.label).tag($0) }
                }
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
