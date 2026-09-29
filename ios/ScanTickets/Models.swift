import Foundation
import Security

// MARK: - Listes de référence

enum Catalog {
    static let natures = ["Restaurant", "Carburant", "Péage", "Parking", "Transport", "Hôtel", "Fournitures", "Télécom", "Divers"]
    static let paiements = ["Carte bancaire", "Espèces", "Chèque", "Virement", "Titre-restaurant", "Autre"]
    /// Nature spéciale pour les trajets en véhicule personnel (pas de ticket)
    static let kmNature = "Kilomètres"

    static func icon(for nature: String) -> String {
        switch nature {
        case "Restaurant": return "fork.knife"
        case "Carburant": return "fuelpump.fill"
        case "Péage": return "road.lanes"
        case "Parking": return "parkingsign"
        case "Transport": return "tram.fill"
        case "Hôtel": return "bed.double.fill"
        case "Fournitures": return "shippingbox.fill"
        case "Télécom": return "antenna.radiowaves.left.and.right"
        case kmNature: return "car.fill"
        default: return "tag.fill"
        }
    }
}

// MARK: - Ticket

struct Ticket: Identifiable, Codable, Hashable {
    var id: String = UUID().uuidString
    var createdAt: Date = Date()
    var commercant: String = ""
    var date: Date = Date()
    var nature: String = "Divers"
    var ttc: Double? = nil
    var tva: Double? = nil
    var ht: Double? = nil
    var devise: String = "EUR"
    var paiement: String = ""
    var descriptionText: String = ""
    var notes: String = ""
    var aVerifier: Bool = false
    var source: String = ""
    /// Chemin relatif de la copie de la photo dans le dossier iCloud choisi
    var cloudPhotoPath: String? = nil

    // Champs de la note de frais
    var affaire: String = ""
    var lieu: String = ""
    var partenaire: String = ""
    var raison: String = ""
    /// Personnes invitées (colonne « Réception »)
    var invites: String = ""
    /// Kilomètres parcourus avec le véhicule personnel (nature « Kilomètres »)
    var km: Double? = nil

    var isKilometres: Bool { nature == Catalog.kmNature }
    var monthKey: String { Fmt.monthKey(date) }
    var weekKey: String { Fmt.weekKey(date) }

    /// Nom de fichier lisible pour la photo : 2026-09-14_Restaurant_Brasserie_du_Port_39,50.jpg
    var photoFileName: String {
        let amount = Fmt.amountString(ttc ?? 0)
        return "\(Fmt.iso(date))_\(Fmt.safeName(nature))_\(Fmt.safeName(commercant))_\(amount).jpg"
    }

    init() {}

    // Décodage tolérant : les tickets enregistrés avec une ancienne version restent lisibles
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        commercant = try c.decodeIfPresent(String.self, forKey: .commercant) ?? ""
        date = try c.decodeIfPresent(Date.self, forKey: .date) ?? Date()
        nature = try c.decodeIfPresent(String.self, forKey: .nature) ?? "Divers"
        ttc = try c.decodeIfPresent(Double.self, forKey: .ttc)
        tva = try c.decodeIfPresent(Double.self, forKey: .tva)
        ht = try c.decodeIfPresent(Double.self, forKey: .ht)
        devise = try c.decodeIfPresent(String.self, forKey: .devise) ?? "EUR"
        paiement = try c.decodeIfPresent(String.self, forKey: .paiement) ?? ""
        descriptionText = try c.decodeIfPresent(String.self, forKey: .descriptionText) ?? ""
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        aVerifier = try c.decodeIfPresent(Bool.self, forKey: .aVerifier) ?? false
        source = try c.decodeIfPresent(String.self, forKey: .source) ?? ""
        cloudPhotoPath = try c.decodeIfPresent(String.self, forKey: .cloudPhotoPath)
        affaire = try c.decodeIfPresent(String.self, forKey: .affaire) ?? ""
        lieu = try c.decodeIfPresent(String.self, forKey: .lieu) ?? ""
        partenaire = try c.decodeIfPresent(String.self, forKey: .partenaire) ?? ""
        raison = try c.decodeIfPresent(String.self, forKey: .raison) ?? ""
        invites = try c.decodeIfPresent(String.self, forKey: .invites) ?? ""
        km = try c.decodeIfPresent(Double.self, forKey: .km)
    }
}

// MARK: - Formatage

enum Fmt {
    static let fr = Locale(identifier: "fr_FR")

    static func money(_ v: Double?, _ currency: String = "EUR") -> String {
        let code = currency.count == 3 ? currency.uppercased() : "EUR"
        return (v ?? 0).formatted(.currency(code: code).locale(fr))
    }

    static func amountString(_ v: Double?) -> String {
        guard let v else { return "" }
        return String(format: "%.2f", v).replacingOccurrences(of: ".", with: ",")
    }

    static func parseAmount(_ s: String) -> Double? {
        let cleaned = s.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\u{00a0}", with: "")
            .replacingOccurrences(of: "€", with: "")
            .replacingOccurrences(of: ",", with: ".")
        guard !cleaned.isEmpty, let v = Double(cleaned), v.isFinite else { return nil }
        return (v * 100).rounded() / 100
    }

    private static let isoFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func iso(_ d: Date) -> String { isoFormatter.string(from: d) }
    static func fromISO(_ s: String) -> Date? { isoFormatter.date(from: s) }
    static func monthKey(_ d: Date) -> String { String(iso(d).prefix(7)) }

    static var isoCalendar: Calendar {
        var c = Calendar(identifier: .iso8601)
        c.locale = fr
        return c
    }

    /// Semaine ISO, ex. « 2026-S39 »
    static func weekKey(_ d: Date) -> String {
        let c = isoCalendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: d)
        return String(format: "%04d-S%02d", c.yearForWeekOfYear ?? 0, c.weekOfYear ?? 0)
    }

    /// Lundi et dimanche d'une semaine « 2026-S39 »
    static func weekBounds(_ key: String) -> (start: Date, end: Date)? {
        let parts = key.split(separator: "-")
        guard parts.count == 2, let y = Int(parts[0]), let w = Int(parts[1].dropFirst()) else { return nil }
        var comps = DateComponents()
        comps.yearForWeekOfYear = y
        comps.weekOfYear = w
        comps.weekday = 2
        guard let start = isoCalendar.date(from: comps),
              let end = isoCalendar.date(byAdding: .day, value: 6, to: start) else { return nil }
        return (start, end)
    }

    static func weekTitle(_ key: String) -> String {
        guard let b = weekBounds(key) else { return key }
        let f = DateFormatter()
        f.locale = fr
        f.dateFormat = "d MMM"
        let num = key.split(separator: "-").last.map(String.init) ?? key
        return "\(num) · \(f.string(from: b.start)) – \(f.string(from: b.end))"
    }

    static func monthTitle(_ key: String) -> String {
        guard let d = fromISO(key + "-01") else { return key }
        let f = DateFormatter()
        f.locale = fr
        f.dateFormat = "LLLL yyyy"
        return f.string(from: d).capitalized(with: fr)
    }

    static func shortDay(_ d: Date) -> String {
        d.formatted(.dateTime.day().month(.abbreviated).locale(fr))
    }

    static func safeName(_ s: String) -> String {
        let folded = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: fr)
        var out = ""
        var lastUnderscore = false
        for ch in folded {
            if ch.isASCII && (ch.isLetter || ch.isNumber || ch == "-") {
                out.append(ch); lastUnderscore = false
            } else if !lastUnderscore {
                out.append("_"); lastUnderscore = true
            }
        }
        let trimmed = out.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return String(trimmed.prefix(30)).isEmpty ? "ticket" : String(trimmed.prefix(30))
    }
}

// MARK: - Réglages

enum Prefs {
    static let defaultModel = "claude-sonnet-4-5"

    /// auto | claude | local | none
    static var engine: String { UserDefaults.standard.string(forKey: "engine") ?? "auto" }
    static var model: String { UserDefaults.standard.string(forKey: "model") ?? defaultModel }

    // Listes pour les champs de la note de frais (modifiables dans Réglages)
    enum ListKind: String, CaseIterable, Identifiable {
        case affaire, lieu, partenaire, raison
        var id: String { rawValue }
        var title: String {
            switch self {
            case .affaire: return "N° Affaire"
            case .lieu: return "Lieu"
            case .partenaire: return "Partenaire"
            case .raison: return "Raison du déplacement"
            }
        }
        var plural: String {
            switch self {
            case .affaire: return "N° d'affaire"
            case .lieu: return "Lieux"
            case .partenaire: return "Partenaires"
            case .raison: return "Raisons du déplacement"
            }
        }
    }

    static func list(_ kind: ListKind) -> [String] {
        UserDefaults.standard.stringArray(forKey: "list_" + kind.rawValue) ?? []
    }

    static func setList(_ kind: ListKind, _ values: [String]) {
        UserDefaults.standard.set(values, forKey: "list_" + kind.rawValue)
    }

    /// Dernière valeur utilisée (proposée par défaut sur le ticket suivant)
    static func last(_ kind: ListKind) -> String {
        UserDefaults.standard.string(forKey: "last_" + kind.rawValue) ?? ""
    }

    static func setLast(_ kind: ListKind, _ v: String) {
        UserDefaults.standard.set(v, forKey: "last_" + kind.rawValue)
    }

    // Profil (en-tête de la note de frais)
    static func profile(_ key: String, _ fallback: String = "") -> String {
        UserDefaults.standard.string(forKey: "profile_" + key) ?? fallback
    }

    static var apiKey: String {
        get { Keychain.get("anthropic-api-key") ?? "" }
        set { Keychain.set(newValue, for: "anthropic-api-key") }
    }
}

enum Keychain {
    private static func baseQuery(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "ScanTickets",
         kSecAttrAccount as String: key]
    }

    static func set(_ value: String, for key: String) {
        let q = baseQuery(key)
        SecItemDelete(q as CFDictionary)
        guard !value.isEmpty else { return }
        var add = q
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func get(_ key: String) -> String? {
        var q = baseQuery(key)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
}

struct AppError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
