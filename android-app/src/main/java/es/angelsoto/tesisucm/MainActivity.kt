package es.angelsoto.tesisucm

import android.content.Intent
import android.graphics.pdf.PdfRenderer
import android.net.Uri
import android.os.Bundle
import android.os.ParcelFileDescriptor
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.text.Normalizer

private val burgundy = Color(0xFF681B35)
private val cream = Color(0xFFFFF9F0)
private data class Thesis(
    val id: String, val title: String, val authors: String, val directors: String,
    val summary: String, val subjects: String, val year: String, val pdf: String, val link: String
)
private fun JSONArray?.joined(): String = if (this == null) "" else (0 until length()).joinToString(", ") { optString(it) }
private fun normalized(s: String): String = Normalizer.normalize(s, Normalizer.Form.NFD).replace(Regex("\\p{M}+"), "").lowercase()
private fun loadCatalog(activity: ComponentActivity): List<Thesis> {
    val result = ArrayList<Thesis>(15419)
    for (chunk in 0 until 62) {
        val filename = "chunks/chunk_%04d.json".format(chunk)
        val data = activity.assets.open(filename).bufferedReader().use { it.readText() }
        val records = JSONArray(data)
        for (i in 0 until records.length()) {
            val j = records.getJSONObject(i)
            val date = j.optString("defense_date").ifBlank { j.optString("pub_date") }
            val year = Regex("(18|19|20)\\d{2}").find(date)?.value ?: ""
            result.add(Thesis(j.optString("_id", j.optString("id", "$chunk-$i")),
                j.optString("title"), j.optJSONArray("authors").joined(),
                j.optJSONArray("directors").joined(), j.optString("summary"),
                listOf(j.optJSONArray("subjects_ucm").joined(), j.optJSONArray("subjects_unesco").joined()).filter { it.isNotBlank() }.joinToString(", "),
                year, j.optString("pdf"), j.optString("link")))
        }
    }
    return result
}
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            var catalog by remember { mutableStateOf<List<Thesis>>(emptyList()) }
            var loading by remember { mutableStateOf(true) }
            var error by remember { mutableStateOf<String?>(null) }
            var query by remember { mutableStateOf("") }
            var year by remember { mutableStateOf("") }
            var selected by remember { mutableStateOf<Thesis?>(null) }
            var showHome by remember { mutableStateOf(true) }
            var reading by remember { mutableStateOf(false) }
            val context = LocalContext.current
            LaunchedEffect(Unit) {
                try { catalog = withContext(Dispatchers.IO) { loadCatalog(this@MainActivity) } }
                catch (e: Exception) { error = e.localizedMessage }
                finally { loading = false }
            }
            MaterialTheme(colorScheme = lightColorScheme(primary = burgundy, background = cream, surface = cream)) {
                if (reading && selected != null) {
                    ThesisReaderScreen(selected!!.pdf, selected!!.title, onClose = { reading = false })
                } else if (showHome) {
                    ThesisHomeScreen(catalog.size, onSearch = { query = it; showHome = false }, onShortcut = { action ->
                        query = when(action) { "recent" -> ""; else -> query }
                        showHome = false
                    })
                } else Column(Modifier.fillMaxSize().background(cream).padding(16.dp)) {
                    TextButton(onClick = { selected = null; showHome = true }) { Text("← Inicio") }
                    Text("TESIS UCM", style = MaterialTheme.typography.headlineMedium, color = burgundy, fontWeight = FontWeight.Bold)
                    Text("Biblioteca de tesis de la Universidad Complutense", color = burgundy)
                    Spacer(Modifier.height(12.dp))
                    if (selected == null) {
                        OutlinedTextField(query, { query = it }, label = { Text("Buscar título, autor, director o materia") }, modifier = Modifier.fillMaxWidth(), singleLine = true)
                        OutlinedTextField(year, { year = it.filter(Char::isDigit).take(4) }, label = { Text("Año (opcional)") }, modifier = Modifier.fillMaxWidth(), singleLine = true)
                        if (loading) CircularProgressIndicator() else if (error != null) Text("Error al cargar el catálogo: $error")
                        else {
                            val tokens = normalized(query.trim()).split(Regex("\\s+")).filter { it.isNotEmpty() }
                            val matches = remember(catalog, query, year) {
                                catalog.asSequence().filter { t ->
                                    (year.isBlank() || t.year == year) &&
                                    (tokens.isEmpty() || tokens.all { normalized(t.title + " " + t.authors + " " + t.directors + " " + t.subjects + " " + t.summary).contains(it) })
                                }.take(250).toList()
                            }
                            Text("${catalog.size} tesis · Mostrando ${matches.size} resultados (máximo 250)", color = burgundy)
                            LazyColumn(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                items(matches, key = { it.id }) { t ->
                                    Card(onClick = { selected = t }, modifier = Modifier.fillMaxWidth(), shape = RoundedCornerShape(12.dp)) {
                                        Column(Modifier.padding(14.dp)) {
                                            Text(t.title, fontWeight = FontWeight.Bold, color = burgundy)
                                            Text(t.authors, style = MaterialTheme.typography.bodySmall)
                                            if (t.year.isNotBlank()) Text(t.year, style = MaterialTheme.typography.labelMedium)
                                        }
                                    }
                                }
                            }
                        }
                    } else {
                        val t = selected!!
                        TextButton(onClick = { selected = null }) { Text("← Volver al catálogo") }
                        Text(t.title, style = MaterialTheme.typography.titleLarge, color = burgundy)
                        Text("Autores: ${t.authors}")
                        Text("Directores: ${t.directors}")
                        Text("Año: ${t.year}")
                        Text("Materias: ${t.subjects}")
                        Spacer(Modifier.height(12.dp))
                        Row {
                            Button(onClick = {
                                val url = t.pdf.takeIf { it.startsWith("https://") || it.startsWith("http://") }
                                if (url != null) reading = true
                            }, enabled = t.pdf.startsWith("http")) { Text("Leer tesis") }
                            Spacer(Modifier.width(8.dp))
                            OutlinedButton(onClick = {
                                val url = t.link.takeIf { it.startsWith("http") }
                                if (url != null) context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
                            }, enabled = t.link.startsWith("http")) { Text("Ficha UCM") }
                        }
                        Spacer(Modifier.height(12.dp))
                        Text("Resumen", fontWeight = FontWeight.Bold)
                        Column(Modifier.verticalScroll(rememberScrollState())) { Text(t.summary) }
                    }
                }
            }
        }
    }
}
