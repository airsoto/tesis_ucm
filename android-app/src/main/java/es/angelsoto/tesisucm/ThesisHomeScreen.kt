package es.angelsoto.tesisucm

import android.graphics.BitmapFactory
import android.webkit.WebView
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView

private val wine = Color(0xFF741D37)
private val paper = Color(0xFFF9F3E8)
private val ink = Color(0xFF282324)

@Composable
private fun AssetPhoto(name: String, modifier: Modifier = Modifier, scale: ContentScale = ContentScale.Crop) {
    val ctx = LocalContext.current
    val bitmap = remember(name) {
        runCatching { ctx.assets.open(name).use { BitmapFactory.decodeStream(it) } }.getOrNull()
    }
    if (bitmap != null) Image(bitmap.asImageBitmap(), contentDescription = null, contentScale = scale, modifier = modifier)
}

@Composable
private fun HomeTile(label: String, symbol: ImageVector, tint: Color, fill: Color, modifier: Modifier = Modifier, onClick: () -> Unit) {
    Surface(
        modifier = modifier.heightIn(min = 116.dp).clickable(onClick = onClick),
        shape = RoundedCornerShape(20.dp),
        color = fill,
        shadowElevation = 5.dp,
        border = androidx.compose.foundation.BorderStroke(1.dp, Color.White)
    ) {
        Column(
            Modifier.padding(horizontal = 5.dp, vertical = 12.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center
        ) {
            Icon(symbol, contentDescription = null, tint = tint, modifier = Modifier.size(30.dp))
            Spacer(Modifier.height(8.dp))
            Text(label, fontWeight = FontWeight.Bold, fontSize = 15.sp, lineHeight = 19.sp, color = ink, textAlign = TextAlign.Center)
        }
    }
}

/** Android home layout based on the original SwiftUI CatalogHomeView and shared UCM assets. */
@Composable
fun ThesisHomeScreen(total: Int, onSearch: (String) -> Unit, onShortcut: (String) -> Unit) {
    var search by remember { mutableStateOf("") }
    Column(Modifier.fillMaxSize().background(paper)) {
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState())) {
            Box(Modifier.fillMaxWidth().height(225.dp)) {
                AndroidView(
                    factory = { ctx -> WebView(ctx).apply {
                        setBackgroundColor(android.graphics.Color.TRANSPARENT)
                        isVerticalScrollBarEnabled = false
                        isHorizontalScrollBarEnabled = false
                        loadUrl("file:///android_asset/library.svg")
                    } },
                    modifier = Modifier.fillMaxSize()
                )
                Row(Modifier.align(Alignment.TopStart).padding(start = 16.dp, top = 30.dp, end = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                    AssetPhoto("FEUCM.jpg", Modifier.width(70.dp).height(84.dp), ContentScale.Fit)
                    Spacer(Modifier.width(12.dp))
                    Column {
                        Text("Tesis UCM", color = Color(0xFF981536), fontWeight = FontWeight.Bold, fontSize = 29.sp)
                        Text("Universidad Complutense\nde Madrid", color = ink, fontWeight = FontWeight.Medium, fontSize = 14.sp, lineHeight = 18.sp)
                    }
                }
                Box(Modifier.fillMaxWidth().height(13.dp).align(Alignment.BottomCenter).background(wine))
            }
            Spacer(Modifier.height(20.dp))
            Text("Catálogo de tesis doctorales", modifier = Modifier.fillMaxWidth().padding(horizontal = 10.dp), textAlign = TextAlign.Center, color = ink, fontWeight = FontWeight.Bold, fontSize = 23.sp)
            Spacer(Modifier.height(6.dp))
            Text("${if (total > 0) String.format("%,d", total).replace(',', '.') else "15.419"} tesis para explorar, buscar\ny consultar.",
                modifier = Modifier.fillMaxWidth(), textAlign = TextAlign.Center, color = Color.Gray, fontSize = 19.sp, lineHeight = 24.sp)
            Spacer(Modifier.height(24.dp))
            OutlinedTextField(
                value = search, onValueChange = { search = it },
                placeholder = { Text("Buscar tesis, autor, director…", maxLines = 1) },
                trailingIcon = { IconButton(onClick = { onSearch(search) }) { Icon(Icons.Default.Search, contentDescription = "Buscar", tint = wine) } },
                singleLine = true, modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
                shape = RoundedCornerShape(18.dp),
                colors = OutlinedTextFieldDefaults.colors(focusedContainerColor = Color.White, unfocusedContainerColor = Color.White)
            )
            Spacer(Modifier.height(18.dp))
            Column(Modifier.padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    HomeTile("Búsqueda\navanzada", Icons.Default.Tune, wine, Color(0xFFF8E2E6), Modifier.weight(1f)) { onShortcut("advanced") }
                    HomeTile("Explorar\npor materias", Icons.Default.Layers, Color(0xFF214F87), Color(0xFFE8EFFC), Modifier.weight(1f)) { onShortcut("subjects") }
                    HomeTile("Facultades\ny centros", Icons.Default.AccountBalance, Color(0xFF825116), Color(0xFFFBECD4), Modifier.weight(1f)) { onShortcut("centres") }
                }
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    HomeTile("Tesis\nrecientes", Icons.Default.Schedule, Color(0xFF35582A), Color(0xFFE7EFDE), Modifier.weight(1f)) { onShortcut("recent") }
                    HomeTile("Mis\ndescargas", Icons.Default.Download, Color(0xFF663D95), Color(0xFFF0E7FA), Modifier.weight(1f)) { onShortcut("downloads") }
                    HomeTile("Mis\nfavoritas", Icons.Default.Star, Color(0xFF825116), Color(0xFFFFF1D3), Modifier.weight(1f)) { onShortcut("favorites") }
                }
            }
            Spacer(Modifier.height(24.dp))
            AssetPhoto("HomeBooks.jpg", Modifier.fillMaxWidth().height(180.dp))
        }
        NavigationBar(containerColor = paper) {
            listOf(
                Triple("Inicio", Icons.Default.Home, "home"),
                Triple("Buscar", Icons.Default.Search, "search"),
                Triple("Biblioteca", Icons.Default.MenuBook, "library"),
                Triple("Descargas", Icons.Default.Download, "downloads"),
                Triple("Ajustes", Icons.Default.Settings, "settings")
            ).forEach { (label, icon, action) ->
                NavigationBarItem(selected = action == "home", onClick = { onShortcut(action) }, icon = { Icon(icon, contentDescription = null) }, label = { Text(label, fontSize = 10.sp) }, colors = NavigationBarItemDefaults.colors(selectedIconColor = wine, selectedTextColor = wine))
            }
        }
    }
}
