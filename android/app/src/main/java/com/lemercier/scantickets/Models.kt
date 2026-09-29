package com.lemercier.scantickets

import android.content.Context
import org.json.JSONObject
import java.text.Normalizer
import java.text.NumberFormat
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.time.format.TextStyle
import java.time.temporal.WeekFields
import java.util.Currency
import java.util.Locale
import java.util.UUID
import kotlin.math.roundToLong

// ---------- Listes de référence ----------

object Catalog {
    val natures = listOf("Restaurant", "Carburant", "Péage", "Parking", "Transport", "Hôtel", "Fournitures", "Télécom", "Divers")
    val paiements = listOf("Carte bancaire", "Espèces", "Chèque", "Virement", "Titre-restaurant", "Autre")
    /** Nature spéciale pour les trajets en véhicule personnel (pas de ticket) */
    const val KM_NATURE = "Kilomètres"
}

// ---------- Ticket ----------

data class Ticket(
    val id: String = UUID.randomUUID().toString(),
    val createdAt: Long = System.currentTimeMillis(),
    val commercant: String = "",
    val date: LocalDate = LocalDate.now(),
    val nature: String = "Divers",
    val ttc: Double? = null,
    val tva: Double? = null,
    val ht: Double? = null,
    val devise: String = "EUR",
    val paiement: String = "",
    val description: String = "",
    val notes: String = "",
    val aVerifier: Boolean = false,
    val source: String = "",
    /** Chemin relatif de la copie de la photo dans le dossier de sauvegarde choisi */
    val folderPhotoPath: String? = null,
    // Champs de la note de frais
    val affaire: String = "",
    val lieu: String = "",
    val partenaire: String = "",
    val raison: String = "",
    /** Personnes invitées (colonne « Réception ») */
    val invites: String = "",
    /** Kilomètres parcourus avec le véhicule personnel (nature « Kilomètres ») */
    val km: Double? = null,
) {
    val isKilometres: Boolean get() = nature == Catalog.KM_NATURE
    val monthKey: String get() = Fmt.monthKey(date)
    val weekKey: String get() = Fmt.weekKey(date)

    /** Nom lisible : 2026-09-14_Restaurant_Brasserie_du_Port_39,50.jpg */
    val photoFileName: String
        get() = "${Fmt.iso(date)}_${Fmt.safeName(nature)}_${Fmt.safeName(commercant)}_${Fmt.amountString(ttc ?: 0.0)}.jpg"

    fun toJson(): JSONObject = JSONObject().apply {
        put("id", id); put("createdAt", createdAt); put("commercant", commercant)
        put("date", Fmt.iso(date)); put("nature", nature)
        put("ttc", ttc ?: JSONObject.NULL); put("tva", tva ?: JSONObject.NULL); put("ht", ht ?: JSONObject.NULL)
        put("devise", devise); put("paiement", paiement); put("description", description); put("notes", notes)
        put("aVerifier", aVerifier); put("source", source); put("folderPhotoPath", folderPhotoPath ?: JSONObject.NULL)
        put("affaire", affaire); put("lieu", lieu); put("partenaire", partenaire); put("raison", raison)
        put("invites", invites); put("km", km ?: JSONObject.NULL)
    }

    companion object {
        fun fromJson(o: JSONObject): Ticket = Ticket(
            id = o.getString("id"),
            createdAt = o.optLong("createdAt", System.currentTimeMillis()),
            commercant = o.optString("commercant"),
            date = Fmt.fromIso(o.optString("date")) ?: LocalDate.now(),
            nature = o.optString("nature", "Divers"),
            ttc = o.optDoubleOrNull("ttc"), tva = o.optDoubleOrNull("tva"), ht = o.optDoubleOrNull("ht"),
            devise = o.optString("devise", "EUR"),
            paiement = o.optString("paiement"),
            description = o.optString("description"),
            notes = o.optString("notes"),
            aVerifier = o.optBoolean("aVerifier"),
            source = o.optString("source"),
            folderPhotoPath = if (o.isNull("folderPhotoPath")) null else o.optString("folderPhotoPath"),
            affaire = o.optString("affaire"),
            lieu = o.optString("lieu"),
            partenaire = o.optString("partenaire"),
            raison = o.optString("raison"),
            invites = o.optString("invites"),
            km = o.optDoubleOrNull("km"),
        )

        /** Nouveau ticket pré-rempli avec les derniers choix de la note de frais */
        fun withDefaults(c: Context, nature: String? = null): Ticket = Ticket(
            affaire = Prefs.last(c, ListKind.AFFAIRE),
            lieu = Prefs.last(c, ListKind.LIEU),
            partenaire = Prefs.last(c, ListKind.PARTENAIRE),
            raison = Prefs.last(c, ListKind.RAISON),
            nature = nature ?: "Divers",
        )
    }
}

fun JSONObject.optDoubleOrNull(key: String): Double? =
    if (!has(key) || isNull(key)) null else optDouble(key).takeIf { !it.isNaN() }

// ---------- Formatage ----------

object Fmt {
    val fr: Locale = Locale.FRANCE
    private val isoFmt = DateTimeFormatter.ISO_LOCAL_DATE

    fun money(v: Double?, currency: String = "EUR"): String {
        val f = NumberFormat.getCurrencyInstance(fr)
        runCatching { f.currency = Currency.getInstance(currency.uppercase()) }
        return f.format(v ?: 0.0)
    }

    fun amountString(v: Double?): String =
        if (v == null) "" else String.format(Locale.US, "%.2f", v).replace('.', ',')

    fun parseAmount(s: String): Double? {
        val cleaned = s.replace(" ", "").replace(" ", "").replace(" ", "")
            .replace("€", "").replace(',', '.')
        if (cleaned.isEmpty()) return null
        val v = cleaned.toDoubleOrNull() ?: return null
        return round2(v)
    }

    fun round2(v: Double): Double = (v * 100).roundToLong() / 100.0

    fun iso(d: LocalDate): String = d.format(isoFmt)
    fun fromIso(s: String): LocalDate? = runCatching { LocalDate.parse(s, isoFmt) }.getOrNull()
    fun monthKey(d: LocalDate): String = iso(d).take(7)

    /** Semaine ISO, ex. « 2026-S39 » */
    fun weekKey(d: LocalDate): String {
        val wf = WeekFields.ISO
        return String.format(Locale.US, "%04d-S%02d", d.get(wf.weekBasedYear()), d.get(wf.weekOfWeekBasedYear()))
    }

    /** Lundi d'une semaine « 2026-S39 » */
    fun weekStart(key: String): LocalDate? {
        val parts = key.split("-S")
        if (parts.size != 2) return null
        val y = parts[0].toIntOrNull() ?: return null
        val w = parts[1].toIntOrNull() ?: return null
        return runCatching {
            LocalDate.of(y, 1, 4)
                .with(WeekFields.ISO.weekOfWeekBasedYear(), w.toLong())
                .with(java.time.DayOfWeek.MONDAY)
        }.getOrNull()
    }

    fun weekTitle(key: String): String {
        val start = weekStart(key) ?: return key
        val f = DateTimeFormatter.ofPattern("d MMM", fr)
        return "${key.substringAfter('-')} · ${start.format(f)} – ${start.plusDays(6).format(f)}"
    }

    fun kmString(v: Double?): String = amountString(v).removeSuffix(",00")

    fun monthTitle(key: String): String {
        val d = fromIso("$key-01") ?: return key
        val m = d.month.getDisplayName(TextStyle.FULL_STANDALONE, fr)
        return m.replaceFirstChar { it.titlecase(fr) } + " " + d.year
    }

    fun shortDay(d: LocalDate): String = d.format(DateTimeFormatter.ofPattern("d MMM", fr))
    fun longDay(d: LocalDate): String = d.format(DateTimeFormatter.ofPattern("d MMMM yyyy", fr))

    fun safeName(s: String): String {
        val folded = Normalizer.normalize(s, Normalizer.Form.NFD).replace(Regex("\\p{M}+"), "")
        val out = folded.replace(Regex("[^A-Za-z0-9-]+"), "_").trim('_').take(30)
        return out.ifEmpty { "ticket" }
    }
}

// ---------- Réglages ----------

object Prefs {
    const val DEFAULT_MODEL = "claude-sonnet-4-5"
    private fun sp(c: Context) = c.getSharedPreferences("settings", Context.MODE_PRIVATE)

    /** auto | claude | local | none */
    fun engine(c: Context): String = sp(c).getString("engine", "auto") ?: "auto"
    fun setEngine(c: Context, v: String) = sp(c).edit().putString("engine", v).apply()

    fun model(c: Context): String = sp(c).getString("model", DEFAULT_MODEL) ?: DEFAULT_MODEL
    fun setModel(c: Context, v: String) = sp(c).edit().putString("model", v).apply()

    fun apiKey(c: Context): String = sp(c).getString("apiKey", "") ?: ""
    fun setApiKey(c: Context, v: String) = sp(c).edit().putString("apiKey", v.trim()).apply()

    // Listes de la note de frais
    fun list(c: Context, k: ListKind): List<String> {
        val raw = sp(c).getString("list_${k.key}", null) ?: return emptyList()
        return runCatching { org.json.JSONArray(raw).let { a -> (0 until a.length()).map { a.getString(it) } } }.getOrDefault(emptyList())
    }
    fun setList(c: Context, k: ListKind, values: List<String>) =
        sp(c).edit().putString("list_${k.key}", org.json.JSONArray(values).toString()).apply()
    fun last(c: Context, k: ListKind): String = sp(c).getString("last_${k.key}", "") ?: ""
    fun setLast(c: Context, k: ListKind, v: String) = sp(c).edit().putString("last_${k.key}", v).apply()

    // Profil (en-tête de la note de frais)
    fun profile(c: Context, key: String, fallback: String = ""): String = sp(c).getString("profile_$key", fallback) ?: fallback
    fun setProfile(c: Context, key: String, v: String) = sp(c).edit().putString("profile_$key", v).apply()

    // Divers
    fun string(c: Context, key: String): String? = sp(c).getString(key, null)
    fun setString(c: Context, key: String, v: String) = sp(c).edit().putString(key, v).apply()

    fun folderUri(c: Context): String? = sp(c).getString("folderUri", null)
    fun setFolderUri(c: Context, v: String?) = sp(c).edit().putString("folderUri", v).apply()
}

enum class ListKind(val key: String, val title: String, val plural: String) {
    AFFAIRE("affaire", "N° Affaire", "N° d'affaire"),
    LIEU("lieu", "Lieu", "Lieux"),
    PARTENAIRE("partenaire", "Partenaire", "Partenaires"),
    RAISON("raison", "Raison du déplacement", "Raisons du déplacement"),
}

class AppException(message: String) : Exception(message)
