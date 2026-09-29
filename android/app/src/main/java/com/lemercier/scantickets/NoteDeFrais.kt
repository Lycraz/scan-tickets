package com.lemercier.scantickets

import android.content.Context
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.time.LocalDate
import java.util.zip.ZipEntry
import java.util.zip.ZipInputStream
import java.util.zip.ZipOutputStream
import kotlin.math.roundToLong

// ---------- Remplissage du modèle « Note de frais » (fichier Excel de l'entreprise) ----------
//
// Disposition du modèle (feuille « Note de frais ») :
//   En-tête : M2 mois · P2 semaine · T2 année · E3 entité · F4 nom · M4 véhicule · M6 immatriculation
//             S4 N° feuille de mission · I10 CV · I11 moteur · I12 taux (formule) · E48 date
//   Lignes 14 à 44 (31 justificatifs) :
//     B n° de justificatif · C N° affaire · D lieu · E partenaire · F raison
//     H km · J montant km (formule) · K carburant · L péage · M divers transport
//     O invités · P restaurant · Q hôtel · S nature (autres) · T montant (autres)
//   Ligne 46 : sous-totaux · T48 total · T50 net à rembourser

object NoteDeFrais {
    const val FIRST_ROW = 14
    const val LAST_ROW = 44
    const val CAPACITY = LAST_ROW - FIRST_ROW + 1

    val cvOptions = listOf("3 cv", "4 cv", "5 cv", "6 cv", "7 cv")
    val moteurOptions = listOf("Thermique", "Electrique")
    /** Barème kilométrique du modèle (thermique, électrique) */
    private val rates = mapOf(
        "3 cv" to (0.37 to 0.444), "4 cv" to (0.407 to 0.4884), "5 cv" to (0.427 to 0.5124),
        "6 cv" to (0.447 to 0.5364), "7 cv" to (0.47 to 0.564),
    )
    private val months = listOf("JANVIER", "FÉVRIER", "MARS", "AVRIL", "MAI", "JUIN", "JUILLET",
        "AOÛT", "SEPTEMBRE", "OCTOBRE", "NOVEMBRE", "DÉCEMBRE")

    /** Colonne du modèle selon la nature du ticket (null = « Autres paiements ») */
    fun column(nature: String): String? = when (nature) {
        "Carburant" -> "K"
        "Péage" -> "L"
        "Transport", "Parking" -> "M"
        "Restaurant" -> "P"
        "Hôtel" -> "Q"
        else -> null
    }

    data class Header(
        val mois: String = "",
        val semaine: String = "",
        val annee: Int? = null,
        val entite: String = "",
        val nom: String = "",
        val vehicule: String = "",
        val immatriculation: String = "",
        val feuilleMission: String = "",
        val cv: String = "5 cv",
        val moteur: String = "Thermique",
        val date: LocalDate = LocalDate.now(),
    )

    fun customTemplate(c: Context) = File(c.filesDir, "Modele_note_de_frais.xlsx")

    fun templateBytes(c: Context): ByteArray {
        val custom = customTemplate(c)
        if (custom.exists()) return custom.readBytes()
        return runCatching { c.assets.open("NoteDeFrais_modele.xlsx").use { it.readBytes() } }.getOrElse {
            throw AppException("Aucun modèle de note de frais : importez votre fichier Excel dans Réglages › Note de frais › Modèle Excel.")
        }
    }

    fun hasTemplate(c: Context): Boolean =
        customTemplate(c).exists() || runCatching { c.assets.open("NoteDeFrais_modele.xlsx").close() }.isSuccess

    class Result(val files: List<File>, val numbers: Map<String, Int>)

    /** Crée une ou plusieurs notes (31 lignes maximum par note) pour une semaine */
    fun build(c: Context, week: String, tickets: List<Ticket>, base: Header, outDir: File): Result {
        val sorted = tickets.sortedWith(compareBy<Ticket> { it.date }.thenBy { it.createdAt })
        if (sorted.isEmpty()) throw AppException("Aucun ticket pour cette semaine")
        val template = templateBytes(c)

        // Le mois de la semaine est celui de son jeudi (règle ISO)
        val thursday = Fmt.weekStart(week)?.plusDays(3)
        val header = base.copy(
            mois = thursday?.let { months[it.monthValue - 1] } ?: "",
            semaine = week.substringAfter('-'),
            annee = week.substringBefore('-').toIntOrNull(),
        )

        outDir.mkdirs()
        val files = mutableListOf<File>()
        val numbers = mutableMapOf<String, Int>()
        val chunks = sorted.chunked(CAPACITY)
        chunks.forEachIndexed { i, chunk ->
            var name = "Note_de_frais_$week"
            if (header.feuilleMission.isNotEmpty()) name += "_" + Fmt.safeName(header.feuilleMission)
            if (chunks.size > 1) name += "_${i + 1}"
            val f = File(outDir, "$name.xlsx")
            f.writeBytes(fill(template, header, chunk))
            files += f
            chunk.forEachIndexed { n, t -> numbers[t.id] = n + 1 }
        }
        return Result(files, numbers)
    }

    // ---------- Remplissage ----------

    fun fill(template: ByteArray, h: Header, lines: List<Ticket>): ByteArray {
        val entries = readZip(template)
        val sheetPath = sheetPath("Note de frais", entries)
        val sheet = SheetXml(entries[sheetPath]?.toString(Charsets.UTF_8)
            ?: throw AppException("Feuille « Note de frais » introuvable dans le modèle"))

        sheet.set("M2", h.mois)
        sheet.set("P2", h.semaine)
        sheet.set("T2", h.annee?.toDouble())
        sheet.set("E3", h.entite)
        sheet.set("F4", h.nom)
        sheet.set("M4", h.vehicule)
        sheet.set("M6", h.immatriculation)
        sheet.set("S4", h.feuilleMission)
        sheet.set("I10", h.cv)
        sheet.set("I11", h.moteur)
        sheet.set("E48", XlsxWriter.excelSerial(h.date).toDouble())
        val pair = rates[h.cv] ?: (0.0 to 0.0)
        val rate = if (h.moteur == "Electrique") pair.second else pair.first
        sheet.setCached("I12", rate)

        val totals = mutableMapOf("H" to 0.0, "J" to 0.0, "K" to 0.0, "L" to 0.0, "M" to 0.0, "P" to 0.0, "Q" to 0.0, "T" to 0.0)
        for (i in 0 until CAPACITY) {
            val r = FIRST_ROW + i
            for (col in listOf("C", "D", "E", "F", "H", "K", "L", "M", "O", "P", "Q", "S", "T")) sheet.set("$col$r", null as String?)
            if (r > FIRST_ROW) sheet.setCached("J$r", null)
            val t = lines.getOrNull(i) ?: continue
            sheet.set("C$r", t.affaire)
            sheet.set("D$r", t.lieu)
            sheet.set("E$r", t.partenaire)
            sheet.set("F$r", t.raison)

            if (t.isKilometres) {
                val km = t.km ?: 0.0
                val amount = round2(rate * km)
                sheet.set("H$r", km)
                totals["H"] = totals.getValue("H") + km
                totals["J"] = totals.getValue("J") + amount
                // La ligne 14 du modèle n'a pas de formule : on écrit directement le montant
                if (r > FIRST_ROW) sheet.setCached("J$r", amount) else sheet.set("J$r", amount)
                continue
            }
            val amount = t.ttc ?: 0.0
            val col = column(t.nature)
            if (col != null) {
                sheet.set("$col$r", amount)
                totals[col] = totals.getValue(col) + amount
                if (t.nature == "Restaurant" && t.invites.isNotBlank()) sheet.set("O$r", t.invites)
            } else {
                sheet.set("S$r", t.description.ifBlank { t.nature })
                sheet.set("T$r", amount)
                totals["T"] = totals.getValue("T") + amount
            }
        }
        for (col in listOf("H", "J", "K", "L", "M", "P", "Q", "T")) sheet.setCached("${col}46", round2(totals.getValue(col)))
        val total = round2(listOf("J", "K", "L", "M", "P", "Q", "T").sumOf { totals.getValue(it) })
        sheet.setCached("T48", total)
        sheet.setCached("T50", total)
        entries[sheetPath] = sheet.xml().toByteArray(Charsets.UTF_8)

        // Excel recalcule tout à l'ouverture ; la chaîne de calcul est supprimée (Excel la reconstruit)
        entries.remove("xl/calcChain.xml")
        entries["xl/workbook.xml"]?.let { wb ->
            val s = wb.toString(Charsets.UTF_8).replace(" fullCalcOnLoad=\"1\"", "")
                .replace("<calcPr", "<calcPr fullCalcOnLoad=\"1\"")
            entries["xl/workbook.xml"] = s.toByteArray(Charsets.UTF_8)
        }
        for (name in listOf("[Content_Types].xml", "xl/_rels/workbook.xml.rels")) {
            entries[name]?.let { entries[name] = removeTags("calcChain", it.toString(Charsets.UTF_8)).toByteArray(Charsets.UTF_8) }
        }
        return writeZip(entries)
    }

    private fun round2(v: Double) = (v * 100).roundToLong() / 100.0

    /** Retire les balises auto-fermantes qui mentionnent `needle` */
    private fun removeTags(needle: String, s: String): String {
        var out = s
        while (true) {
            val i = out.indexOf(needle)
            if (i < 0) break
            val start = out.lastIndexOf('<', i)
            val end = out.indexOf("/>", i)
            if (start < 0 || end < 0) break
            out = out.removeRange(start, end + 2)
        }
        return out
    }

    private fun sheetPath(name: String, entries: Map<String, ByteArray>): String {
        val wb = entries["xl/workbook.xml"]?.toString(Charsets.UTF_8) ?: throw AppException("Modèle Excel invalide")
        val rels = entries["xl/_rels/workbook.xml.rels"]?.toString(Charsets.UTF_8) ?: throw AppException("Modèle Excel invalide")
        val tagStart = wb.indexOf("<sheet name=\"${XlsxWriter.esc(name)}\"")
        if (tagStart < 0) throw AppException("Feuille « $name » introuvable dans le modèle")
        val tag = wb.substring(tagStart, wb.indexOf("/>", tagStart) + 2)
        val rid = attribute("r:id", tag) ?: throw AppException("Modèle Excel invalide")
        val relPos = rels.indexOf("Id=\"$rid\"")
        if (relPos < 0) throw AppException("Modèle Excel invalide")
        val rel = rels.substring(rels.lastIndexOf('<', relPos), rels.indexOf("/>", relPos) + 2)
        val target = attribute("Target", rel) ?: throw AppException("Modèle Excel invalide")
        return if (target.startsWith("/")) target.drop(1) else "xl/$target"
    }

    private fun attribute(name: String, tag: String): String? {
        val i = tag.indexOf(" $name=\"")
        if (i < 0) return null
        val start = i + name.length + 3
        return tag.substring(start, tag.indexOf('"', start))
    }

    private fun readZip(bytes: ByteArray): LinkedHashMap<String, ByteArray> {
        val out = LinkedHashMap<String, ByteArray>()
        ZipInputStream(ByteArrayInputStream(bytes)).use { zin ->
            while (true) {
                val e = zin.nextEntry ?: break
                if (!e.isDirectory) out[e.name] = zin.readBytes()
            }
        }
        if (out.isEmpty()) throw AppException("Fichier Excel invalide")
        return out
    }

    private fun writeZip(entries: Map<String, ByteArray>): ByteArray {
        val bos = ByteArrayOutputStream()
        ZipOutputStream(bos).use { z ->
            for ((name, data) in entries) {
                z.putNextEntry(ZipEntry(name))
                z.write(data)
                z.closeEntry()
            }
        }
        return bos.toByteArray()
    }
}

// ---------- Modification de cellules dans le XML d'une feuille (mise en forme conservée) ----------

class SheetXml(xml: String) {
    private val prefix: String
    private val suffix: String
    private val chunks: MutableList<String>
    private val rowIndex = HashMap<Int, Int>()

    init {
        val open = xml.indexOf("<sheetData>")
        val close = xml.indexOf("</sheetData>")
        if (open < 0 || close < 0) {
            prefix = xml; suffix = ""; chunks = mutableListOf()
        } else {
            prefix = xml.substring(0, open + "<sheetData>".length)
            suffix = xml.substring(close)
            val parts = xml.substring(open + "<sheetData>".length, close).split("</row>").toMutableList()
            for (k in 0 until parts.size - 1) parts[k] = parts[k] + "</row>"
            chunks = parts
            val re = Regex("<row r=\"(\\d+)\"")
            chunks.forEachIndexed { k, c -> re.findAll(c).forEach { rowIndex[it.groupValues[1].toInt()] = k } }
        }
    }

    fun xml(): String = prefix + chunks.joinToString("") + suffix

    private fun locate(ref: String): Triple<Int, Int, Int>? {
        val row = ref.dropWhile { it.isLetter() }.toIntOrNull() ?: return null
        val k = rowIndex[row] ?: return null
        val text = chunks[k]
        val start = text.indexOf("<c r=\"$ref\"")
        if (start < 0) return null
        val gt = text.indexOf('>', start)
        if (text[gt - 1] == '/') return Triple(k, start, gt + 1)
        val close = text.indexOf("</c>", gt)
        if (close < 0) return null
        return Triple(k, start, close + 4)
    }

    private fun styleAttr(cell: String): String =
        Regex(" s=\"(\\d+)\"").find(cell)?.let { " s=\"${it.groupValues[1]}\"" } ?: ""

    private fun replace(k: Int, start: Int, end: Int, new: String) {
        chunks[k] = chunks[k].substring(0, start) + new + chunks[k].substring(end)
    }

    /** Texte (vide = cellule vidée) */
    fun set(ref: String, value: String?) {
        val (k, a, b) = locate(ref) ?: return
        val s = styleAttr(chunks[k].substring(a, b))
        val new = if (value.isNullOrEmpty()) "<c r=\"$ref\"$s/>"
        else "<c r=\"$ref\"$s t=\"inlineStr\"><is><t xml:space=\"preserve\">${XlsxWriter.esc(value)}</t></is></c>"
        replace(k, a, b, new)
    }

    /** Nombre (null = cellule vidée) */
    fun set(ref: String, value: Double?) {
        val (k, a, b) = locate(ref) ?: return
        val s = styleAttr(chunks[k].substring(a, b))
        val new = if (value == null) "<c r=\"$ref\"$s/>" else "<c r=\"$ref\"$s><v>${format(value)}</v></c>"
        replace(k, a, b, new)
    }

    /** Garde la formule et met à jour la valeur affichée en cache */
    fun setCached(ref: String, value: Double?) {
        val (k, a, b) = locate(ref) ?: return
        var cell = chunks[k].substring(a, b).replace(" t=\"str\"", "").replace("<v/>", "")
        cell = cell.replaceFirst(Regex("<v>[^<]*</v>"), "")
        if (value != null) {
            cell = if (cell.endsWith("/>")) cell.dropLast(2) + "><v>${format(value)}</v></c>"
            else cell.dropLast(4) + "<v>${format(value)}</v></c>"
        }
        replace(k, a, b, cell)
    }

    private fun format(v: Double): String =
        if (v == Math.rint(v) && kotlin.math.abs(v) < 1e15) v.toLong().toString() else v.toString()
}
