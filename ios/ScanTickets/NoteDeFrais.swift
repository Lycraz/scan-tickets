import Foundation
import Compression

// MARK: - Remplissage du modèle « Note de frais » (fichier Excel de l'entreprise)
//
// Disposition du modèle (feuille « Note de frais ») :
//   En-tête : M2 mois · P2 semaine · T2 année · E3 entité · F4 nom · M4 véhicule · M6 immatriculation
//             S4 N° feuille de mission · I10 CV · I11 moteur · I12 taux (formule) · E48 date
//   Lignes 14 à 44 (31 justificatifs) :
//     B n° de justificatif · C N° affaire · D lieu · E partenaire · F raison
//     H km · J montant km (formule) · K carburant · L péage · M divers transport
//     O invités · P restaurant · Q hôtel · S nature (autres) · T montant (autres)
//   Ligne 46 : sous-totaux · T48 total · T50 net à rembourser

enum NoteDeFrais {
    static let firstRow = 14
    static let lastRow = 44
    static var capacity: Int { lastRow - firstRow + 1 }

    static let cvOptions = ["3 cv", "4 cv", "5 cv", "6 cv", "7 cv"]
    static let moteurOptions = ["Thermique", "Electrique"]
    /// Barème kilométrique du modèle (thermique, électrique)
    static let rates: [String: (Double, Double)] = [
        "3 cv": (0.37, 0.444), "4 cv": (0.407, 0.4884), "5 cv": (0.427, 0.5124),
        "6 cv": (0.447, 0.5364), "7 cv": (0.47, 0.564),
    ]
    static let months = ["JANVIER", "FÉVRIER", "MARS", "AVRIL", "MAI", "JUIN", "JUILLET",
                         "AOÛT", "SEPTEMBRE", "OCTOBRE", "NOVEMBRE", "DÉCEMBRE"]

    /// Colonne du modèle selon la nature du ticket (nil = « Autres paiements »)
    static func column(for nature: String) -> String? {
        switch nature {
        case "Carburant": return "K"
        case "Péage": return "L"
        case "Transport", "Parking": return "M"
        case "Restaurant": return "P"
        case "Hôtel": return "Q"
        default: return nil
        }
    }

    struct Header {
        var mois = ""
        var semaine = ""
        var annee: Int?
        var entite = ""
        var nom = ""
        var vehicule = ""
        var immatriculation = ""
        var feuilleMission = ""
        var cv = "5 cv"
        var moteur = "Thermique"
        var date = Date()
    }

    /// Modèle utilisé : celui importé par l'utilisateur, sinon celui fourni avec l'app
    static var customTemplateURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Modele_note_de_frais.xlsx")
    }

    static func templateData() throws -> Data {
        if let d = try? Data(contentsOf: customTemplateURL) { return d }
        guard let url = Bundle.main.url(forResource: "NoteDeFrais_modele", withExtension: "xlsx") else {
            throw AppError("Aucun modèle de note de frais : importez votre fichier Excel dans Réglages › Note de frais › Modèle Excel.")
        }
        return try Data(contentsOf: url)
    }

    static var hasTemplateInBundle: Bool {
        Bundle.main.url(forResource: "NoteDeFrais_modele", withExtension: "xlsx") != nil
    }

    /// Un modèle est-il disponible (importé ou fourni avec l'app) ?
    static var hasTemplate: Bool {
        FileManager.default.fileExists(atPath: customTemplateURL.path)
            || Bundle.main.url(forResource: "NoteDeFrais_modele", withExtension: "xlsx") != nil
    }

    /// Crée une ou plusieurs notes (31 lignes maximum par note) pour une semaine.
    /// Renvoie les fichiers Excel et, pour chaque ticket, son numéro de justificatif.
    static func build(week: String, tickets: [Ticket], header base: Header) throws -> (files: [URL], numbers: [String: Int]) {
        let sorted = tickets.sorted { $0.date != $1.date ? $0.date < $1.date : $0.createdAt < $1.createdAt }
        guard !sorted.isEmpty else { throw AppError("Aucun ticket pour cette semaine") }
        let template = try templateData()

        var header = base
        if let b = Fmt.weekBounds(week) {
            // Le mois et l'année de la semaine sont ceux de son jeudi (règle ISO)
            let thursday = Fmt.isoCalendar.date(byAdding: .day, value: 3, to: b.start) ?? b.start
            let comps = Calendar(identifier: .gregorian).dateComponents([.month], from: thursday)
            header.mois = months[(comps.month ?? 1) - 1]
        }
        let parts = week.split(separator: "-")
        header.semaine = parts.count == 2 ? String(parts[1]) : week
        header.annee = parts.first.flatMap { Int($0) }

        var files: [URL] = []
        var numbers: [String: Int] = [:]
        let chunks = stride(from: 0, to: sorted.count, by: capacity).map { Array(sorted[$0..<min($0 + capacity, sorted.count)]) }
        for (i, chunk) in chunks.enumerated() {
            let data = try fill(template: template, header: header, lines: chunk)
            var name = "Note_de_frais_\(week)"
            if !header.feuilleMission.isEmpty { name += "_\(Fmt.safeName(header.feuilleMission))" }
            if chunks.count > 1 { name += "_\(i + 1)" }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(name + ".xlsx")
            try? FileManager.default.removeItem(at: url)
            try data.write(to: url, options: .atomic)
            files.append(url)
            for (n, t) in chunk.enumerated() { numbers[t.id] = n + 1 }
        }
        return (files, numbers)
    }

    // MARK: Remplissage

    static func fill(template: Data, header h: Header, lines: [Ticket]) throws -> Data {
        var entries = try ZipReader.entries(template)
        let sheetPath = try sheetPath(named: "Note de frais", in: entries)
        guard let idx = entries.firstIndex(where: { $0.name == sheetPath }),
              let x = String(data: entries[idx].data, encoding: .utf8) else {
            throw AppError("Feuille « Note de frais » introuvable dans le modèle")
        }
        var sheet = SheetXML(x)

        // En-tête
        sheet.set("M2", .text(h.mois))
        sheet.set("P2", .text(h.semaine))
        sheet.set("T2", h.annee.map { SheetXML.Value.number(Double($0)) } ?? SheetXML.Value.empty)
        sheet.set("E3", .text(h.entite))
        sheet.set("F4", .text(h.nom))
        sheet.set("M4", .text(h.vehicule))
        sheet.set("M6", .text(h.immatriculation))
        sheet.set("S4", .text(h.feuilleMission))
        sheet.set("I10", .text(h.cv))
        sheet.set("I11", .text(h.moteur))
        sheet.set("E48", .number(Double(XLSXWriter.excelSerial(h.date))))
        let pair = rates[h.cv] ?? (0, 0)
        let rate = h.moteur == "Electrique" ? pair.1 : pair.0
        sheet.setCached("I12", rate)

        var totals: [String: Double] = ["H": 0, "J": 0, "K": 0, "L": 0, "M": 0, "P": 0, "Q": 0, "T": 0]
        for i in 0..<capacity {
            let r = firstRow + i
            for c in ["C", "D", "E", "F", "H", "K", "L", "M", "O", "P", "Q", "S", "T"] { sheet.set("\(c)\(r)", .empty) }
            if r > firstRow { sheet.setCached("J\(r)", nil) }
            guard i < lines.count else { continue }
            let t = lines[i]
            sheet.set("C\(r)", .text(t.affaire))
            sheet.set("D\(r)", .text(t.lieu))
            sheet.set("E\(r)", .text(t.partenaire))
            sheet.set("F\(r)", .text(t.raison))

            if t.isKilometres {
                let km = t.km ?? 0
                let amount = round2(rate * km)
                sheet.set("H\(r)", .number(km))
                totals["H", default: 0] += km
                totals["J", default: 0] += amount
                // La ligne 14 du modèle n'a pas de formule : on écrit directement le montant
                if r > firstRow { sheet.setCached("J\(r)", amount) } else { sheet.set("J\(r)", .number(amount)) }
                continue
            }
            let amount = t.ttc ?? 0
            if let col = column(for: t.nature) {
                sheet.set("\(col)\(r)", .number(amount))
                totals[col, default: 0] += amount
                if t.nature == "Restaurant", !t.invites.isEmpty { sheet.set("O\(r)", .text(t.invites)) }
            } else {
                let label = t.descriptionText.isEmpty ? t.nature : t.descriptionText
                sheet.set("S\(r)", .text(label))
                sheet.set("T\(r)", .number(amount))
                totals["T", default: 0] += amount
            }
        }
        for c in ["H", "J", "K", "L", "M", "P", "Q", "T"] { sheet.setCached("\(c)46", round2(totals[c] ?? 0)) }
        let total = round2(["J", "K", "L", "M", "P", "Q", "T"].reduce(0) { $0 + (totals[$1] ?? 0) })
        sheet.setCached("T48", total)
        sheet.setCached("T50", total)

        entries[idx].data = Data(sheet.xml.utf8)

        // Excel recalcule tout à l'ouverture ; la chaîne de calcul est supprimée (Excel la reconstruit)
        entries.removeAll { $0.name == "xl/calcChain.xml" }
        entries = entries.map { e in
            var e = e
            if e.name == "xl/workbook.xml", var wb = String(data: e.data, encoding: .utf8) {
                wb = wb.replacingOccurrences(of: " fullCalcOnLoad=\"1\"", with: "")
                wb = wb.replacingOccurrences(of: "<calcPr", with: "<calcPr fullCalcOnLoad=\"1\"")
                e.data = Data(wb.utf8)
            }
            if e.name == "[Content_Types].xml" || e.name == "xl/_rels/workbook.xml.rels",
               let s = String(data: e.data, encoding: .utf8) {
                e.data = Data(removeTags(containing: "calcChain", in: s).utf8)
            }
            return e
        }
        return ZipWriter.archive(entries.map { ($0.name, $0.data) })
    }

    private static func round2(_ v: Double) -> Double { (v * 100).rounded() / 100 }

    /// Retire les balises auto-fermantes qui mentionnent `needle` (ex. l'entrée calcChain)
    private static func removeTags(containing needle: String, in s: String) -> String {
        var out = s
        while let r = out.range(of: needle) {
            guard let start = out[..<r.lowerBound].lastIndex(of: "<"),
                  let end = out[r.upperBound...].range(of: "/>")?.upperBound else { break }
            out.removeSubrange(start..<end)
        }
        return out
    }

    /// Chemin du fichier XML de la feuille portant ce nom (via workbook.xml et ses relations)
    private static func sheetPath(named name: String, in entries: [ZipReader.Entry]) throws -> String {
        guard let wb = entries.first(where: { $0.name == "xl/workbook.xml" }).flatMap({ String(data: $0.data, encoding: .utf8) }),
              let rels = entries.first(where: { $0.name == "xl/_rels/workbook.xml.rels" }).flatMap({ String(data: $0.data, encoding: .utf8) })
        else { throw AppError("Modèle Excel invalide") }
        guard let tagRange = wb.range(of: "<sheet name=\"\(name)\"") ?? wb.range(of: "<sheet name=\"\(XLSXWriter.escape(name))\""),
              let tagEnd = wb[tagRange.upperBound...].range(of: "/>"),
              let rid = attribute("r:id", in: String(wb[tagRange.lowerBound..<tagEnd.upperBound]))
        else { throw AppError("Feuille « \(name) » introuvable dans le modèle") }
        guard let relRange = rels.range(of: "Id=\"\(rid)\"") else { throw AppError("Modèle Excel invalide") }
        let relStart = rels[..<relRange.lowerBound].lastIndex(of: "<") ?? relRange.lowerBound
        let relEnd = rels[relRange.upperBound...].range(of: "/>")?.upperBound ?? rels.endIndex
        guard let target = attribute("Target", in: String(rels[relStart..<relEnd])) else { throw AppError("Modèle Excel invalide") }
        return target.hasPrefix("/") ? String(target.dropFirst()) : "xl/" + target
    }

    private static func attribute(_ name: String, in tag: String) -> String? {
        guard let r = tag.range(of: " \(name)=\"") else { return nil }
        guard let end = tag[r.upperBound...].firstIndex(of: "\"") else { return nil }
        return String(tag[r.upperBound..<end])
    }
}

// MARK: - Modification de cellules dans le XML d'une feuille (en gardant la mise en forme)

struct SheetXML {
    enum Value {
        case text(String)
        case number(Double)
        case empty
    }

    // Le XML est découpé par ligne une seule fois : chaque modification ne touche
    // qu'une petite chaîne (rapide même avec une feuille de 1 000 lignes).
    private var prefix = ""
    private var chunks: [String] = []
    private var suffix = ""
    private var rowIndex: [Int: Int] = [:]

    init(_ xml: String) {
        guard let open = xml.range(of: "<sheetData>"), let close = xml.range(of: "</sheetData>") else {
            prefix = xml
            return
        }
        prefix = String(xml[..<open.upperBound])
        suffix = String(xml[close.lowerBound...])
        let body = String(xml[open.upperBound..<close.lowerBound])
        var parts = body.components(separatedBy: "</row>")
        for k in 0..<(parts.count - 1) { parts[k] += "</row>" }
        chunks = parts
        for (k, chunk) in chunks.enumerated() {
            var search = chunk.startIndex
            while let r = chunk.range(of: "<row r=\"", range: search..<chunk.endIndex) {
                let digits = chunk[r.upperBound...].prefix { $0.isNumber }
                if let n = Int(digits) { rowIndex[n] = k }
                search = r.upperBound
            }
        }
    }

    var xml: String { prefix + chunks.joined() + suffix }

    private static func rowNumber(_ ref: String) -> Int? { Int(ref.drop { $0.isLetter }) }

    /// Position de la cellule <c r="REF" …/> ou <c r="REF" …>…</c> dans le morceau de sa ligne
    private func locate(_ ref: String) -> (chunk: Int, range: Range<String.Index>)? {
        guard let row = Self.rowNumber(ref), let k = rowIndex[row] else { return nil }
        let text = chunks[k]
        guard let start = text.range(of: "<c r=\"\(ref)\"")?.lowerBound,
              let gt = text[start...].firstIndex(of: ">") else { return nil }
        if text[text.index(before: gt)] == "/" { return (k, start..<text.index(after: gt)) }
        guard let close = text[gt...].range(of: "</c>") else { return nil }
        return (k, start..<close.upperBound)
    }

    private func styleAttr(_ cell: Substring) -> String {
        guard let r = cell.range(of: " s=\""), let end = cell[r.upperBound...].firstIndex(of: "\"") else { return "" }
        return " s=\"\(cell[r.upperBound..<end])\""
    }

    /// Remplace la valeur d'une cellule (le style d'origine est conservé)
    mutating func set(_ ref: String, _ value: Value) {
        guard let loc = locate(ref) else { return }
        let k = loc.chunk, range = loc.range
        let s = styleAttr(chunks[k][range])
        let new: String
        switch value {
        case .empty:
            new = "<c r=\"\(ref)\"\(s)/>"
        case .number(let v):
            new = "<c r=\"\(ref)\"\(s)><v>\(format(v))</v></c>"
        case .text(let t):
            new = t.isEmpty ? "<c r=\"\(ref)\"\(s)/>"
                : "<c r=\"\(ref)\"\(s) t=\"inlineStr\"><is><t xml:space=\"preserve\">\(XLSXWriter.escape(t))</t></is></c>"
        }
        chunks[k].replaceSubrange(range, with: new)
    }

    /// Garde la formule de la cellule et met à jour la valeur affichée en cache
    mutating func setCached(_ ref: String, _ value: Double?) {
        guard let loc = locate(ref) else { return }
        let k = loc.chunk, range = loc.range
        var cell = String(chunks[k][range]).replacingOccurrences(of: " t=\"str\"", with: "")
        cell = cell.replacingOccurrences(of: "<v/>", with: "")
        if let vStart = cell.range(of: "<v>"), let vEnd = cell[vStart.upperBound...].range(of: "</v>") {
            cell.removeSubrange(vStart.lowerBound..<vEnd.upperBound)
        }
        if let value {
            if cell.hasSuffix("/>") {
                cell = String(cell.dropLast(2)) + "><v>\(format(value))</v></c>"
            } else {
                cell = String(cell.dropLast(4)) + "<v>\(format(value))</v></c>"
            }
        }
        chunks[k].replaceSubrange(range, with: cell)
    }

    private func format(_ v: Double) -> String {
        v == v.rounded() && abs(v) < 1e15 ? String(Int64(v)) : String(v)
    }
}

// MARK: - Lecture d'un fichier ZIP (.xlsx)

enum ZipReader {
    struct Entry {
        var name: String
        var data: Data
    }

    static func entries(_ zip: Data) throws -> [Entry] {
        let bytes = [UInt8](zip)
        func u16(_ o: Int) -> Int { Int(bytes[o]) | Int(bytes[o + 1]) << 8 }
        func u32(_ o: Int) -> Int { u16(o) | u16(o + 2) << 16 }

        // Fin du répertoire central
        guard bytes.count >= 22 else { throw AppError("Fichier Excel invalide") }
        var eocd = -1
        var i = bytes.count - 22
        while i >= max(0, bytes.count - 65_557) {
            if u32(i) == 0x06054b50 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { throw AppError("Fichier Excel invalide") }
        let count = u16(eocd + 10)
        var p = u32(eocd + 16)

        var result: [Entry] = []
        for _ in 0..<count {
            guard p + 46 <= bytes.count, u32(p) == 0x02014b50 else { throw AppError("Fichier Excel invalide") }
            let method = u16(p + 10)
            let compSize = u32(p + 20)
            let size = u32(p + 24)
            let nameLen = u16(p + 28)
            let extraLen = u16(p + 30)
            let commentLen = u16(p + 32)
            let localOffset = u32(p + 42)
            let name = String(decoding: bytes[(p + 46)..<(p + 46 + nameLen)], as: UTF8.self)
            p += 46 + nameLen + extraLen + commentLen

            let dataStart = localOffset + 30 + u16(localOffset + 26) + u16(localOffset + 28)
            guard dataStart + compSize <= bytes.count else { throw AppError("Fichier Excel invalide") }
            let raw = Array(bytes[dataStart..<(dataStart + compSize)])
            let data: Data
            switch method {
            case 0: data = Data(raw)
            case 8: data = try inflate(raw, expectedSize: size)
            default: throw AppError("Compression non prise en charge dans le modèle")
            }
            if !name.hasSuffix("/") { result.append(Entry(name: name, data: data)) }
        }
        return result
    }

    /// Décompression DEFLATE brute (format utilisé dans les ZIP)
    private static func inflate(_ src: [UInt8], expectedSize: Int) throws -> Data {
        if expectedSize == 0 { return Data() }
        var dst = [UInt8](repeating: 0, count: expectedSize)
        let n = src.withUnsafeBufferPointer { s in
            dst.withUnsafeMutableBufferPointer { d in
                compression_decode_buffer(d.baseAddress!, expectedSize, s.baseAddress!, src.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard n == expectedSize else { throw AppError("Décompression du modèle impossible") }
        return Data(dst)
    }
}
