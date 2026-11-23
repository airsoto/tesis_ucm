package es.angelsoto.tesisucm

import android.graphics.Bitmap
import android.graphics.pdf.PdfRenderer
import android.os.ParcelFileDescriptor
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.tom_roush.pdfbox.android.PDFBoxResourceLoader
import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.text.PDFTextStripper
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

private val wineReader = Color(0xFF681B35)
private val paperReader = Color(0xFFFFF9F0)

@Composable
fun ThesisReaderScreen(pdfUrl: String, title: String, onClose: () -> Unit) {
    val ctx = LocalContext.current
    var file by remember(pdfUrl) { mutableStateOf<File?>(null) }
    var error by remember(pdfUrl) { mutableStateOf<String?>(null) }
    var pageCount by remember(pdfUrl) { mutableIntStateOf(0) }
    var page by remember(pdfUrl) { mutableIntStateOf(1) }
    var adaptive by remember { mutableStateOf(true) }
    var text by remember { mutableStateOf("") }
    var image by remember { mutableStateOf<Bitmap?>(null) }
    var size by remember { mutableFloatStateOf(19f) }
    var palette by remember { mutableStateOf("Papel") }
    var controls by remember { mutableStateOf(false) }
    val bg = when (palette) { "Blanco" -> Color.White; "Oscuro" -> Color(0xFF211D20); else -> paperReader }
    val fg = if (palette == "Oscuro") paperReader else Color(0xFF252125)
    LaunchedEffect(pdfUrl) {
        try {
            val result = withContext(Dispatchers.IO) {
                val dest = File(ctx.filesDir, "tesis_" + pdfUrl.hashCode().toUInt().toString() + ".pdf")
                if (!dest.exists() || dest.length() == 0L) {
                    val connection = URL(pdfUrl).openConnection() as HttpURLConnection
                    connection.connectTimeout = 20000
                    connection.readTimeout = 60000
                    connection.instanceFollowRedirects = true
                    try {
                        if (connection.responseCode !in 200..299) error("HTTP ${connection.responseCode}")
                        connection.inputStream.use { input -> dest.outputStream().use { input.copyTo(it) } }
                    } finally { connection.disconnect() }
                }
                PDFBoxResourceLoader.init(ctx.applicationContext)
                val count = PDDocument.load(dest).use { it.numberOfPages }
                dest to count
            }
            file = result.first
            pageCount = result.second
        } catch (e: Exception) { error = e.localizedMessage ?: "No se pudo descargar el PDF" }
    }
    LaunchedEffect(file, page, adaptive) {
        val source = file ?: return@LaunchedEffect
        try {
            if (adaptive) {
                text = withContext(Dispatchers.IO) {
                    PDDocument.load(source).use { doc ->
                        PDFTextStripper().apply { startPage = page; endPage = page; sortByPosition = true }.getText(doc)
                    }
                }
            } else {
                image = withContext(Dispatchers.IO) {
                    ParcelFileDescriptor.open(source, ParcelFileDescriptor.MODE_READ_ONLY).use { descriptor ->
                        PdfRenderer(descriptor).use { renderer ->
                            renderer.openPage(page - 1).use { pdfPage ->
                                val width = (pdfPage.width * 1.6).toInt().coerceAtLeast(1)
                                val height = (pdfPage.height * 1.6).toInt().coerceAtLeast(1)
                                Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888).also {
                                    it.eraseColor(android.graphics.Color.WHITE)
                                    pdfPage.render(it, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                                }
                            }
                        }
                    }
                }
            }
        } catch (e: Exception) { error = e.localizedMessage ?: "Error al leer la página" }
    }
    Column(Modifier.fillMaxSize().background(bg)) {
        Row(Modifier.fillMaxWidth().padding(8.dp), horizontalArrangement = Arrangement.SpaceBetween) {
            TextButton(onClick = onClose) { Text("← Volver", color = wineReader) }
            Text(title, modifier = Modifier.weight(1f).padding(8.dp), maxLines = 1, fontSize = 13.sp, color = fg)
            TextButton(onClick = { controls = !controls }) { Text("Aa", color = wineReader) }
        }
        Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            FilterChip(selected = adaptive, onClick = { adaptive = true }, label = { Text("Lectura adaptable") })
            FilterChip(selected = !adaptive, onClick = { adaptive = false }, label = { Text("PDF original") })
        }
        if (controls) {
            Text("Tamaño de letra: ${size.toInt()}", color = fg, modifier = Modifier.padding(horizontal = 16.dp))
            Slider(value = size, onValueChange = { size = it }, valueRange = 14f..36f, modifier = Modifier.padding(horizontal = 16.dp))
            Row(Modifier.padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                listOf("Blanco", "Papel", "Oscuro").forEach { choice ->
                    FilterChip(selected = palette == choice, onClick = { palette = choice }, label = { Text(choice) })
                }
            }
        }
        when {
            error != null -> Text("Error: $error", color = Color.Red, modifier = Modifier.padding(16.dp))
            file == null -> Box(Modifier.weight(1f)) { CircularProgressIndicator(Modifier.padding(30.dp)) }
            else -> {
                if (adaptive) {
                    if (text.isBlank()) {
                        Column(Modifier.weight(1f).padding(20.dp)) {
                            Text("No se ha podido extraer texto de esta página. Puede ser un escaneo.", color = fg)
                            Button(onClick = { adaptive = false }) { Text("Ver PDF original") }
                        }
                    } else {
                        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 22.dp, vertical = 16.dp)) {
                            Text(text.trim(), fontSize = size.sp, lineHeight = (size * 1.5f).sp, fontFamily = FontFamily.Serif, color = fg)
                        }
                    }
                } else {
                    val bitmap = image
                    if (bitmap != null) Image(bitmap.asImageBitmap(), contentDescription = "Página $page del PDF", contentScale = ContentScale.Fit, modifier = Modifier.weight(1f).fillMaxWidth())
                    else CircularProgressIndicator(Modifier.padding(24.dp))
                }
                Row(Modifier.fillMaxWidth().padding(12.dp), horizontalArrangement = Arrangement.SpaceBetween) {
                    TextButton(onClick = { page = (page - 1).coerceAtLeast(1) }, enabled = page > 1) { Text("Anterior") }
                    Text("$page / $pageCount", color = fg, modifier = Modifier.padding(12.dp))
                    TextButton(onClick = { page = (page + 1).coerceAtMost(pageCount) }, enabled = page < pageCount) { Text("Siguiente") }
                }
            }
        }
    }
}
