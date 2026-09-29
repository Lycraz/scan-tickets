package com.lemercier.scantickets.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.TableChart
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import com.lemercier.scantickets.ExcelExport
import com.lemercier.scantickets.Fmt
import com.lemercier.scantickets.NoteDeFrais
import com.lemercier.scantickets.Prefs
import com.lemercier.scantickets.Ticket
import com.lemercier.scantickets.TicketStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.time.LocalDate

private const val XLSX_MIME = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ExportScreen(store: TicketStore) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()

    var noteMode by rememberSaveable { mutableStateOf(Prefs.string(ctx, "exportMode") != "recap") }
    var week by rememberSaveable { mutableStateOf(store.weeks.firstOrNull() ?: "") }
    var month by rememberSaveable { mutableStateOf(store.months.firstOrNull() ?: "") }
    var feuilleMission by remember { mutableStateOf("") }
    var includePhotos by rememberSaveable { mutableStateOf(true) }
    var saveToFolder by rememberSaveable { mutableStateOf(true) }
    var working by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(week) {
        feuilleMission = Prefs.string(ctx, "fm_$week") ?: Prefs.string(ctx, "fm_last") ?: ""
    }

    val weekTickets = store.tickets.filter { it.weekKey == week }
    val monthTickets = store.tickets.filter { month.isEmpty() || it.monthKey == month }
    val selection = if (noteMode) weekTickets else monthTickets

    fun sortedForNote(list: List<Ticket>) = list.sortedWith(compareBy<Ticket> { it.date }.thenBy { it.createdAt })

    suspend fun exportNote(): List<File> = withContext(Dispatchers.IO) {
        val out = File(exportsDir(ctx), week).apply { deleteRecursively(); mkdirs() }
        val header = NoteDeFrais.Header(
            entite = Prefs.profile(ctx, "entite"),
            nom = Prefs.profile(ctx, "nom"),
            vehicule = Prefs.profile(ctx, "vehicule"),
            immatriculation = Prefs.profile(ctx, "immat"),
            feuilleMission = feuilleMission.trim(),
            cv = Prefs.profile(ctx, "cv", "5 cv"),
            moteur = Prefs.profile(ctx, "moteur", "Thermique"),
            date = LocalDate.now(),
        )
        val result = NoteDeFrais.build(ctx, week, weekTickets, header, out)
        val files = result.files.toMutableList()
        if (includePhotos) {
            // Justificatifs numérotés comme la colonne « Just » : 01_…, 02_…
            val multi = result.files.size > 1
            sortedForNote(weekTickets).forEachIndexed { i, t ->
                val src = store.imageFile(t)
                val n = result.numbers[t.id] ?: return@forEachIndexed
                if (!src.exists()) return@forEachIndexed
                val prefix = if (multi) "F${i / NoteDeFrais.CAPACITY + 1}-" else ""
                val dest = File(out, prefix + String.format("%02d_", n) + t.photoFileName)
                src.copyTo(dest, overwrite = true)
                files += dest
            }
        }
        files
    }

    suspend fun exportRecap(): List<File> = withContext(Dispatchers.IO) {
        val period = month.ifEmpty { "tout" }
        val out = File(exportsDir(ctx), "recap_$period").apply { deleteRecursively(); mkdirs() }
        val files = mutableListOf(ExcelExport.build(monthTickets, period, out))
        if (includePhotos) {
            monthTickets.forEach { t ->
                val src = store.imageFile(t)
                if (src.exists()) files += src.copyTo(File(out, t.photoFileName), overwrite = true)
            }
        }
        files
    }

    fun export() {
        scope.launch {
            working = true
            try {
                val files = if (noteMode) exportNote() else exportRecap()
                if (saveToFolder && store.folderName != null) {
                    var saved = 0
                    for (f in files) {
                        val mime = if (f.name.endsWith(".xlsx")) XLSX_MIME else "image/jpeg"
                        if (store.saveExportToFolder(f, mime, if (noteMode) week else null) != null) saved++
                    }
                    message = if (saved == files.size) "Fichiers enregistrés dans « ${store.folderName}/Exports »."
                    else store.lastFolderError ?: "Impossible d'écrire dans le dossier de sauvegarde."
                }
                shareFiles(ctx, files, if (noteMode) "Partager la note de frais" else "Partager le récapitulatif")
            } catch (e: Exception) {
                message = "Export impossible : ${e.message}"
            } finally {
                working = false
            }
        }
    }

    Scaffold(topBar = { TopAppBar(title = { Text("Export Excel", fontWeight = FontWeight.Bold) }) }) { padding ->
        Column(
            Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState()).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                FilterChip(selected = noteMode, onClick = { noteMode = true; Prefs.setString(ctx, "exportMode", "note") },
                    label = { Text("Note de frais") })
                FilterChip(selected = !noteMode, onClick = { noteMode = false; Prefs.setString(ctx, "exportMode", "recap") },
                    label = { Text("Récapitulatif") })
            }

            Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainer)) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    if (noteMode) {
                        Text("Note de frais (modèle)", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                        if (store.weeks.isEmpty()) {
                            Text("Aucun ticket pour l'instant.")
                        } else {
                            SelectField("Semaine", week, store.weeks, Modifier.fillMaxWidth(), display = { Fmt.weekTitle(it) }) { week = it }
                        }
                        OutlinedTextField(
                            feuilleMission,
                            { v ->
                                feuilleMission = v.uppercase()
                                Prefs.setString(ctx, "fm_$week", feuilleMission)
                                Prefs.setString(ctx, "fm_last", feuilleMission)
                            },
                            label = { Text("N° feuille de mission (ex. FM002158)") },
                            keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Characters),
                            singleLine = true, modifier = Modifier.fillMaxWidth(),
                        )
                        Info("Lignes", "${weekTickets.size}")
                        Info("Total", Fmt.money(weekTickets.sumOf { it.ttc ?: 0.0 }))
                        val km = weekTickets.sumOf { it.km ?: 0.0 }
                        if (km > 0) Info("Kilomètres", "${Fmt.kmString(km)} km")
                        if (weekTickets.size > NoteDeFrais.CAPACITY) {
                            Hint("Plus de ${NoteDeFrais.CAPACITY} lignes : la note sera répartie sur plusieurs fichiers.")
                        }
                        if (weekTickets.any { it.aVerifier }) Hint("Certains tickets sont encore « à vérifier ».", warn = true)
                        if (!NoteDeFrais.hasTemplate(ctx)) {
                            Hint("Importez d'abord votre modèle Excel dans Réglages › Note de frais › Modèle Excel.", warn = true)
                        }
                        if (Prefs.profile(ctx, "nom").isEmpty()) {
                            Hint("Renseignez votre nom dans Réglages › Profil pour remplir l'en-tête.", warn = true)
                        }
                        Hint("Remplit votre modèle Excel : en-tête, une ligne par justificatif, colonnes selon la nature, kilomètres et totaux.")
                    } else {
                        Text("Récapitulatif", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                        SelectField("Mois", month, listOf("") + store.months, Modifier.fillMaxWidth(),
                            display = { if (it.isEmpty()) "Tous les mois" else Fmt.monthTitle(it) }) { month = it }
                        Info("Tickets", "${monthTickets.size}")
                        Info("Total TTC", Fmt.money(monthTickets.sumOf { it.ttc ?: 0.0 }))
                    }
                }
            }

            Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainer)) {
                Column(Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) {
                    SwitchRow(if (noteMode) "Joindre les justificatifs numérotés" else "Joindre les photos des tickets", includePhotos) { includePhotos = it }
                    if (store.folderName != null) {
                        SwitchRow("Enregistrer aussi dans « ${store.folderName} »", saveToFolder) { saveToFolder = it }
                    }
                }
            }

            Button(
                onClick = { export() },
                enabled = selection.isNotEmpty() && !working,
                modifier = Modifier.fillMaxWidth().height(52.dp),
            ) {
                if (working) {
                    CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
                } else {
                    Icon(Icons.Filled.TableChart, null)
                    Spacer(Modifier.width(8.dp))
                    Text(if (noteMode) "Créer la note de frais" else "Créer le récapitulatif", fontWeight = FontWeight.Bold)
                }
            }
            Text(
                "Une fois créés, les fichiers s'ouvrent dans le menu de partage : Drive, Gmail, « Enregistrer dans Fichiers »…",
                style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }

    message?.let {
        AlertDialog(
            onDismissRequest = { message = null },
            text = { Text(it) },
            confirmButton = { TextButton(onClick = { message = null }) { Text("OK") } },
        )
    }
}

@Composable
private fun Info(label: String, value: String) {
    Row(Modifier.fillMaxWidth()) {
        Text(label, modifier = Modifier.weight(1f))
        Text(value, fontWeight = FontWeight.SemiBold)
    }
}

@Composable
private fun Hint(text: String, warn: Boolean = false) {
    Text(text, style = MaterialTheme.typography.bodySmall,
        color = if (warn) Warning else MaterialTheme.colorScheme.onSurfaceVariant)
}

@Composable
fun SwitchRow(label: String, checked: Boolean, onChange: (Boolean) -> Unit) {
    Row(Modifier.fillMaxWidth().padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(label, modifier = Modifier.weight(1f))
        Switch(checked = checked, onCheckedChange = onChange)
    }
}
