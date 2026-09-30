package com.lemercier.scantickets.ui

import android.app.DatePickerDialog
import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.Context
import android.content.Intent
import androidx.compose.foundation.clickable
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.core.content.FileProvider
import java.io.File
import java.time.LocalDate

val Indigo = Color(0xFF4F46E5)
val IndigoDark = Color(0xFF4338CA)
val Warning = Color(0xFFD97706)

@Composable
fun ScanTicketsTheme(content: @Composable () -> Unit) {
    val scheme = if (isSystemInDarkTheme()) {
        darkColorScheme(
            primary = Color(0xFF818CF8), onPrimary = Color(0xFF0F1020),
            primaryContainer = Color(0xFF2B2F5C), onPrimaryContainer = Color(0xFFE0E7FF),
            background = Color(0xFF0F1020), surface = Color(0xFF0F1020),
            surfaceContainer = Color(0xFF1A1C30), surfaceContainerHigh = Color(0xFF24273F),
        )
    } else {
        lightColorScheme(
            primary = Indigo, onPrimary = Color.White,
            primaryContainer = Color(0xFFE0E7FF), onPrimaryContainer = Color(0xFF1E1B4B),
            background = Color(0xFFF5F6FB), surface = Color(0xFFF5F6FB),
            surfaceContainer = Color.White, surfaceContainerHigh = Color(0xFFEEF0F8),
        )
    }
    MaterialTheme(colorScheme = scheme, content = content)
}

/** Champ à choix (liste déroulante) */
@Composable
fun SelectField(
    label: String,
    value: String,
    options: List<String>,
    modifier: Modifier = Modifier,
    display: (String) -> String = { it.ifEmpty { "—" } },
    onSelect: (String) -> Unit,
) {
    var open by remember { mutableStateOf(false) }
    Box(modifier) {
        OutlinedTextField(
            value = display(value), onValueChange = {}, readOnly = true,
            label = { Text(label) },
            trailingIcon = { Icon(Icons.Filled.ArrowDropDown, null) },
            modifier = Modifier.fillMaxWidth(),
        )
        Box(Modifier.matchParentSize().clickable { open = true })
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            options.forEach { o ->
                DropdownMenuItem(text = { Text(display(o)) }, onClick = { onSelect(o); open = false })
            }
        }
    }
}

@Composable
fun SectionTitle(text: String) {
    Text(
        text.uppercase(),
        style = MaterialTheme.typography.labelMedium,
        fontWeight = FontWeight.SemiBold,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(start = 4.dp, top = 16.dp, bottom = 6.dp),
    )
}

fun pickDate(ctx: Context, current: LocalDate, onPick: (LocalDate) -> Unit) {
    DatePickerDialog(ctx, { _, y, m, d -> onPick(LocalDate.of(y, m + 1, d)) },
        current.year, current.monthValue - 1, current.dayOfMonth).show()
}

/** Dossier des fichiers à partager (déclaré dans res/xml/file_paths.xml) */
fun exportsDir(ctx: Context): File = File(ctx.cacheDir, "exports").apply { mkdirs() }

/** Ouvre la feuille de partage Android (Drive, Gmail, enregistrer…) */
private const val XLSX_TYPE = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"

private fun mimeOf(f: File) = if (f.name.endsWith(".xlsx")) XLSX_TYPE else "image/jpeg"

/** Ouvre un fichier dans l'app par défaut (Excel, Sheets…). Renvoie false si aucune app ne sait l'ouvrir. */
fun openFile(ctx: Context, file: File): Boolean {
    val uri = FileProvider.getUriForFile(ctx, ctx.packageName + ".fileprovider", file)
    val intent = Intent(Intent.ACTION_VIEW).apply {
        setDataAndType(uri, mimeOf(file))
        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }
    return try {
        ctx.startActivity(intent)
        true
    } catch (e: ActivityNotFoundException) {
        false
    }
}

fun shareFiles(ctx: Context, files: List<File>, title: String) {
    if (files.isEmpty()) return
    val auth = ctx.packageName + ".fileprovider"
    val uris = ArrayList(files.map { FileProvider.getUriForFile(ctx, auth, it) })
    val types = files.map { mimeOf(it) }.distinct()
    val intent = if (uris.size == 1) {
        Intent(Intent.ACTION_SEND).apply {
            type = types[0]
            putExtra(Intent.EXTRA_STREAM, uris[0])
        }
    } else {
        Intent(Intent.ACTION_SEND_MULTIPLE).apply {
            type = if (types.size == 1) types[0] else "*/*"
            putParcelableArrayListExtra(Intent.EXTRA_STREAM, uris)
        }
    }
    intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    intent.clipData = ClipData.newRawUri(files[0].name, uris[0]).apply {
        uris.drop(1).forEach { addItem(ClipData.Item(it)) }
    }
    ctx.startActivity(Intent.createChooser(intent, title))
}
