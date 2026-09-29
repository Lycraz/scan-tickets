package com.lemercier.scantickets

import android.app.Application
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.documentfile.provider.DocumentFile
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import java.io.File
import java.io.FileOutputStream

/**
 * Base de données locale : tickets.json + photos dans le stockage privé de l'app,
 * avec copie automatique des photos dans un dossier choisi par l'utilisateur
 * (dossier du téléphone, carte SD…).
 */
class TicketStore(app: Application) : AndroidViewModel(app) {
    private val ctx get() = getApplication<Application>()
    private val dataFile get() = File(ctx.filesDir, "tickets.json")
    val photosDir: File get() = File(ctx.filesDir, "photos").apply { mkdirs() }

    var tickets by mutableStateOf<List<Ticket>>(emptyList())
        private set
    var folderName by mutableStateOf<String?>(null)
        private set
    var lastFolderError by mutableStateOf<String?>(null)

    private val thumbCache = HashMap<String, Bitmap>()

    /** Progression de l'import de plusieurs photos (null = rien en cours) */
    var batchProgress by mutableStateOf<String?>(null)
        private set
    var batchMessage by mutableStateOf<String?>(null)

    /** Plusieurs tickets : lecture en série, enregistrés avec le badge « à vérifier » */
    fun processBatch(uris: List<Uri>) {
        viewModelScope.launch {
            var ok = 0
            uris.forEachIndexed { i, uri ->
                batchProgress = "Ticket ${i + 1} sur ${uris.size}…"
                val img = withContext(Dispatchers.IO) { runCatching { com.lemercier.scantickets.loadBitmap(ctx, uri) }.getOrNull() } ?: return@forEachIndexed
                var t = Ticket.withDefaults(ctx)
                runCatching { Analyzer.run(ctx, img) }.getOrNull()?.let { t = it.applyTo(t) }
                save(t.copy(aVerifier = true), img)
                ok++
            }
            batchProgress = null
            batchMessage = "$ok tickets ajoutés. Ils sont marqués « à vérifier » : touchez-les pour contrôler."
        }
    }

    init {
        load()
        folderName = folder()?.name
    }

    // ---------- Lecture / écriture ----------

    private fun load() {
        if (!dataFile.exists()) return
        tickets = runCatching {
            val arr = JSONArray(dataFile.readText())
            (0 until arr.length()).map { Ticket.fromJson(arr.getJSONObject(it)) }
        }.getOrDefault(emptyList()).let(::sorted)
    }

    private fun persist() {
        val arr = JSONArray()
        tickets.forEach { arr.put(it.toJson()) }
        val tmp = File(ctx.filesDir, "tickets.json.tmp")
        tmp.writeText(arr.toString(2))
        tmp.renameTo(dataFile)
    }

    private fun sorted(list: List<Ticket>) =
        list.sortedWith(compareByDescending<Ticket> { it.date }.thenByDescending { it.createdAt })

    fun imageFile(t: Ticket) = File(photosDir, "${t.id}.jpg")

    fun loadBitmap(t: Ticket): Bitmap? =
        imageFile(t).takeIf { it.exists() }?.let { BitmapFactory.decodeFile(it.path) }

    fun thumbnail(t: Ticket): Bitmap? {
        thumbCache[t.id]?.let { return it }
        val f = imageFile(t)
        if (!f.exists()) return null
        val opts = BitmapFactory.Options().apply { inSampleSize = 8 }
        return BitmapFactory.decodeFile(f.path, opts)?.also { thumbCache[t.id] = it }
    }

    /** Enregistre (création ou modification). `image` n'est fourni que pour un nouveau ticket. */
    suspend fun save(ticket: Ticket, image: Bitmap? = null) {
        var t = ticket
        withContext(Dispatchers.IO) {
            if (image != null) {
                FileOutputStream(imageFile(t)).use { image.compress(Bitmap.CompressFormat.JPEG, 82, it) }
                thumbCache.remove(t.id)
            }
            t = t.copy(folderPhotoPath = copyPhotoToFolder(t))
        }
        val others = tickets.filter { it.id != t.id }
        tickets = sorted(others + t)
        withContext(Dispatchers.IO) { persist() }
    }

    suspend fun delete(t: Ticket) {
        tickets = tickets.filter { it.id != t.id }
        thumbCache.remove(t.id)
        withContext(Dispatchers.IO) {
            imageFile(t).delete()
            persist()
        }
    }

    val months: List<String> get() = tickets.map { it.monthKey }.distinct().sortedDescending()
    val weeks: List<String> get() = tickets.map { it.weekKey }.distinct().sortedDescending()
    val toReviewCount: Int get() = tickets.count { it.aVerifier }

    // ---------- Dossier de sauvegarde ----------

    fun setFolder(uri: Uri) {
        runCatching {
            ctx.contentResolver.takePersistableUriPermission(
                uri, Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            )
        }
        Prefs.setFolderUri(ctx, uri.toString())
        folderName = folder()?.name
        lastFolderError = if (folderName == null) "Dossier inaccessible" else null
    }

    fun clearFolder() {
        Prefs.setFolderUri(ctx, null)
        folderName = null
    }

    private fun folder(): DocumentFile? {
        val s = Prefs.folderUri(ctx) ?: return null
        return runCatching { DocumentFile.fromTreeUri(ctx, Uri.parse(s)) }.getOrNull()?.takeIf { it.canWrite() }
    }

    private fun subDir(parent: DocumentFile, name: String): DocumentFile? =
        parent.findFile(name)?.takeIf { it.isDirectory } ?: parent.createDirectory(name)

    private fun writeInto(dir: DocumentFile, name: String, mime: String, src: File): Boolean {
        dir.findFile(name)?.delete()
        val dest = dir.createFile(mime, name) ?: return false
        ctx.contentResolver.openOutputStream(dest.uri)?.use { out -> src.inputStream().use { it.copyTo(out) } } ?: return false
        return true
    }

    /** Copie la photo dans <dossier>/Photos/<AAAA-MM>/<nom lisible>.jpg */
    private fun copyPhotoToFolder(t: Ticket): String? {
        val root = folder() ?: return t.folderPhotoPath
        val src = imageFile(t)
        if (!src.exists()) return t.folderPhotoPath
        return runCatching {
            val relative = "Photos/${t.monthKey}/${t.photoFileName}"
            // Supprime l'ancienne copie si le nom a changé
            t.folderPhotoPath?.takeIf { it != relative }?.let { old -> findByPath(root, old)?.delete() }
            val photos = subDir(root, "Photos") ?: error("Création du dossier Photos impossible")
            val month = subDir(photos, t.monthKey) ?: error("Création du dossier ${t.monthKey} impossible")
            if (!writeInto(month, t.photoFileName, "image/jpeg", src)) error("Écriture impossible")
            lastFolderError = null
            relative
        }.getOrElse {
            lastFolderError = "Dossier de sauvegarde : ${it.message}"
            t.folderPhotoPath
        }
    }

    private fun findByPath(root: DocumentFile, path: String): DocumentFile? {
        var cur: DocumentFile = root
        for (part in path.split('/')) cur = cur.findFile(part) ?: return null
        return cur
    }

    suspend fun syncAllPhotos(): Int = withContext(Dispatchers.IO) {
        var n = 0
        val updated = tickets.map { t ->
            val p = copyPhotoToFolder(t.copy(folderPhotoPath = null))
            if (p != null) n++
            t.copy(folderPhotoPath = p ?: t.folderPhotoPath)
        }
        withContext(Dispatchers.Main) { tickets = updated }
        persist()
        n
    }

    /** Écrit un export dans <dossier>/Exports/. Renvoie un libellé si réussi. */
    suspend fun saveExportToFolder(file: File, mime: String, subfolder: String? = null): String? = withContext(Dispatchers.IO) {
        val root = folder() ?: return@withContext null
        runCatching {
            val exports = subDir(root, "Exports") ?: error("Création du dossier Exports impossible")
            val dir = if (subfolder != null) subDir(exports, subfolder) ?: error("Création du dossier $subfolder impossible") else exports
            if (!writeInto(dir, file.name, mime, file)) error("Écriture impossible")
            "${root.name}/Exports/" + (subfolder?.let { "$it/" } ?: "") + file.name
        }.getOrElse {
            lastFolderError = "Dossier de sauvegarde : ${it.message}"
            null
        }
    }
}
