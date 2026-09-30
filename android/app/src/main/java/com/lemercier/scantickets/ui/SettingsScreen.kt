package com.lemercier.scantickets.ui

import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
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
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
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
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import com.lemercier.scantickets.ClaudeClient
import com.lemercier.scantickets.ListKind
import com.lemercier.scantickets.NoteDeFrais
import com.lemercier.scantickets.Prefs
import com.lemercier.scantickets.TicketStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** Réglages, avec des sous-pages (profil, listes, modèle Excel) */
@Composable
fun SettingsScreen(store: TicketStore) {
    var page by rememberSaveable { mutableStateOf("main") }
    BackHandler(enabled = page != "main") {
        page = if (page.startsWith("list_")) "lists" else "main"
    }
    when {
        page == "profile" -> ProfilePage { page = "main" }
        page == "lists" -> ListsPage(onBack = { page = "main" }, onOpen = { page = "list_" + it.name })
        page.startsWith("list_") -> ListEditorPage(ListKind.valueOf(page.removePrefix("list_"))) { page = "lists" }
        page == "template" -> TemplatePage { page = "main" }
        else -> MainSettings(store) { page = it }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun Page(title: String, onBack: (() -> Unit)?, content: @Composable ColumnScope.() -> Unit) {
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(title, fontWeight = FontWeight.Bold) },
                navigationIcon = {
                    if (onBack != null) IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Retour") }
                },
            )
        },
    ) { padding ->
        Column(
            Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState()).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
            content = content,
        )
    }
}

@Composable
private fun Group(content: @Composable ColumnScope.() -> Unit) {
    Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainer)) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp), content = content)
    }
}

@Composable
private fun NavRow(title: String, detail: String? = null, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().clickable(onClick = onClick).padding(vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(title, modifier = Modifier.weight(1f))
        if (detail != null) Text(detail, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Icon(Icons.Filled.ChevronRight, null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun Footer(text: String) {
    Text(text, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
}

// ---------- Page principale ----------

@Composable
private fun MainSettings(store: TicketStore, open: (String) -> Unit) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    var engine by remember { mutableStateOf(Prefs.engine(ctx)) }
    var apiKey by remember { mutableStateOf(Prefs.apiKey(ctx)) }
    var model by remember { mutableStateOf(Prefs.model(ctx)) }
    var models by remember { mutableStateOf<List<ClaudeClient.ModelInfo>>(emptyList()) }
    var keyStatus by remember { mutableStateOf<String?>(null) }
    var testing by remember { mutableStateOf(false) }
    var info by remember { mutableStateOf<String?>(null) }

    val folderLauncher = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocumentTree()) { uri ->
        if (uri != null) {
            store.setFolder(uri)
            if (store.lastFolderError == null && store.tickets.isNotEmpty()) {
                scope.launch { info = "Dossier enregistré. ${store.syncAllPhotos()} photo(s) copiée(s)." }
            }
        }
    }

    val engines = listOf("auto", "claude", "local", "none")
    val engineLabels = mapOf(
        "auto" to "Automatique", "claude" to "IA Claude uniquement",
        "local" to "Sur le téléphone (gratuit)", "none" to "Saisie manuelle",
    )

    Page("Réglages", null) {
        SectionTitle("Lecture des tickets")
        Group {
            SelectField("Moteur", engine, engines, Modifier.fillMaxWidth(), display = { engineLabels[it] ?: it }) {
                engine = it; Prefs.setEngine(ctx, it)
            }
            OutlinedTextField(
                apiKey, { apiKey = it.trim(); Prefs.setApiKey(ctx, apiKey) },
                label = { Text("Clé API Anthropic (sk-ant-…)") },
                visualTransformation = PasswordVisualTransformation(),
                singleLine = true, modifier = Modifier.fillMaxWidth(),
            )
            SelectField("Modèle", model, if (models.isEmpty()) listOf(model) else models.map { it.id }, Modifier.fillMaxWidth(),
                display = { id -> models.firstOrNull { it.id == id }?.name ?: id }) {
                model = it; Prefs.setModel(ctx, it)
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                OutlinedButton(enabled = !testing, onClick = {
                    scope.launch {
                        testing = true
                        keyStatus = try {
                            val list = ClaudeClient.listModels(apiKey).filter { "claude" in it.id }
                            models = list
                            if (list.none { it.id == model }) {
                                (list.firstOrNull { "sonnet" in it.id } ?: list.firstOrNull())?.let { model = it.id; Prefs.setModel(ctx, it.id) }
                            }
                            "✓ Clé valide"
                        } catch (e: Exception) {
                            "✗ ${e.message}"
                        }
                        testing = false
                    }
                }) { Text("Tester la clé") }
                Spacer(Modifier.width(12.dp))
                if (testing) CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
                keyStatus?.let { Text(it, style = MaterialTheme.typography.bodySmall) }
            }
        }
        Footer("« Automatique » utilise l'IA si une clé est enregistrée, sinon la lecture gratuite du téléphone. Créez la clé sur console.anthropic.com et fixez-y une limite de dépense.")

        SectionTitle("Dossier de sauvegarde")
        Group {
            val name = store.folderName
            if (name != null) {
                Row { Text("Dossier", Modifier.weight(1f)); Text(name, fontWeight = FontWeight.SemiBold) }
                HorizontalDivider()
                NavRow("Recopier toutes les photos maintenant") {
                    scope.launch { info = store.lastFolderError ?: "${store.syncAllPhotos()} photo(s) copiée(s)." }
                }
                NavRow("Changer de dossier") { folderLauncher.launch(null) }
                TextButton(onClick = { store.clearFolder() }) {
                    Text("Ne plus utiliser de dossier", color = MaterialTheme.colorScheme.error)
                }
            } else {
                NavRow("Choisir un dossier") { folderLauncher.launch(null) }
            }
            store.lastFolderError?.let { Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall) }
        }
        Footer("Chaque ticket enregistré y est copié automatiquement (Photos/AAAA-MM/…), ainsi que les exports Excel.")

        SectionTitle("Note de frais")
        Group {
            NavRow("Profil (en-tête de la note)") { open("profile") }
            HorizontalDivider()
            NavRow("Listes (affaires, lieux…)") { open("lists") }
            HorizontalDivider()
            NavRow("Modèle Excel") { open("template") }
        }

        SectionTitle("À propos")
        Group {
            Row { Text("Tickets enregistrés", Modifier.weight(1f)); Text("${store.tickets.size}") }
            Row { Text("Version", Modifier.weight(1f)); Text("1.0") }
        }
    }

    info?.let {
        AlertDialog(onDismissRequest = { info = null }, text = { Text(it) },
            confirmButton = { TextButton(onClick = { info = null }) { Text("OK") } })
    }
}

// ---------- Profil ----------

@Composable
private fun ProfilePage(onBack: () -> Unit) {
    val ctx = LocalContext.current
    Page("Profil", onBack) {
        SectionTitle("Salarié")
        Group {
            ProfileField("nom", "Nom Prénom (ex. LEMERCIER Fabien)", KeyboardCapitalization.Characters)
            ProfileField("entite", "Entité (ex. CUP)", KeyboardCapitalization.Characters)
        }
        SectionTitle("Véhicule personnel")
        Group {
            ProfileField("vehicule", "Véhicule", KeyboardCapitalization.Words)
            ProfileField("immat", "Immatriculation", KeyboardCapitalization.Characters)
            var cv by remember { mutableStateOf(Prefs.profile(ctx, "cv", "5 cv")) }
            SelectField("Puissance fiscale", cv, NoteDeFrais.cvOptions, Modifier.fillMaxWidth()) { cv = it; Prefs.setProfile(ctx, "cv", it) }
            var moteur by remember { mutableStateOf(Prefs.profile(ctx, "moteur", "Thermique")) }
            SelectField("Moteur", moteur, NoteDeFrais.moteurOptions, Modifier.fillMaxWidth()) { moteur = it; Prefs.setProfile(ctx, "moteur", it) }
        }
        Footer("Sert à remplir l'en-tête de la note de frais et à calculer le barème kilométrique.")
    }
}

@Composable
private fun ProfileField(key: String, label: String, caps: KeyboardCapitalization) {
    val ctx = LocalContext.current
    var value by remember { mutableStateOf(Prefs.profile(ctx, key)) }
    OutlinedTextField(
        value, { value = it; Prefs.setProfile(ctx, key, it) },
        label = { Text(label) },
        keyboardOptions = KeyboardOptions(capitalization = caps),
        singleLine = true, modifier = Modifier.fillMaxWidth(),
    )
}

// ---------- Listes ----------

@Composable
private fun ListsPage(onBack: () -> Unit, onOpen: (ListKind) -> Unit) {
    val ctx = LocalContext.current
    Page("Listes", onBack) {
        Group {
            ListKind.entries.forEachIndexed { i, kind ->
                if (i > 0) HorizontalDivider()
                NavRow(kind.plural, "${Prefs.list(ctx, kind).size}") { onOpen(kind) }
            }
        }
        Footer("Ces valeurs se choisissent sur chaque ticket. Le dernier choix est repris automatiquement sur le ticket suivant.")
    }
}

@Composable
private fun ListEditorPage(kind: ListKind, onBack: () -> Unit) {
    val ctx = LocalContext.current
    val values = remember { mutableStateListOf<String>().apply { addAll(Prefs.list(ctx, kind)) } }
    var newValue by remember { mutableStateOf("") }

    fun add() {
        val v = newValue.trim()
        if (v.isNotEmpty() && v !in values) {
            values.add(v)
            Prefs.setList(ctx, kind, values.toList())
        }
        newValue = ""
    }

    Page(kind.plural, onBack) {
        Group {
            Row(verticalAlignment = Alignment.CenterVertically) {
                OutlinedTextField(newValue, { newValue = it }, label = { Text("Ajouter…") }, singleLine = true,
                    modifier = Modifier.weight(1f))
                IconButton(onClick = { add() }, enabled = newValue.isNotBlank()) { Icon(Icons.Filled.Add, "Ajouter") }
            }
        }
        Group {
            if (values.isEmpty()) Text("Aucune valeur pour l'instant.", color = MaterialTheme.colorScheme.onSurfaceVariant)
            values.toList().forEachIndexed { i, v ->
                if (i > 0) HorizontalDivider()
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(v, Modifier.weight(1f))
                    IconButton(onClick = { values.remove(v); Prefs.setList(ctx, kind, values.toList()) }) {
                        Icon(Icons.Filled.Delete, "Supprimer", tint = MaterialTheme.colorScheme.error)
                    }
                }
            }
        }
    }
}

// ---------- Modèle Excel ----------

@Composable
private fun TemplatePage(onBack: () -> Unit) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    var hasCustom by remember { mutableStateOf(NoteDeFrais.customTemplate(ctx).exists()) }
    var message by remember { mutableStateOf<String?>(null) }

    val importLauncher = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        scope.launch {
            message = withContext(Dispatchers.IO) {
                try {
                    val data = ctx.contentResolver.openInputStream(uri)?.use { it.readBytes() }
                        ?: throw IllegalStateException("Lecture impossible")
                    // Vérifie que le modèle est exploitable avant de l'adopter
                    NoteDeFrais.fill(data, NoteDeFrais.Header(), emptyList())
                    NoteDeFrais.customTemplate(ctx).writeBytes(data)
                    "Modèle importé."
                } catch (e: Exception) {
                    "Ce fichier ne peut pas servir de modèle : ${e.message}"
                }
            }
            hasCustom = NoteDeFrais.customTemplate(ctx).exists()
        }
    }

    Page("Modèle Excel", onBack) {
        Group {
            Row { Text("Modèle utilisé", Modifier.weight(1f)); Text(if (hasCustom) "Importé" else if (NoteDeFrais.hasTemplate(ctx)) "Modèle de base" else "Aucun", fontWeight = FontWeight.SemiBold) }
            HorizontalDivider()
            NavRow("Importer un nouveau modèle (.xlsx)") {
                importLauncher.launch(arrayOf("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", "application/octet-stream"))
            }
            if (hasCustom) {
                TextButton(onClick = { NoteDeFrais.customTemplate(ctx).delete(); hasCustom = false }) {
                    Text("Revenir au modèle de base", color = MaterialTheme.colorScheme.error)
                }
            }
        }
        Footer("Un modèle de note de frais générique est fourni avec l'app. L'en-tête (nom, entité, véhicule, immatriculation…) est rempli avec votre Profil. Vous pouvez importer la trame de votre entreprise si elle garde la même disposition : justificatifs lignes 14 à 44, mêmes colonnes et mêmes cases d'en-tête.")
    }

    message?.let {
        AlertDialog(onDismissRequest = { message = null }, text = { Text(it) },
            confirmButton = { TextButton(onClick = { message = null }) { Text("OK") } })
    }
}
