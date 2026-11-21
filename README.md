# Tesis UCM

Aplicación nativa para iPhone para consultar, organizar y leer tesis académicas.

## Tecnología

- Swift 5 y SwiftUI.
- PDFKit para lectura de documentos PDF.
- XcodeGen para generar el proyecto de Xcode desde \`project.yml\`.
- CodeMagic para compilación continua y distribución mediante TestFlight/App Store.

## Identificador y plataforma

- Bundle ID: \`es.angelsoto.tesisucm\`
- Plataforma: iOS
- Dispositivo objetivo inicial: iPhone
- Versión inicial: 1.0 (1)

## Base de datos de tesis

La aplicación utiliza la base de datos JSON que ya alimentaba el buscador web del proyecto. Se ha trasladado desde \`airsoto/vet/tesis_ucm/json/tesis_fast/\` a este repositorio para que la web y la aplicación puedan trabajar con la misma fuente de datos.

**Estadísticas del manifiesto importado:**

- 15.419 tesis.
- 15.051 autores.
- 9.713 directores.
- 1.220 materias.
- Fechas de defensa entre 1853 y 2026.
- 62 fragmentos de datos, con un máximo de 250 registros por fragmento.
- 36 fragmentos de índice invertido de resúmenes.

### Archivos de datos

- \`TesisUCM/Resources/catalog.json\`: manifiesto del catálogo, estadísticas, número de fragmentos y materias principales.
- \`TesisUCM/Resources/chunks/chunk_0000.json\` … \`chunk_0061.json\`: registros completos de las tesis.
- \`TesisUCM/Resources/summary_index/0.json\` … \`z.json\`: índice invertido por términos para localizar tesis por contenido de sus resúmenes.

Se conservan los JSON sin comprimir. No se duplican los ficheros \`.gz\`, que contienen las mismas estructuras comprimidas.

### Campos originales de cada tesis

- \`_id\`: identificador del registro.
- \`title\`: título.
- \`authors\`: autores.
- \`directors\`: directores.
- \`summary\`: resumen.
- \`pub_date\`: fecha de publicación.
- \`defense_date\`: fecha de defensa.
- \`subjects_ucm\`: materias UCM.
- \`subjects_unesco\`: materias UNESCO.
- \`pdf\`: URL del documento PDF.
- \`link\`: URL del registro original.

La aplicación conserva los campos originales. No asigna facultades ni idiomas cuando esos datos no figuran en los registros de origen. Los PDF se consultan desde sus URL; no se copian al repositorio de código.

### Carga y caché en iPhone

1. La aplicación descarga el manifiesto desde GitHub.
2. Descarga los 62 fragmentos con un máximo de cinco descargas simultáneas.
3. Comprueba que el número de registros coincide con el total del manifiesto.
4. Guarda los fragmentos en el almacenamiento local de la aplicación.
5. En siguientes aperturas comprueba la versión del manifiesto y reutiliza la caché si no ha cambiado.

La búsqueda local actual consulta título, autores, directores, resumen y materias UCM/UNESCO. Los filtros disponibles se basan en el año de defensa y las clasificaciones UCM/UNESCO. Los 36 fragmentos del índice invertido se han importado y quedan disponibles para optimizar futuras búsquedas por términos.

Para publicar una actualización de la base de datos, hay que actualizar los JSON y aumentar \`version\` en el manifiesto \`catalog.json\`. Así la aplicación detectará que debe descargar los fragmentos nuevos.

## Estructura del proyecto

- \`TesisUCM/App\`: punto de entrada.
- \`TesisUCM/Models\`: modelos compatibles con el esquema original de tesis.
- \`TesisUCM/Services\`: descarga del catálogo, caché local, favoritos, notas y progreso.
- \`TesisUCM/Theme\`: identidad visual burdeos y crema.
- \`TesisUCM/Views\`: biblioteca, ficha, lector PDF, guardados y ajustes.
- \`project.yml\`: definición del proyecto para XcodeGen.
- \`codemagic.yaml\`: flujo inicial de compilación para iOS Simulator.

## Generar el proyecto en macOS

~~~bash
brew install xcodegen
xcodegen generate
open TesisUCM.xcodeproj
~~~

## CodeMagic

1. Añade el repositorio \`airsoto/tesis_ucm\` a CodeMagic.
2. Selecciona la configuración mediante \`codemagic.yaml\`.
3. Ejecuta el workflow \`ios-simulator\`.
4. El primer flujo comprueba la compilación sin firma para el simulador.
5. Después configura la firma de distribución y el envío a TestFlight con la integración de App Store Connect.

No se guardan claves privadas, certificados ni credenciales en este repositorio.

## Estado

La base de datos JSON completa se ha importado y el código Swift se ha adaptado a su esquema original. La compilación en CodeMagic y las pruebas con dispositivos iPhone son los siguientes pasos. Antes de la publicación deben comprobarse los enlaces externos y los derechos de uso de los registros y documentos enlazados.
