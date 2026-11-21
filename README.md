# Tesis UCM

Aplicación nativa para iPhone para consultar, organizar y leer tesis académicas.

## Tecnología

- Swift 5 y SwiftUI.
- PDFKit para lectura de documentos PDF.
- XcodeGen para generar el proyecto de Xcode desde \`project.yml\`.
- CodeMagic para compilación continua y, en una fase posterior, firma y distribución mediante TestFlight.

## Identificador

- Bundle ID: \`es.angelsoto.tesisucm\`
- Plataforma: iOS
- Dispositivo objetivo inicial: iPhone
- Versión inicial: 1.0 (1)

## Estructura

- \`TesisUCM/App\`: punto de entrada y composición de la aplicación.
- \`TesisUCM/Models\`: modelos del catálogo.
- \`TesisUCM/Services\`: catálogo remoto, descargas y persistencia local.
- \`TesisUCM/Theme\`: colores y estilos.
- \`TesisUCM/Views\`: biblioteca, ficha, lector PDF, guardados y ajustes.
- \`TesisUCM/Resources/catalog.json\`: catálogo inicial incluido en la aplicación.
- \`project.yml\`: definición del proyecto para XcodeGen.
- \`codemagic.yaml\`: flujo inicial de compilación sin firma para iOS Simulator.

## Catálogo

La aplicación carga primero el catálogo incluido en el bundle y después intenta actualizarlo desde:

https://raw.githubusercontent.com/airsoto/tesis_ucm/main/TesisUCM/Resources/catalog.json

El JSON tiene esta estructura:

\`\`\`json
{
  "updatedAt": "2026-11-21",
  "theses": [
    {
      "id": "identificador-unico",
      "title": "Título de la tesis",
      "authors": ["Nombre del autor"],
      "directors": ["Nombre del director"],
      "year": 2025,
      "faculty": "Facultad",
      "subjects": ["Materia"],
      "language": "Español",
      "abstract": "Resumen de la tesis",
      "pdfURL": "https://servidor.example/tesis.pdf",
      "landingURL": "https://repositorio.example/registro",
      "isPDFAvailable": true
    }
  ]
}
\`\`\`

Los campos \`id\` y \`title\` son obligatorios. El resto admite valores vacíos o nulos. Las URL deben ser enlaces HTTPS públicos y estables.

**Importante:** el catálogo inicial está vacío. Antes de publicar habrá que incorporar el catálogo real y comprobar que los enlaces de las tesis y los PDF se pueden utilizar legítimamente.

## Generar el proyecto en macOS

Instala Xcode y XcodeGen. Desde la raíz del repositorio ejecuta:

\`\`\`bash
brew install xcodegen
xcodegen generate
open TesisUCM.xcodeproj
\`\`\`

## CodeMagic

1. Añade el repositorio \`airsoto/tesis_ucm\` a CodeMagic.
2. Selecciona configuración mediante \`codemagic.yaml\`.
3. Ejecuta el workflow \`ios-simulator\`.
4. El primer flujo comprueba que el proyecto compila sin firma para el simulador.

La firma de distribución y el envío a TestFlight se configurarán después de conectar la integración de App Store Connect y cargar los perfiles/certificados de firma en CodeMagic. No se guardan claves privadas ni credenciales en este repositorio.

## Estado

Base inicial del proyecto. El lector PDF, el catálogo remoto y la persistencia local están preparados para evolucionar; se deben validar con datos reales y dispositivos antes de la publicación.
