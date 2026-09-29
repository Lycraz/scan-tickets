import Foundation

// MARK: - Export des tickets en .xlsx (sans dépendance externe)

enum ExcelExport {
    static let headers = ["N°", "Date", "Commerçant", "Nature", "Description", "Moyen de paiement",
                          "Montant HT", "TVA", "Montant TTC", "Devise", "Fichier photo", "Notes"]
    static let widths: [Double] = [6, 12, 28, 14, 32, 18, 13, 11, 13, 8, 46, 30]

    /// Crée le fichier dans le dossier temporaire et renvoie son URL
    static func build(tickets: [Ticket], period: String) throws -> URL {
        let sorted = tickets.sorted { $0.date < $1.date }
        let last = sorted.count + 1

        var rows: [[XLSXWriter.Cell]] = [headers.map { XLSXWriter.Cell.text($0, style: 1) }]
        for (i, t) in sorted.enumerated() {
            rows.append([
                .number(Double(i + 1), style: 0),
                .date(t.date),
                .text(t.commercant),
                .text(t.nature),
                .text(t.descriptionText),
                .text(t.paiement),
                t.ht.map { XLSXWriter.Cell.number($0, style: 3) } ?? XLSXWriter.Cell.empty,
                t.tva.map { XLSXWriter.Cell.number($0, style: 3) } ?? XLSXWriter.Cell.empty,
                t.ttc.map { XLSXWriter.Cell.number($0, style: 3) } ?? XLSXWriter.Cell.empty,
                .text(t.devise),
                .text("Photos/\(t.monthKey)/\(t.photoFileName)"),
                .text(t.notes),
            ])
        }
        var total: [XLSXWriter.Cell] = Array(repeating: .empty, count: headers.count)
        total[2] = .text("TOTAL", style: 4)
        total[6] = .formula("SUM(G2:G\(last))", style: 5)
        total[7] = .formula("SUM(H2:H\(last))", style: 5)
        total[8] = .formula("SUM(I2:I\(last))", style: 5)
        rows.append(total)

        let main = XLSXWriter.Sheet(name: "Tickets", widths: widths, rows: rows,
                                    freezeHeader: true, autoFilter: "A1:L\(last)")

        // Récapitulatif par nature (formules, donc à jour si vous modifiez l'onglet Tickets)
        var recap: [[XLSXWriter.Cell]] = [[.text("Nature", style: 1), .text("Nb tickets", style: 1), .text("Total TTC", style: 1)]]
        for (i, n) in Catalog.natures.enumerated() {
            let r = i + 2
            recap.append([
                .text(n),
                .formula("COUNTIF(Tickets!D2:D\(last),A\(r))", style: 0),
                .formula("SUMIF(Tickets!D2:D\(last),A\(r),Tickets!I2:I\(last))", style: 3),
            ])
        }
        let end = Catalog.natures.count + 1
        recap.append([.text("TOTAL", style: 4), .formula("SUM(B2:B\(end))", style: 4), .formula("SUM(C2:C\(end))", style: 5)])
        let recapSheet = XLSXWriter.Sheet(name: "Récap par nature", widths: [20, 12, 14], rows: recap,
                                          freezeHeader: true, autoFilter: nil)

        let data = XLSXWriter.workbook([main, recapSheet])
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Notes_de_frais_\(period).xlsx")
        try? FileManager.default.removeItem(at: url)
        try data.write(to: url, options: .atomic)
        return url
    }
}

// MARK: - Générateur XLSX minimal (Office Open XML + ZIP non compressé)

enum XLSXWriter {
    enum Cell {
        case text(String, style: Int = 0)
        case number(Double, style: Int = 0)
        case date(Date)
        case formula(String, style: Int = 0)
        case empty
    }

    struct Sheet {
        var name: String
        var widths: [Double]
        var rows: [[Cell]]
        var freezeHeader: Bool
        var autoFilter: String?
    }

    // Styles : 0 normal · 1 en-tête · 2 date · 3 montant · 4 gras · 5 montant gras
    static let stylesXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
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
    </styleSheet>
    """

    static func workbook(_ sheets: [Sheet]) -> Data {
        var files: [(String, Data)] = []
        let overrides = sheets.indices.map {
            "<Override PartName=\"/xl/worksheets/sheet\($0 + 1).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>"
        }.joined()
        files.append(("[Content_Types].xml", Data("""
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>\(overrides)</Types>
        """.utf8)))
        files.append(("_rels/.rels", Data("""
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>
        """.utf8)))

        let sheetTags = sheets.enumerated().map { i, s in
            "<sheet name=\"\(escape(s.name))\" sheetId=\"\(i + 1)\" r:id=\"rId\(i + 1)\"/>"
        }.joined()
        let filterNames = sheets.enumerated().compactMap { i, s -> String? in
            guard let f = s.autoFilter else { return nil }
            let absRef = f.split(separator: ":").map { part -> String in
                let letters = part.prefix { $0.isLetter }
                let digits = part.drop { $0.isLetter }
                return "$\(letters)$\(digits)"
            }.joined(separator: ":")
            return "<definedName name=\"_xlnm._FilterDatabase\" localSheetId=\"\(i)\" hidden=\"1\">'\(escape(s.name))'!\(absRef)</definedName>"
        }.joined()
        files.append(("xl/workbook.xml", Data("""
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>\(sheetTags)</sheets>\(filterNames.isEmpty ? "" : "<definedNames>\(filterNames)</definedNames>")<calcPr calcId="191029" fullCalcOnLoad="1"/></workbook>
        """.utf8)))

        let rels = sheets.indices.map {
            "<Relationship Id=\"rId\($0 + 1)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet\($0 + 1).xml\"/>"
        }.joined()
        files.append(("xl/_rels/workbook.xml.rels", Data("""
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\(rels)<Relationship Id="rId\(sheets.count + 1)" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>
        """.utf8)))
        files.append(("xl/styles.xml", Data(stylesXML.utf8)))

        for (i, s) in sheets.enumerated() {
            files.append(("xl/worksheets/sheet\(i + 1).xml", Data(sheetXML(s).utf8)))
        }
        return ZipWriter.archive(files)
    }

    static func sheetXML(_ s: Sheet) -> String {
        var x = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
        x += "<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\">"
        if s.freezeHeader {
            x += "<sheetViews><sheetView workbookViewId=\"0\"><pane ySplit=\"1\" topLeftCell=\"A2\" activePane=\"bottomLeft\" state=\"frozen\"/></sheetView></sheetViews>"
        }
        x += "<cols>"
        for (i, w) in s.widths.enumerated() {
            x += "<col min=\"\(i + 1)\" max=\"\(i + 1)\" width=\"\(w)\" customWidth=\"1\"/>"
        }
        x += "</cols><sheetData>"
        for (r, row) in s.rows.enumerated() {
            x += "<row r=\"\(r + 1)\">"
            for (c, cell) in row.enumerated() {
                let ref = "\(column(c))\(r + 1)"
                switch cell {
                case .empty:
                    continue
                case let .text(v, style):
                    x += "<c r=\"\(ref)\" s=\"\(style)\" t=\"inlineStr\"><is><t xml:space=\"preserve\">\(escape(v))</t></is></c>"
                case let .number(v, style):
                    x += "<c r=\"\(ref)\" s=\"\(style)\"><v>\(v)</v></c>"
                case let .date(d):
                    x += "<c r=\"\(ref)\" s=\"2\"><v>\(excelSerial(d))</v></c>"
                case let .formula(f, style):
                    x += "<c r=\"\(ref)\" s=\"\(style)\"><f>\(escape(f))</f></c>"
                }
            }
            x += "</row>"
        }
        x += "</sheetData>"
        if let f = s.autoFilter { x += "<autoFilter ref=\"\(f)\"/>" }
        x += "</worksheet>"
        return x
    }

    static func column(_ i: Int) -> String {
        var n = i + 1, s = ""
        while n > 0 {
            let r = (n - 1) % 26
            s = String(UnicodeScalar(UInt8(65 + r))) + s
            n = (n - 1) / 26
        }
        return s
    }

    /// Nombre de jours depuis le 30/12/1899 (format de date Excel)
    static func excelSerial(_ d: Date) -> Int {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let day = utc.date(from: c) ?? d
        return Int((day.timeIntervalSince1970 / 86400).rounded()) + 25569
    }

    static func escape(_ s: String) -> String {
        var out = ""
        for ch in s.unicodeScalars {
            switch ch {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&apos;"
            default:
                // Retire les caractères de contrôle interdits en XML
                if ch.value < 0x20 && ch != "\n" && ch != "\t" && ch != "\r" { continue }
                out.unicodeScalars.append(ch)
            }
        }
        return out
    }
}

// MARK: - ZIP (méthode « stockée », suffisant pour un .xlsx)

enum ZipWriter {
    private static let crcTable: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1) }
        return c
    }

    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for b in data { crc = crcTable[Int((crc ^ UInt32(b)) & 0xFF)] ^ (crc >> 8) }
        return crc ^ 0xFFFFFFFF
    }

    static func archive(_ files: [(String, Data)]) -> Data {
        var out = Data()
        var central = Data()
        // Date DOS fixe : 01/01/2024 00:00
        let dosTime: UInt16 = 0
        let dosDate: UInt16 = UInt16(((2024 - 1980) << 9) | (1 << 5) | 1)

        for (name, data) in files {
            let nameData = Data(name.utf8)
            let crc = crc32(data)
            let offset = UInt32(out.count)
            out.append(le32(0x04034b50)); out.append(le16(20)); out.append(le16(0x0800)); out.append(le16(0))
            out.append(le16(dosTime)); out.append(le16(dosDate)); out.append(le32(crc))
            out.append(le32(UInt32(data.count))); out.append(le32(UInt32(data.count)))
            out.append(le16(UInt16(nameData.count))); out.append(le16(0))
            out.append(nameData); out.append(data)

            central.append(le32(0x02014b50)); central.append(le16(20)); central.append(le16(20))
            central.append(le16(0x0800)); central.append(le16(0)); central.append(le16(dosTime)); central.append(le16(dosDate))
            central.append(le32(crc)); central.append(le32(UInt32(data.count))); central.append(le32(UInt32(data.count)))
            central.append(le16(UInt16(nameData.count))); central.append(le16(0)); central.append(le16(0))
            central.append(le16(0)); central.append(le16(0)); central.append(le32(0)); central.append(le32(offset))
            central.append(nameData)
        }
        let cdOffset = UInt32(out.count)
        out.append(central)
        out.append(le32(0x06054b50)); out.append(le16(0)); out.append(le16(0))
        out.append(le16(UInt16(files.count))); out.append(le16(UInt16(files.count)))
        out.append(le32(UInt32(central.count))); out.append(le32(cdOffset)); out.append(le16(0))
        return out
    }

    private static func le16(_ v: UInt16) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
    private static func le32(_ v: UInt32) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
}
