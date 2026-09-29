package com.lemercier.scantickets.ui

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.DocumentScanner
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.KeyboardCapitalization
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.lemercier.scantickets.Analyzer
import com.lemercier.scantickets.Catalog
import com.lemercier.scantickets.EditorRequest
import com.lemercier.scantickets.Fmt
import com.lemercier.scantickets.ListKind
import com.lemercier.scantickets.Prefs
import com.lemercier.scantickets.TicketStore
import kotlinx.coroutines.launch

/** Fiche d'un ticket (création ou modification), en plein écran */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun EditorDialog(store: TicketStore, req: EditorRequest, onClose: (saved: Boolean) -> Unit) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()

    var draft by remember { mutableStateOf(req.ticket) }
    var ttcText by remember { mutableStateOf(Fmt.amountString(req.ticket.ttc)) }
    var tvaText by remember { mutableStateOf(Fmt.amountString(req.ticket.tva)) }
    var htText by remember { mutableStateOf(Fmt.amountString(req.ticket.ht)) }
    var kmText by remember { mutableStateOf(req.ticket.km?.let { Fmt.kmString(it) } ?: "") }
    var analyzing by remember { mutableStateOf(false) }
    var status by remember { mutableStateOf("Lecture du ticket…") }
    var note by remember { mutableStateOf<String?>(null) }
    var noteWarn by remember { mutableStateOf(false) }
    var showPhoto by remember { mutableStateOf(false) }
    var confirmDelete by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    fun autoHT() {
        val ttc = Fmt.parseAmount(ttcText)
        val tva = Fmt.parseAmount(tvaText)
        if (ttc != null && tva != null) htText = Fmt.amountString(Fmt.round2(ttc - tva))
    }

    suspend fun analyze() {
        val image = req.image ?: return
        analyzing = true
        try {
            val result = Analyzer.run(ctx, image) { status = it }
            if (result == null) {
                note = "Saisie manuelle : complétez les champs."; noteWarn = false
            } else {
                draft = result.applyTo(draft)
                ttcText = Fmt.amountString(draft.ttc)
                tvaText = Fmt.amountString(draft.tva)
                htText = Fmt.amountString(draft.ht)
                val low = result.confiance == "basse"
                noteWarn = low || result.warning != null
                note = result.warning ?: ("Lu par ${result.source}" +
                    if (low) " — vérifiez bien les montants." else ". Vérifiez puis enregistrez.")
            }
        } catch (e: Exception) {
            noteWarn = true
            note = "Lecture impossible : ${e.message}. Complétez à la main."
        } finally {
            analyzing = false
        }
    }

    fun save() {
        var t = draft.copy(devise = draft.devise.trim().uppercase().ifEmpty { "EUR" })
        if (t.isKilometres) {
            val km = Fmt.parseAmount(kmText)
            if (km == null || km <= 0) { error = "Indiquez le nombre de kilomètres."; return }
            t = t.copy(km = km, ttc = null, tva = null, ht = null,
                commercant = t.commercant.ifBlank { "Véhicule personnel" })
        } else {
            t = t.copy(
                commercant = t.commercant.trim(),
                ttc = Fmt.parseAmount(ttcText), tva = Fmt.parseAmount(tvaText), ht = Fmt.parseAmount(htText),
            )
            if (t.commercant.isEmpty()) { error = "Indiquez le commerçant."; return }
            if (t.ttc == null) { error = "Indiquez le montant TTC."; return }
        }
        t = t.copy(aVerifier = false)
        Prefs.setLast(ctx, ListKind.AFFAIRE, t.affaire)
        Prefs.setLast(ctx, ListKind.LIEU, t.lieu)
        Prefs.setLast(ctx, ListKind.PARTENAIRE, t.partenaire)
        Prefs.setLast(ctx, ListKind.RAISON, t.raison)
        scope.launch {
            store.save(t, if (req.isNew) req.image else null)
            onClose(true)
        }
    }

    LaunchedEffect(Unit) { if (req.autoAnalyze) analyze() }

    Dialog(
        onDismissRequest = { if (!analyzing) onClose(false) },
        properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false),
    ) {
        Scaffold(
            topBar = {
                TopAppBar(
                    title = {
                        Text(
                            when {
                                draft.isKilometres && req.isNew -> "Nouveau trajet"
                                draft.isKilometres -> "Modifier le trajet"
                                req.isNew -> "Nouveau ticket"
                                else -> "Modifier"
                            },
                        )
                    },
                    navigationIcon = { IconButton(onClick = { onClose(false) }) { Icon(Icons.Filled.Close, "Annuler") } },
                    actions = {
                        TextButton(onClick = { save() }, enabled = !analyzing) {
                            Text("Enregistrer", fontWeight = FontWeight.Bold)
                        }
                    },
                )
            },
        ) { padding ->
            Column(
                Modifier.fillMaxSize().padding(padding).imePadding().verticalScroll(rememberScrollState())
                    .padding(horizontal = 16.dp, vertical = 8.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                req.image?.let { img ->
                    Box(
                        Modifier.fillMaxWidth().heightIn(max = 260.dp).clip(RoundedCornerShape(14.dp))
                            .background(MaterialTheme.colorScheme.surfaceContainerHigh),
                        contentAlignment = Alignment.Center,
                    ) {
                        Image(img.asImageBitmap(), "Photo du ticket", contentScale = ContentScale.Fit,
                            modifier = Modifier.fillMaxWidth().heightIn(max = 260.dp).clickable { showPhoto = true })
                        if (analyzing) {
                            Box(Modifier.matchParentSize().background(Color.Black.copy(alpha = 0.55f)), contentAlignment = Alignment.Center) {
                                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                                    CircularProgressIndicator(color = Color.White)
                                    Spacer(Modifier.height(10.dp))
                                    Text(status, color = Color.White, fontWeight = FontWeight.SemiBold)
                                }
                            }
                        }
                    }
                }
                note?.let {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(if (noteWarn) Icons.Filled.Warning else Icons.Filled.CheckCircle, null,
                            tint = if (noteWarn) Warning else Color(0xFF059669))
                        Spacer(Modifier.padding(4.dp))
                        Text(it, style = MaterialTheme.typography.bodySmall)
                    }
                }

                if (draft.isKilometres) {
                    SectionTitle("Trajet en véhicule personnel")
                    DateField(draft.date) { draft = draft.copy(date = it) }
                    OutlinedTextField(
                        kmText, { kmText = it }, label = { Text("Distance (km)") },
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                        singleLine = true, modifier = Modifier.fillMaxWidth(),
                    )
                    OutlinedTextField(
                        draft.description, { draft = draft.copy(description = it) },
                        label = { Text("Trajet (ex. Nantes → Rennes)") }, singleLine = true, modifier = Modifier.fillMaxWidth(),
                    )
                    Text("Le montant est calculé dans la note de frais selon le barème (CV et moteur réglés dans Réglages › Profil).",
                        style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                } else {
                    SectionTitle("Ticket")
                    OutlinedTextField(
                        draft.commercant, { draft = draft.copy(commercant = it) }, label = { Text("Commerçant") },
                        keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Words),
                        singleLine = true, modifier = Modifier.fillMaxWidth(),
                    )
                    DateField(draft.date) { draft = draft.copy(date = it) }
                    SelectField("Nature", draft.nature, Catalog.natures, Modifier.fillMaxWidth()) { draft = draft.copy(nature = it) }

                    SectionTitle("Montants")
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        AmountField("Montant TTC", ttcText, Modifier.weight(1f)) { ttcText = it; autoHT() }
                        OutlinedTextField(
                            draft.devise, { draft = draft.copy(devise = it.take(3).uppercase()) }, label = { Text("Devise") },
                            singleLine = true, modifier = Modifier.weight(0.5f),
                        )
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        AmountField("TVA", tvaText, Modifier.weight(1f)) { tvaText = it; autoHT() }
                        AmountField("Montant HT", htText, Modifier.weight(1f)) { htText = it }
                    }

                    SectionTitle("Détails")
                    SelectField("Paiement", draft.paiement, listOf("") + Catalog.paiements, Modifier.fillMaxWidth()) {
                        draft = draft.copy(paiement = it)
                    }
                    OutlinedTextField(
                        draft.description, { draft = draft.copy(description = it) },
                        label = { Text("Description (ex. Déjeuner client)") }, singleLine = true, modifier = Modifier.fillMaxWidth(),
                    )
                    if (draft.nature == "Restaurant") {
                        OutlinedTextField(
                            draft.invites, { draft = draft.copy(invites = it) },
                            label = { Text("Personnes invitées (ex. Mickael Le Fur)") },
                            keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Words),
                            singleLine = true, modifier = Modifier.fillMaxWidth(),
                        )
                    }
                }

                SectionTitle("Note de frais")
                ListField(ListKind.AFFAIRE, draft.affaire) { draft = draft.copy(affaire = it) }
                ListField(ListKind.LIEU, draft.lieu) { draft = draft.copy(lieu = it) }
                ListField(ListKind.PARTENAIRE, draft.partenaire) { draft = draft.copy(partenaire = it) }
                ListField(ListKind.RAISON, draft.raison) { draft = draft.copy(raison = it) }
                OutlinedTextField(
                    draft.notes, { draft = draft.copy(notes = it) }, label = { Text("Notes") },
                    minLines = 2, modifier = Modifier.fillMaxWidth(),
                )
                Text("Les listes se modifient dans Réglages › Listes de la note de frais.",
                    style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)

                Row(horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.padding(vertical = 12.dp)) {
                    if (req.image != null) {
                        OutlinedButton(onClick = { scope.launch { analyze() } }, enabled = !analyzing) {
                            Icon(Icons.Filled.DocumentScanner, null); Spacer(Modifier.padding(3.dp)); Text("Relire le ticket")
                        }
                    }
                    if (!req.isNew) {
                        OutlinedButton(onClick = { confirmDelete = true }) {
                            Icon(Icons.Filled.Delete, null, tint = MaterialTheme.colorScheme.error)
                            Spacer(Modifier.padding(3.dp))
                            Text("Supprimer", color = MaterialTheme.colorScheme.error)
                        }
                    }
                }
            }
        }

        if (showPhoto && req.image != null) {
            Dialog(onDismissRequest = { showPhoto = false }, properties = DialogProperties(usePlatformDefaultWidth = false)) {
                Box(Modifier.fillMaxSize().background(Color.Black).clickable { showPhoto = false }, contentAlignment = Alignment.Center) {
                    Image(req.image.asImageBitmap(), null, contentScale = ContentScale.Fit, modifier = Modifier.fillMaxSize())
                }
            }
        }
        if (confirmDelete) {
            AlertDialog(
                onDismissRequest = { confirmDelete = false },
                title = { Text("Supprimer ce ticket ?") },
                confirmButton = {
                    TextButton(onClick = {
                        confirmDelete = false
                        scope.launch { store.delete(draft); onClose(false) }
                    }) { Text("Supprimer", color = MaterialTheme.colorScheme.error) }
                },
                dismissButton = { TextButton(onClick = { confirmDelete = false }) { Text("Annuler") } },
            )
        }
        error?.let {
            AlertDialog(
                onDismissRequest = { error = null },
                title = { Text("Information manquante") },
                text = { Text(it) },
                confirmButton = { TextButton(onClick = { error = null }) { Text("OK") } },
            )
        }
    }
}

@Composable
private fun AmountField(label: String, value: String, modifier: Modifier, onChange: (String) -> Unit) {
    OutlinedTextField(
        value, onChange, label = { Text(label) }, suffix = { Text("€") },
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
        singleLine = true, modifier = modifier,
    )
}

@Composable
fun DateField(date: java.time.LocalDate, onPick: (java.time.LocalDate) -> Unit) {
    val ctx = LocalContext.current
    Box {
        OutlinedTextField(
            Fmt.longDay(date), {}, readOnly = true, label = { Text("Date") },
            trailingIcon = { Icon(Icons.Filled.CalendarMonth, null) }, modifier = Modifier.fillMaxWidth(),
        )
        Box(Modifier.matchParentSize().clickable { pickDate(ctx, date, onPick) })
    }
}

@Composable
private fun ListField(kind: ListKind, value: String, onSelect: (String) -> Unit) {
    val ctx = LocalContext.current
    val options = remember(kind) { Prefs.list(ctx, kind) }
    val all = listOf("") + options + (if (value.isNotEmpty() && value !in options) listOf(value) else emptyList())
    SelectField(kind.title, value, all, Modifier.fillMaxWidth(), onSelect = onSelect)
}
