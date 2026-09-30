package com.lemercier.scantickets.ui

import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.text.format.Formatter
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.core.content.FileProvider
import org.json.JSONArray
import java.io.File

// ---------- Envoi par e-mail (note de frais, récapitulatif, justificatifs) ----------

/** Mémoire des adresses e-mail déjà utilisées */
object MailMemory {
    private fun sp(c: Context) = c.getSharedPreferences("settings", Context.MODE_PRIVATE)

    fun recent(c: Context): List<String> {
        val raw = sp(c).getString("mail_recent", null) ?: return emptyList()
        return runCatching { JSONArray(raw).let { a -> (0 until a.length()).map { a.getString(it) } } }.getOrDefault(emptyList())
    }

    /** Ajoute les adresses en tête de liste (sans doublon, 12 au maximum) */
    fun remember(c: Context, addresses: List<String>) {
        if (addresses.isEmpty()) return
        val list = addresses + recent(c).filter { old -> addresses.none { it.equals(old, ignoreCase = true) } }
        sp(c).edit().putString("mail_recent", JSONArray(list.take(12)).toString()).apply()
    }

    fun forget(c: Context, address: String) {
        sp(c).edit().putString("mail_recent", JSONArray(recent(c).filter { it != address }).toString()).apply()
    }

    fun lastTo(c: Context): String = sp(c).getString("mail_to", "") ?: ""
    fun lastCc(c: Context): String = sp(c).getString("mail_cc", "") ?: ""
    fun setLast(c: Context, to: String, cc: String) = sp(c).edit().putString("mail_to", to).putString("mail_cc", cc).apply()

    /** « a@b.fr, c@d.fr » → [a@b.fr, c@d.fr] */
    fun split(s: String): List<String> = s.split(',', ';', ' ', '\n').map { it.trim() }.filter { it.isNotEmpty() }

    fun isValid(a: String): Boolean = Regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$").matches(a)

    /** Ajoute une adresse à un champ « À » ou « Cc » si elle n'y est pas déjà */
    fun adding(address: String, field: String): String {
        val list = split(field).toMutableList()
        if (list.none { it.equals(address, ignoreCase = true) }) list += address
        return list.joinToString(", ")
    }
}

private const val SIZE_LIMIT = 20L * 1024 * 1024

/** Formulaire d'envoi : destinataires (avec mémoire), objet, message, pièces jointes */
@Composable
fun MailDialog(
    files: List<File>,
    initialSubject: String,
    initialBody: String,
    onDismiss: () -> Unit,
    onError: (String) -> Unit,
) {
    val ctx = LocalContext.current
    var to by remember { mutableStateOf(MailMemory.lastTo(ctx)) }
    var cc by remember { mutableStateOf(MailMemory.lastCc(ctx)) }
    var subject by remember { mutableStateOf(initialSubject) }
    var body by remember { mutableStateOf(initialBody) }
    var recent by remember { mutableStateOf(MailMemory.recent(ctx)) }
    var error by remember { mutableStateOf<String?>(null) }
    val totalSize = remember(files) { files.sumOf { it.length() } }
    val photos = files.count { !it.name.endsWith(".xlsx") }

    fun send() {
        val toList = MailMemory.split(to)
        val ccList = MailMemory.split(cc)
        val bad = (toList + ccList).firstOrNull { !MailMemory.isValid(it) }
        if (bad != null) { error = "Adresse invalide : $bad"; return }
        // Mémorise les adresses pour les prochains envois
        MailMemory.remember(ctx, toList + ccList)
        MailMemory.setLast(ctx, toList.joinToString(", "), ccList.joinToString(", "))
        if (sendMail(ctx, files, toList, ccList, subject, body)) onDismiss()
        else onError("Aucune app de messagerie trouvée. Installez Gmail ou Outlook, ou utilisez « Tout partager ».")
    }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Envoyer par mail") },
        text = {
            Column(
                Modifier.verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                val emailKeyboard = KeyboardOptions(keyboardType = KeyboardType.Email)
                OutlinedTextField(to, { to = it; error = null }, label = { Text("À") },
                    placeholder = { Text("adresse@entreprise.fr") }, keyboardOptions = emailKeyboard,
                    modifier = Modifier.fillMaxWidth())
                OutlinedTextField(cc, { cc = it; error = null }, label = { Text("Cc (facultatif)") },
                    keyboardOptions = emailKeyboard, modifier = Modifier.fillMaxWidth())
                Text("Plusieurs adresses : séparez-les par une virgule.",
                    style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                error?.let { Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall) }

                if (recent.isNotEmpty()) {
                    Text("Adresses mémorisées", fontWeight = FontWeight.SemiBold)
                    recent.forEach { address ->
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(address, Modifier.weight(1f), maxLines = 1, overflow = TextOverflow.Ellipsis,
                                style = MaterialTheme.typography.bodyMedium)
                            TextButton(onClick = { to = MailMemory.adding(address, to) }) { Text("À") }
                            TextButton(onClick = { cc = MailMemory.adding(address, cc) }) { Text("Cc") }
                            IconButton(onClick = { MailMemory.forget(ctx, address); recent = MailMemory.recent(ctx) }) {
                                Icon(Icons.Filled.Close, contentDescription = "Oublier cette adresse")
                            }
                        }
                    }
                    HorizontalDivider()
                }

                OutlinedTextField(subject, { subject = it }, label = { Text("Objet") }, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(body, { body = it }, label = { Text("Message") },
                    modifier = Modifier.fillMaxWidth().heightIn(min = 120.dp))

                Text(
                    "Pièces jointes : ${files.size - photos} fichier(s) Excel" +
                        (if (photos > 0) " + $photos photo(s)" else "") +
                        " · " + Formatter.formatShortFileSize(ctx, totalSize),
                    style = MaterialTheme.typography.bodySmall,
                )
                if (totalSize > SIZE_LIMIT) {
                    Text("Plus de 20 Mo : certaines messageries refusent les mails aussi lourds. Désactivez « Joindre les justificatifs » ou envoyez en plusieurs fois.",
                        style = MaterialTheme.typography.bodySmall, color = Warning)
                }
            }
        },
        confirmButton = {
            TextButton(onClick = { send() }, enabled = MailMemory.split(to).isNotEmpty()) {
                Text("Continuer", fontWeight = FontWeight.Bold)
            }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Annuler") } },
    )
}

/** Ouvre l'app de messagerie avec destinataires, objet, message et pièces jointes pré-remplis */
fun sendMail(ctx: Context, files: List<File>, to: List<String>, cc: List<String>, subject: String, body: String): Boolean {
    val auth = ctx.packageName + ".fileprovider"
    val uris = ArrayList(files.map { FileProvider.getUriForFile(ctx, auth, it) })
    fun build() = Intent(if (uris.size == 1) Intent.ACTION_SEND else Intent.ACTION_SEND_MULTIPLE).apply {
        type = if (uris.size == 1 && files[0].name.endsWith(".xlsx"))
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" else "*/*"
        putExtra(Intent.EXTRA_EMAIL, to.toTypedArray())
        if (cc.isNotEmpty()) putExtra(Intent.EXTRA_CC, cc.toTypedArray())
        putExtra(Intent.EXTRA_SUBJECT, subject)
        putExtra(Intent.EXTRA_TEXT, body)
        if (uris.size == 1) putExtra(Intent.EXTRA_STREAM, uris[0])
        else putParcelableArrayListExtra(Intent.EXTRA_STREAM, uris)
        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        if (uris.isNotEmpty()) {
            clipData = ClipData.newRawUri(files[0].name, uris[0]).apply { uris.drop(1).forEach { addItem(ClipData.Item(it)) } }
        }
    }
    // Seules les apps de messagerie (Gmail, Outlook, Samsung Email…) sont proposées
    val mailOnly = build().apply { selector = Intent(Intent.ACTION_SENDTO, Uri.parse("mailto:")) }
    return try {
        ctx.startActivity(mailOnly)
        true
    } catch (e: ActivityNotFoundException) {
        try {
            ctx.startActivity(Intent.createChooser(build(), "Envoyer par mail"))
            true
        } catch (e2: ActivityNotFoundException) {
            false
        }
    }
}
