package com.lemercier.scantickets

import android.content.Context
import android.graphics.Bitmap
import android.graphics.ImageDecoder
import android.net.Uri
import android.util.Base64
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.net.HttpURLConnection
import java.net.URL
import kotlin.math.abs
import kotlin.math.max

/** Résultat de la lecture d'un ticket */
data class Analysis(
    val commercant: String? = null,
    val date: java.time.LocalDate? = null,
    val ttc: Double? = null,
    val ht: Double? = null,
    val tva: Double? = null,
    val devise: String? = null,
    val paiement: String? = null,
    val nature: String? = null,
    val description: String? = null,
    val confiance: String = "moyenne",
    val source: String = "",
    val warning: String? = null,
) {
    fun applyTo(t: Ticket): Ticket {
        var r = t
        commercant?.takeIf { it.isNotBlank() }?.let { r = r.copy(commercant = it) }
        date?.let { r = r.copy(date = it) }
        ttc?.let { r = r.copy(ttc = it) }
        tva?.let { r = r.copy(tva = it) }
        ht?.let { r = r.copy(ht = it) }
        devise?.takeIf { it.length == 3 }?.let { r = r.copy(devise = it.uppercase()) }
        paiement?.takeIf { it in Catalog.paiements }?.let { r = r.copy(paiement = it) }
        nature?.takeIf { it in Catalog.natures }?.let { r = r.copy(nature = it) }
        description?.takeIf { it.isNotBlank() }?.let { r = r.copy(description = it) }
        if (r.ht == null && r.ttc != null && r.tva != null) r = r.copy(ht = Fmt.round2(r.ttc!! - r.tva!!))
        return r.copy(source = source)
    }
}

object Analyzer {
    /** Choisit le moteur selon les réglages. Renvoie null en mode « saisie manuelle ». */
    suspend fun run(ctx: Context, image: Bitmap, progress: (String) -> Unit = {}): Analysis? {
        val engine = Prefs.engine(ctx)
        val key = Prefs.apiKey(ctx)
        if (engine == "none") return null
        if (engine == "claude" || (engine == "auto" && key.isNotEmpty())) {
            try {
                progress("Lecture par l'IA…")
                return ClaudeClient.analyze(image, key, Prefs.model(ctx))
            } catch (e: Exception) {
                if (engine == "claude") throw e
                progress("IA indisponible, lecture locale…")
                return localAnalysis(image).copy(
                    warning = "IA indisponible (${e.message}). Lecture faite sur le téléphone : vérifiez les montants."
                )
            }
        }
        progress("Lecture sur le téléphone…")
        return localAnalysis(image)
    }

    suspend fun localAnalysis(image: Bitmap): Analysis {
        val text = LocalOCR.recognize(image)
        return ReceiptParser.parse(text).copy(source = "Lecture téléphone", confiance = "basse")
    }
}

// ---------- IA Claude ----------

object ClaudeClient {
    private val prompt: String
        get() = """
        Tu es un assistant comptable. Analyse cette photo de ticket de caisse, reçu ou facture.
        Réponds UNIQUEMENT avec un objet JSON valide, sans texte autour, avec ces clés :
        {
          "commercant": "nom de l'enseigne ou du commerce",
          "date": "AAAA-MM-JJ",
          "montant_ttc": nombre (total payé),
          "montant_ht": nombre ou null,
          "tva": nombre (montant total de TVA) ou null,
          "devise": "code ISO, ex. EUR",
          "moyen_paiement": une valeur parmi ${JSONArray(Catalog.paiements)},
          "nature": une valeur parmi ${JSONArray(Catalog.natures)},
          "description": "résumé très court de l'achat (ex. Déjeuner 2 couverts, Gazole 42 L)",
          "confiance": "haute" | "moyenne" | "basse"
        }
        Les nombres utilisent le point décimal. Si une information est absente, mets null.
        Si l'image n'est pas un ticket, mets "confiance": "basse".
        """.trimIndent()

    private fun open(url: String, key: String): HttpURLConnection =
        (URL(url).openConnection() as HttpURLConnection).apply {
            setRequestProperty("x-api-key", key)
            setRequestProperty("anthropic-version", "2023-06-01")
            setRequestProperty("content-type", "application/json")
            connectTimeout = 20_000
            readTimeout = 90_000
        }

    private fun readResponse(c: HttpURLConnection): String {
        val code = c.responseCode
        val body = (if (code in 200..299) c.inputStream else c.errorStream)?.bufferedReader()?.use { it.readText() } ?: ""
        if (code !in 200..299) {
            val msg = runCatching { JSONObject(body).getJSONObject("error").getString("message") }.getOrNull()
            throw AppException("Erreur $code" + (msg?.let { " : $it" } ?: ""))
        }
        return body
    }

    suspend fun analyze(image: Bitmap, key: String, model: String): Analysis = withContext(Dispatchers.IO) {
        if (key.isEmpty()) throw AppException("Aucune clé API configurée")
        val small = image.scaledTo(1600)
        val jpeg = ByteArrayOutputStream().use { small.compress(Bitmap.CompressFormat.JPEG, 80, it); it.toByteArray() }
        val b64 = Base64.encodeToString(jpeg, Base64.NO_WRAP)
        val body = JSONObject().apply {
            put("model", model)
            put("max_tokens", 800)
            put("messages", JSONArray().put(JSONObject().apply {
                put("role", "user")
                put("content", JSONArray()
                    .put(JSONObject().apply {
                        put("type", "image")
                        put("source", JSONObject().put("type", "base64").put("media_type", "image/jpeg").put("data", b64))
                    })
                    .put(JSONObject().put("type", "text").put("text", prompt)))
            }))
        }
        val c = open("https://api.anthropic.com/v1/messages", key)
        c.requestMethod = "POST"
        c.doOutput = true
        c.outputStream.use { it.write(body.toString().toByteArray()) }
        val resp = JSONObject(readResponse(c))
        val content = resp.optJSONArray("content") ?: throw AppException("Réponse de l'IA illisible")
        val text = (0 until content.length()).joinToString("") { content.getJSONObject(it).optString("text") }
        val start = text.indexOf('{')
        val end = text.lastIndexOf('}')
        if (start < 0 || end <= start) throw AppException("Réponse de l'IA illisible")
        val j = JSONObject(text.substring(start, end + 1))

        Analysis(
            commercant = j.optStringOrNull("commercant"),
            date = j.optStringOrNull("date")?.let { Fmt.fromIso(it) },
            ttc = number(j, "montant_ttc"),
            ht = number(j, "montant_ht"),
            tva = number(j, "tva"),
            devise = j.optStringOrNull("devise"),
            paiement = j.optStringOrNull("moyen_paiement"),
            nature = j.optStringOrNull("nature"),
            description = j.optStringOrNull("description"),
            confiance = j.optStringOrNull("confiance") ?: "moyenne",
            source = "IA Claude",
        )
    }

    private fun number(j: JSONObject, k: String): Double? {
        if (!j.has(k) || j.isNull(k)) return null
        return when (val v = j.get(k)) {
            is Number -> Fmt.round2(v.toDouble())
            is String -> Fmt.parseAmount(v)
            else -> null
        }
    }

    data class ModelInfo(val id: String, val name: String)

    suspend fun listModels(key: String): List<ModelInfo> = withContext(Dispatchers.IO) {
        val c = open("https://api.anthropic.com/v1/models?limit=100", key)
        val arr = JSONObject(readResponse(c)).optJSONArray("data") ?: JSONArray()
        (0 until arr.length()).map {
            val m = arr.getJSONObject(it)
            ModelInfo(m.getString("id"), m.optString("display_name", m.getString("id")))
        }
    }
}

fun JSONObject.optStringOrNull(k: String): String? =
    if (!has(k) || isNull(k)) null else optString(k).takeIf { it.isNotBlank() }

// ---------- Lecture locale (ML Kit, gratuite, hors ligne) ----------

object LocalOCR {
    suspend fun recognize(image: Bitmap): String {
        val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
        try {
            val result = recognizer.process(InputImage.fromBitmap(image.scaledTo(2400), 0)).await()
            // Regroupe les éléments situés sur la même ligne (ex. « TOTAL » … « 39,50 »)
            val items = result.textBlocks.flatMap { it.lines }
                .mapNotNull { l -> l.boundingBox?.let { it to l.text } }
                .sortedBy { it.first.centerY() }
            val rows = mutableListOf<MutableList<Pair<android.graphics.Rect, String>>>()
            for (item in items) {
                val last = rows.lastOrNull()
                val ref = last?.first()?.first
                if (last != null && ref != null &&
                    abs(ref.centerY() - item.first.centerY()) < max(ref.height(), item.first.height()) * 0.6
                ) {
                    last.add(item)
                } else {
                    rows.add(mutableListOf(item))
                }
            }
            return rows.joinToString("\n") { row -> row.sortedBy { it.first.left }.joinToString(" ") { it.second } }
        } finally {
            recognizer.close()
        }
    }
}

// ---------- Analyse du texte brut ----------

object ReceiptParser {
    private val AMOUNT = Regex("""(\d{1,5}(?:[ .]\d{3})*[.,]\d{2})(?!\d)""")

    fun parse(text: String): Analysis {
        val lines = text.lines().map { it.trim() }.filter { it.isNotEmpty() }
        val low = text.lowercase()

        val commercant = lines.firstOrNull { l ->
            Regex("[a-zà-ÿ]{3,}", RegexOption.IGNORE_CASE).containsMatchIn(l) &&
                !Regex("ticket|facture|bienvenue|merci|t[ée]l|siret|www|http|date|caisse", RegexOption.IGNORE_CASE).containsMatchIn(l)
        }?.take(60)

        var date: java.time.LocalDate? = null
        Regex("""(\d{1,2})[/.\-](\d{1,2})[/.\-](\d{2,4})""").find(text)?.let { m ->
            val d = m.groupValues[1].toInt()
            val mo = m.groupValues[2].toInt()
            var y = m.groupValues[3].toInt()
            if (y < 100) y += 2000
            if (mo in 1..12 && d in 1..31) date = runCatching { java.time.LocalDate.of(y, mo, d) }.getOrNull()
        }

        val priorities = listOf(
            """net\s*[àa]\s*payer|[àa]\s*payer|total\s*ttc|montant\s*ttc""",
            """total""",
            """\bcb\b|carte|montant|esp[èe]ces""",
        )
        var ttc: Double? = null
        for (p in priorities) {
            val re = Regex(p, RegexOption.IGNORE_CASE)
            val excl = Regex("""tva|\bht\b""", RegexOption.IGNORE_CASE)
            val cands = lines.filter { re.containsMatchIn(it) && !excl.containsMatchIn(it) }.flatMap(::amounts)
            if (cands.isNotEmpty()) { ttc = cands.max(); break }
        }
        if (ttc == null) ttc = lines.flatMap(::amounts).maxOrNull()

        val rates = setOf(2.1, 5.5, 10.0, 20.0)
        val tva = lines.filter { it.contains("tva", ignoreCase = true) }.flatMap(::amounts)
            .filter { it !in rates && (ttc == null || it < ttc!!) }
            .maxOrNull()?.takeIf { it > 0 }
        val ht = if (ttc != null && tva != null) Fmt.round2(ttc!! - tva) else null

        return Analysis(
            commercant = commercant, date = date, ttc = ttc, tva = tva, ht = ht, devise = "EUR",
            nature = guessNature(low), paiement = guessPayment(low),
        )
    }

    fun amounts(line: String): List<Double> = AMOUNT.findAll(line).mapNotNull { m ->
        var s = m.groupValues[1]
        // Retire les séparateurs de milliers (« 1 234,56 » ou « 1.234,56 »)
        if (s.length > 6) s = s.dropLast(3).replace(" ", "").replace(".", "") + s.takeLast(3)
        Fmt.parseAmount(s)
    }.toList()

    fun guessNature(t: String): String {
        val rules = listOf(
            "Carburant" to """carburant|gazole|gasoil|sp ?95|sp ?98|\be10\b|diesel|station|esso|shell|totalenergies|avia|\bbp\b""",
            "Péage" to """p[ée]age|autoroute|vinci|sanef|aprr|\basf\b|cofiroute""",
            "Parking" to """parking|stationnement|indigo|effia|onepark""",
            "Transport" to """sncf|ratp|uber|taxi|bolt|heetch|train|navigo|billet|a[ée]roport|air france""",
            "Hôtel" to """h[ôo]tel|ibis|novotel|mercure|campanile|nuit[ée]e|booking|airbnb""",
            "Restaurant" to """restaurant|brasserie|caf[ée]|bistro|pizz|burger|mcdo|kfc|sushi|boulangerie|traiteur|couverts?|menu|plat|dessert|boisson""",
            "Télécom" to """orange|sfr|bouygues|free mobile|forfait""",
            "Fournitures" to """bureau vall[ée]e|fnac|darty|papeterie|amazon|leroy|castorama|fournitures?""",
        )
        return rules.firstOrNull { Regex(it.second).containsMatchIn(t) }?.first ?: "Divers"
    }

    fun guessPayment(t: String): String? = when {
        Regex("""esp[èe]ces|rendu|monnaie rendue""").containsMatchIn(t) -> "Espèces"
        Regex("""ticket.?resto|titre.?resto|swile|edenred|up d[ée]j|pluxee|sodexo""").containsMatchIn(t) -> "Titre-restaurant"
        Regex("""ch[èe]que""").containsMatchIn(t) -> "Chèque"
        Regex("""\bcb\b|carte|visa|mastercard|sans contact|contactless|amex""").containsMatchIn(t) -> "Carte bancaire"
        else -> null
    }
}

// ---------- Images ----------

/** Réduit l'image pour que son plus grand côté fasse au plus `maxSide` pixels */
fun Bitmap.scaledTo(maxSide: Int): Bitmap {
    val longest = max(width, height)
    if (longest <= maxSide) return this
    val s = maxSide.toFloat() / longest
    return Bitmap.createScaledBitmap(this, (width * s).toInt(), (height * s).toInt(), true)
}

/** Charge une image (orientation corrigée automatiquement) en limitant sa taille */
fun loadBitmap(ctx: Context, uri: Uri, maxSide: Int = 2000): Bitmap {
    val src = ImageDecoder.createSource(ctx.contentResolver, uri)
    return ImageDecoder.decodeBitmap(src) { decoder, info, _ ->
        decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
        val longest = max(info.size.width, info.size.height)
        if (longest > maxSide) {
            val s = maxSide.toFloat() / longest
            decoder.setTargetSize((info.size.width * s).toInt(), (info.size.height * s).toInt())
        }
    }
}
