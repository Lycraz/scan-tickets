import Foundation
import UIKit
import Vision

/// Résultat de la lecture d'un ticket
struct Analysis {
    var commercant: String?
    var date: Date?
    var ttc: Double?
    var ht: Double?
    var tva: Double?
    var devise: String?
    var paiement: String?
    var nature: String?
    var description: String?
    var confiance = "moyenne"
    var source = ""
    var warning: String?

    func apply(to t: inout Ticket) {
        if let v = commercant, !v.isEmpty { t.commercant = v }
        if let v = date { t.date = v }
        if let v = ttc { t.ttc = v }
        if let v = tva { t.tva = v }
        if let v = ht { t.ht = v }
        if let v = devise, v.count == 3 { t.devise = v.uppercased() }
        if let v = paiement, Catalog.paiements.contains(v) { t.paiement = v }
        if let v = nature, Catalog.natures.contains(v) { t.nature = v }
        if let v = description, !v.isEmpty { t.descriptionText = v }
        if t.ht == nil, let ttc = t.ttc, let tva = t.tva { t.ht = ((ttc - tva) * 100).rounded() / 100 }
        t.source = source
    }
}

enum Analyzer {
    /// Choisit le moteur selon les réglages. Renvoie nil en mode « saisie manuelle ».
    static func run(_ image: UIImage, progress: @escaping (String) -> Void = { _ in }) async throws -> Analysis? {
        let engine = Prefs.engine
        let key = Prefs.apiKey
        if engine == "none" { return nil }
        if engine == "claude" || (engine == "auto" && !key.isEmpty) {
            do {
                progress("Lecture par l'IA…")
                return try await ClaudeClient.analyze(image, key: key, model: Prefs.model)
            } catch {
                if engine == "claude" { throw error }
                progress("IA indisponible, lecture locale…")
                var r = try await localAnalysis(image)
                r.warning = "IA indisponible (\(error.localizedDescription)). Lecture faite sur l'iPhone : vérifiez les montants."
                return r
            }
        }
        progress("Lecture sur l'iPhone…")
        return try await localAnalysis(image)
    }

    static func localAnalysis(_ image: UIImage) async throws -> Analysis {
        let text = try await LocalOCR.recognize(image)
        var r = ReceiptParser.parse(text)
        r.source = "Lecture iPhone"
        r.confiance = "basse"
        return r
    }
}

// MARK: - IA Claude

enum ClaudeClient {
    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    static var prompt: String {
        """
        Tu es un assistant comptable. Analyse cette photo de ticket de caisse, reçu ou facture.
        Réponds UNIQUEMENT avec un objet JSON valide, sans texte autour, avec ces clés :
        {
          "commercant": "nom de l'enseigne ou du commerce",
          "date": "AAAA-MM-JJ",
          "montant_ttc": nombre (total payé),
          "montant_ht": nombre ou null,
          "tva": nombre (montant total de TVA) ou null,
          "devise": "code ISO, ex. EUR",
          "moyen_paiement": une valeur parmi \(Catalog.paiements),
          "nature": une valeur parmi \(Catalog.natures),
          "description": "résumé très court de l'achat (ex. Déjeuner 2 couverts, Gazole 42 L)",
          "confiance": "haute" | "moyenne" | "basse"
        }
        Les nombres utilisent le point décimal. Si une information est absente, mets null.
        Si l'image n'est pas un ticket, mets "confiance": "basse".
        """
    }

    private static func request(_ url: URL, key: String) -> URLRequest {
        var req = URLRequest(url: url)
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.timeoutInterval = 90
        return req
    }

    private static func check(_ data: Data, _ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw AppError("Réponse invalide") }
        guard (200..<300).contains(http.statusCode) else {
            var msg = "Erreur \(http.statusCode)"
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let err = obj["error"] as? [String: Any], let m = err["message"] as? String {
                msg += " : \(m)"
            }
            throw AppError(msg)
        }
    }

    static func analyze(_ image: UIImage, key: String, model: String) async throws -> Analysis {
        guard !key.isEmpty else { throw AppError("Aucune clé API configurée") }
        guard let jpeg = image.resized(maxSide: 1600).jpegData(compressionQuality: 0.8) else {
            throw AppError("Image illisible")
        }
        var req = request(endpoint, key: key)
        req.httpMethod = "POST"
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 800,
            "messages": [[
                "role": "user",
                "content": [
                    ["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": jpeg.base64EncodedString()]],
                    ["type": "text", "text": prompt],
                ],
            ]],
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: req)
        try check(data, response)

        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = obj["content"] as? [[String: Any]] else { throw AppError("Réponse de l'IA illisible") }
        let text = content.compactMap { $0["text"] as? String }.joined()
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end,
              let json = try JSONSerialization.jsonObject(with: Data(text[start...end].utf8)) as? [String: Any]
        else { throw AppError("Réponse de l'IA illisible") }

        var r = Analysis()
        r.commercant = json["commercant"] as? String
        if let d = json["date"] as? String { r.date = Fmt.fromISO(d) }
        r.ttc = number(json["montant_ttc"])
        r.ht = number(json["montant_ht"])
        r.tva = number(json["tva"])
        r.devise = json["devise"] as? String
        r.paiement = json["moyen_paiement"] as? String
        r.nature = json["nature"] as? String
        r.description = json["description"] as? String
        r.confiance = json["confiance"] as? String ?? "moyenne"
        r.source = "IA Claude"
        return r
    }

    private static func number(_ v: Any?) -> Double? {
        if let n = v as? NSNumber { return (n.doubleValue * 100).rounded() / 100 }
        if let s = v as? String { return Fmt.parseAmount(s) }
        return nil
    }

    struct ModelInfo: Identifiable, Hashable { let id: String; let name: String }

    static func listModels(key: String) async throws -> [ModelInfo] {
        let req = request(URL(string: "https://api.anthropic.com/v1/models?limit=100")!, key: key)
        let (data, response) = try await URLSession.shared.data(for: req)
        try check(data, response)
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = obj["data"] as? [[String: Any]] else { return [] }
        return list.compactMap { m in
            guard let id = m["id"] as? String else { return nil }
            return ModelInfo(id: id, name: m["display_name"] as? String ?? id)
        }
    }
}

// MARK: - OCR local (Apple Vision, gratuit, hors ligne)

enum LocalOCR {
    static func recognize(_ image: UIImage) async throws -> String {
        guard let cg = image.resized(maxSide: 2400).cgImage else { throw AppError("Image illisible") }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["fr-FR", "en-US"]
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        try await Task.detached(priority: .userInitiated) {
            try handler.perform([request])
        }.value
        let observations = request.results ?? []
        return groupIntoLines(observations)
    }

    /// Regroupe les blocs de texte situés sur la même ligne (ex. « TOTAL » … « 39,50 »)
    private static func groupIntoLines(_ obs: [VNRecognizedTextObservation]) -> String {
        let items = obs.compactMap { o -> (box: CGRect, text: String)? in
            guard let s = o.topCandidates(1).first?.string else { return nil }
            return (o.boundingBox, s)
        }.sorted { $0.box.midY > $1.box.midY }

        var lines: [[(box: CGRect, text: String)]] = []
        for item in items {
            if var last = lines.last, let ref = last.first,
               abs(ref.box.midY - item.box.midY) < max(ref.box.height, item.box.height) * 0.6 {
                last.append(item)
                lines[lines.count - 1] = last
            } else {
                lines.append([item])
            }
        }
        return lines
            .map { $0.sorted { $0.box.minX < $1.box.minX }.map(\.text).joined(separator: " ") }
            .joined(separator: "\n")
    }
}

// MARK: - Analyse du texte brut

enum ReceiptParser {
    static func parse(_ text: String) -> Analysis {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let low = text.lowercased()
        var r = Analysis()

        // Commerçant : première ligne « parlante »
        r.commercant = lines.first { l in
            l.matches("[a-zà-ÿ]{3,}") &&
            !l.matches("ticket|facture|bienvenue|merci|t[ée]l|siret|www|http|date|caisse")
        }.map { String($0.prefix(60)) }

        // Date JJ/MM/AAAA
        if let g = text.firstGroups(#"(\d{1,2})[/.\-](\d{1,2})[/.\-](\d{2,4})"#),
           let d = Int(g[0]), let m = Int(g[1]), var y = Int(g[2]) {
            if y < 100 { y += 2000 }
            if (1...12).contains(m), (1...31).contains(d) {
                r.date = Fmt.fromISO(String(format: "%04d-%02d-%02d", y, m, d))
            }
        }

        // Montant TTC : priorité aux lignes « à payer / total TTC », puis « total », puis « CB / montant »
        let priorities = [
            #"net\s*[àa]\s*payer|[àa]\s*payer|total\s*ttc|montant\s*ttc"#,
            #"total"#,
            #"\bcb\b|carte|montant|esp[èe]ces"#,
        ]
        for p in priorities {
            let candidates = lines.filter { $0.matches(p) && !$0.matches(#"tva|\bht\b"#) }.flatMap(amounts)
            if let maxV = candidates.max() { r.ttc = maxV; break }
        }
        if r.ttc == nil { r.ttc = lines.flatMap(amounts).max() }

        // TVA : plus gros montant sur les lignes « TVA », hors taux (5,5 / 10 / 20…)
        let rates: Set<Double> = [2.1, 5.5, 10, 20]
        let tvaCandidates = lines.filter { $0.matches("tva") }.flatMap(amounts)
            .filter { !rates.contains($0) && (r.ttc == nil || $0 < r.ttc!) }
        if let t = tvaCandidates.max(), t > 0 { r.tva = t }
        if let ttc = r.ttc, let tva = r.tva { r.ht = ((ttc - tva) * 100).rounded() / 100 }

        r.devise = "EUR"
        r.nature = guessNature(low)
        r.paiement = guessPayment(low)
        return r
    }

    static func amounts(_ line: String) -> [Double] {
        line.allMatches(#"(\d{1,5}(?:[ .]\d{3})*[.,]\d{2})(?!\d)"#).compactMap { raw in
            // Retire les séparateurs de milliers (« 1 234,56 » ou « 1.234,56 »)
            var s = raw
            if s.count > 6 { s = String(s.dropLast(3)).replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ".", with: "") + s.suffix(3) }
            return Fmt.parseAmount(s)
        }
    }

    static func guessNature(_ t: String) -> String {
        let rules: [(String, String)] = [
            ("Carburant", #"carburant|gazole|gasoil|sp ?95|sp ?98|\be10\b|diesel|station|esso|shell|totalenergies|avia|\bbp\b"#),
            ("Péage", #"p[ée]age|autoroute|vinci|sanef|aprr|\basf\b|cofiroute"#),
            ("Parking", #"parking|stationnement|indigo|effia|onepark"#),
            ("Transport", #"sncf|ratp|uber|taxi|bolt|heetch|train|navigo|billet|a[ée]roport|air france"#),
            ("Hôtel", #"h[ôo]tel|ibis|novotel|mercure|campanile|nuit[ée]e|booking|airbnb"#),
            ("Restaurant", #"restaurant|brasserie|caf[ée]|bistro|pizz|burger|mcdo|kfc|sushi|boulangerie|traiteur|couverts?|menu|plat|dessert|boisson"#),
            ("Télécom", #"orange|sfr|bouygues|free mobile|forfait"#),
            ("Fournitures", #"bureau vall[ée]e|fnac|darty|papeterie|amazon|leroy|castorama|fournitures?"#),
        ]
        return rules.first { t.matches($0.1) }?.0 ?? "Divers"
    }

    static func guessPayment(_ t: String) -> String? {
        if t.matches(#"esp[èe]ces|rendu|monnaie rendue"#) { return "Espèces" }
        if t.matches(#"ticket.?resto|titre.?resto|swile|edenred|up d[ée]j|pluxee|sodexo"#) { return "Titre-restaurant" }
        if t.matches(#"ch[èe]que"#) { return "Chèque" }
        if t.matches(#"\bcb\b|carte|visa|mastercard|sans contact|contactless|amex"#) { return "Carte bancaire" }
        return nil
    }
}

// MARK: - Aides

extension String {
    func matches(_ pattern: String) -> Bool {
        range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    func allMatches(_ pattern: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let ns = self as NSString
        return re.matches(in: self, range: NSRange(location: 0, length: ns.length)).map { m in
            ns.substring(with: m.numberOfRanges > 1 ? m.range(at: 1) : m.range)
        }
    }

    func firstGroups(_ pattern: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let m = re.firstMatch(in: self, range: NSRange(location: 0, length: (self as NSString).length))
        else { return nil }
        return (1..<m.numberOfRanges).map { (self as NSString).substring(with: m.range(at: $0)) }
    }
}

extension UIImage {
    /// Redimensionne et remet l'image « à l'endroit » (orientation normalisée)
    func resized(maxSide: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        let scale = longest > maxSide ? maxSide / longest : 1
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: target))
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
