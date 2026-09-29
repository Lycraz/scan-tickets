package com.lemercier.scantickets

import java.io.File
import java.io.FileOutputStream
import java.time.LocalDate
import java.time.temporal.ChronoUnit
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

// ---------- Export des tickets en .xlsx (sans dépendance externe) ----------

object ExcelExport {
    private val headers = listOf("N°", "Date", "Commerçant", "Nature", "Description", "Moyen de paiement",
        "Montant HT", "TVA", "Montant TTC", "Devise", "Fichier photo", "Notes")
    private val widths = listOf(6.0, 12.0, 28.0, 14.0, 32.0, 18.0, 13.0, 11.0, 13.0, 8.0, 46.0, 30.0)

    fun build(tickets: List<Ticket>, period: String, outDir: File): File {
        val sorted = tickets.sortedBy { it.date }
        val last = sorted.size + 1

        val rows = mutableListOf<List<XlsxWriter.Cell>>()
        rows.add(headers.map { XlsxWriter.Cell.Text(it, 1) })
        sorted.forEachIndexed { i, t ->
            rows.add(listOf(
                XlsxWriter.Cell.Num((i + 1).toDouble()),
                XlsxWriter.Cell.Date(t.date),
                XlsxWriter.Cell.Text(t.commercant),
                XlsxWriter.Cell.Text(t.nature),
                XlsxWriter.Cell.Text(t.description),
                XlsxWriter.Cell.Text(t.paiement),
                t.ht?.let { XlsxWriter.Cell.Num(it, 3) } ?: XlsxWriter.Cell.Empty,
                t.tva?.let { XlsxWriter.Cell.Num(it, 3) } ?: XlsxWriter.Cell.Empty,
                t.ttc?.let { XlsxWriter.Cell.Num(it, 3) } ?: XlsxWriter.Cell.Empty,
                XlsxWriter.Cell.Text(t.devise),
                XlsxWriter.Cell.Text("Photos/${t.monthKey}/${t.photoFileName}"),
                XlsxWriter.Cell.Text(t.notes),
            ))
        }
        val total = MutableList<XlsxWriter.Cell>(headers.size) { XlsxWriter.Cell.Empty }
        total[2] = XlsxWriter.Cell.Text("TOTAL", 4)
        total[6] = XlsxWriter.Cell.Formula("SUM(G2:G$last)", 5)
        total[7] = XlsxWriter.Cell.Formula("SUM(H2:H$last)", 5)
        total[8] = XlsxWriter.Cell.Formula("SUM(I2:I$last)", 5)
        rows.add(total)

        val recap = mutableListOf<List<XlsxWriter.Cell>>()
        recap.add(listOf("Nature", "Nb tickets", "Total TTC").map { XlsxWriter.Cell.Text(it, 1) })
        Catalog.natures.forEachIndexed { i, n ->
            val r = i + 2
            recap.add(listOf(
                XlsxWriter.Cell.Text(n),
                XlsxWriter.Cell.Formula("COUNTIF(Tickets!D2:D$last,A$r)", 0),
                XlsxWriter.Cell.Formula("SUMIF(Tickets!D2:D$last,A$r,Tickets!I2:I$last)", 3),
            ))
        }
        val end = Catalog.natures.size + 1
        recap.add(listOf(
            XlsxWriter.Cell.Text("TOTAL", 4),
            XlsxWriter.Cell.Formula("SUM(B2:B$end)", 4),
            XlsxWriter.Cell.Formula("SUM(C2:C$end)", 5),
        ))

        outDir.mkdirs()
        val file = File(outDir, "Notes_de_frais_$period.xlsx")
        XlsxWriter.write(
            file,
            listOf(
                XlsxWriter.Sheet("Tickets", widths, rows, "A1:L$last"),
                XlsxWriter.Sheet("Récap par nature", listOf(20.0, 12.0, 14.0), recap, null),
            ),
        )
        return file
    }
}

// ---------- Générateur XLSX minimal (Office Open XML) ----------

object XlsxWriter {
    sealed class Cell {
        data class Text(val value: String, val style: Int = 0) : Cell()
        data class Num(val value: Double, val style: Int = 0) : Cell()
        data class Date(val value: LocalDate) : Cell()
        data class Formula(val value: String, val style: Int = 0) : Cell()
        data object Empty : Cell()
    }

    data class Sheet(val name: String, val widths: List<Double>, val rows: List<List<Cell>>, val autoFilter: String?)

    // Styles : 0 normal · 1 en-tête · 2 date · 3 montant · 4 gras · 5 montant gras
    private val STYLES = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
<numFmts count="1"><numFmt numFmtId="164" formatCode="dd/mm/yyyy"/></numFmts>
<fonts count="3"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font></fonts>
<fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FF4F46E5"/><bgColor indexed="64"/></patternFill></fill></fills>
<borders count="2"><border><left/><right/><top/><bottom/><diagonal/></border><border><left/><right/><top style="medium"/><bottom/><diagonal/></border></borders>
<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
<cellXfs count="6">
<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
<xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1"/>
<xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>
<xf numFmtId="4" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>
<xf numFmtId="0" fontId="2" fillId="0" borderId="1" xfId="0" applyFont="1" applyBorder="1"/>
<xf numFmtId="4" fontId="2" fillId="0" borderId="1" xfId="0" applyNumberFormat="1" applyFont="1" applyBorder="1"/>
</cellXfs>
<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
</styleSheet>"""

    private const val HEAD = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"

    fun write(file: File, sheets: List<Sheet>) {
        val files = linkedMapOf<String, String>()
        val overrides = sheets.indices.joinToString("") {
            "<Override PartName=\"/xl/worksheets/sheet${it + 1}.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>"
        }
        files["[Content_Types].xml"] = HEAD +
            "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\">" +
            "<Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/>" +
            "<Default Extension=\"xml\" ContentType=\"application/xml\"/>" +
            "<Override PartName=\"/xl/workbook.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml\"/>" +
            "<Override PartName=\"/xl/styles.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml\"/>" +
            overrides + "</Types>"
        files["_rels/.rels"] = HEAD +
            "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">" +
            "<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"xl/workbook.xml\"/>" +
            "</Relationships>"

        val sheetTags = sheets.mapIndexed { i, s ->
            "<sheet name=\"${esc(s.name)}\" sheetId=\"${i + 1}\" r:id=\"rId${i + 1}\"/>"
        }.joinToString("")
        val filters = sheets.mapIndexedNotNull { i, s ->
            s.autoFilter?.let { f ->
                val abs = f.split(':').joinToString(":") { part ->
                    val letters = part.takeWhile { it.isLetter() }
                    "\$" + letters + "\$" + part.drop(letters.length)
                }
                "<definedName name=\"_xlnm._FilterDatabase\" localSheetId=\"$i\" hidden=\"1\">'${esc(s.name)}'!$abs</definedName>"
            }
        }.joinToString("")
        files["xl/workbook.xml"] = HEAD +
            "<workbook xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\">" +
            "<sheets>$sheetTags</sheets>" +
            (if (filters.isEmpty()) "" else "<definedNames>$filters</definedNames>") +
            "<calcPr calcId=\"191029\" fullCalcOnLoad=\"1\"/></workbook>"

        val rels = sheets.indices.joinToString("") {
            "<Relationship Id=\"rId${it + 1}\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet${it + 1}.xml\"/>"
        }
        files["xl/_rels/workbook.xml.rels"] = HEAD +
            "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">$rels" +
            "<Relationship Id=\"rId${sheets.size + 1}\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/>" +
            "</Relationships>"
        files["xl/styles.xml"] = STYLES
        sheets.forEachIndexed { i, s -> files["xl/worksheets/sheet${i + 1}.xml"] = sheetXml(s) }

        ZipOutputStream(FileOutputStream(file)).use { zip ->
            for ((name, content) in files) {
                zip.putNextEntry(ZipEntry(name))
                zip.write(content.toByteArray(Charsets.UTF_8))
                zip.closeEntry()
            }
        }
    }

    private fun sheetXml(s: Sheet): String {
        val x = StringBuilder(HEAD)
        x.append("<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\">")
        x.append("<sheetViews><sheetView workbookViewId=\"0\"><pane ySplit=\"1\" topLeftCell=\"A2\" activePane=\"bottomLeft\" state=\"frozen\"/></sheetView></sheetViews>")
        x.append("<cols>")
        s.widths.forEachIndexed { i, w -> x.append("<col min=\"${i + 1}\" max=\"${i + 1}\" width=\"$w\" customWidth=\"1\"/>") }
        x.append("</cols><sheetData>")
        s.rows.forEachIndexed { r, row ->
            x.append("<row r=\"${r + 1}\">")
            row.forEachIndexed { c, cell ->
                val ref = "${column(c)}${r + 1}"
                when (cell) {
                    is Cell.Empty -> {}
                    is Cell.Text -> x.append("<c r=\"$ref\" s=\"${cell.style}\" t=\"inlineStr\"><is><t xml:space=\"preserve\">${esc(cell.value)}</t></is></c>")
                    is Cell.Num -> x.append("<c r=\"$ref\" s=\"${cell.style}\"><v>${cell.value}</v></c>")
                    is Cell.Date -> x.append("<c r=\"$ref\" s=\"2\"><v>${excelSerial(cell.value)}</v></c>")
                    is Cell.Formula -> x.append("<c r=\"$ref\" s=\"${cell.style}\"><f>${esc(cell.value)}</f></c>")
                }
            }
            x.append("</row>")
        }
        x.append("</sheetData>")
        s.autoFilter?.let { x.append("<autoFilter ref=\"$it\"/>") }
        x.append("</worksheet>")
        return x.toString()
    }

    fun column(i: Int): String {
        var n = i + 1
        val sb = StringBuilder()
        while (n > 0) {
            val r = (n - 1) % 26
            sb.insert(0, ('A' + r))
            n = (n - 1) / 26
        }
        return sb.toString()
    }

    /** Nombre de jours depuis le 30/12/1899 (format de date Excel) */
    fun excelSerial(d: LocalDate): Long = ChronoUnit.DAYS.between(LocalDate.of(1899, 12, 30), d)

    fun esc(s: String): String {
        val sb = StringBuilder()
        for (ch in s) {
            when (ch) {
                '&' -> sb.append("&amp;")
                '<' -> sb.append("&lt;")
                '>' -> sb.append("&gt;")
                '"' -> sb.append("&quot;")
                '\'' -> sb.append("&apos;")
                else -> if (ch >= ' ' || ch == '\n' || ch == '\t' || ch == '\r') sb.append(ch)
            }
        }
        return sb.toString()
    }
}
