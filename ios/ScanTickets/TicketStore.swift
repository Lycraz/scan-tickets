import Foundation
import UIKit

/// Base de données locale : tickets.json + photos dans le dossier Documents de l'app
/// (visible dans l'app Fichiers > Sur mon iPhone > Scan Tickets),
/// avec copie automatique des photos dans un dossier iCloud Drive choisi par l'utilisateur.
@MainActor
final class TicketStore: ObservableObject {
    @Published private(set) var tickets: [Ticket] = []
    @Published private(set) var cloudFolderName: String?
    @Published var lastCloudError: String?

    private let fm = FileManager.default
    private let docs: URL
    private let thumbCache = NSCache<NSString, UIImage>()

    private var dataURL: URL { docs.appendingPathComponent("tickets.json") }
    var photosDir: URL { docs.appendingPathComponent("Photos", isDirectory: true) }

    init() {
        docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try? fm.createDirectory(at: photosDir, withIntermediateDirectories: true)
        load()
        cloudFolderName = resolveCloudFolder()?.lastPathComponent
    }

    // MARK: Lecture / écriture

    private func load() {
        guard let data = try? Data(contentsOf: dataURL) else { return }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        tickets = (try? dec.decode([Ticket].self, from: data)) ?? []
        sortTickets()
    }

    private func persist() {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(tickets) {
            try? data.write(to: dataURL, options: .atomic)
        }
        backupToCloud()
    }

    private func sortTickets() {
        tickets.sort { a, b in
            if a.date != b.date { return a.date > b.date }
            return a.createdAt > b.createdAt
        }
    }

    func imageURL(_ t: Ticket) -> URL { photosDir.appendingPathComponent(t.id + ".jpg") }

    func image(for t: Ticket) -> UIImage? {
        UIImage(contentsOfFile: imageURL(t).path)
    }

    func thumbnail(for t: Ticket) -> UIImage? {
        let key = t.id as NSString
        if let img = thumbCache.object(forKey: key) { return img }
        guard let full = image(for: t) else { return nil }
        let thumb = full.preparingThumbnail(of: CGSize(width: 140, height: 140 * full.size.height / max(full.size.width, 1))) ?? full
        thumbCache.setObject(thumb, forKey: key)
        return thumb
    }

    /// Enregistre (création ou modification). `image` n'est fourni que pour un nouveau ticket.
    func save(_ ticket: Ticket, image: UIImage? = nil) {
        var t = ticket
        if let image, let data = image.jpegData(compressionQuality: 0.8) {
            try? data.write(to: imageURL(t), options: .atomic)
            thumbCache.removeObject(forKey: t.id as NSString)
        }
        t.cloudPhotoPath = copyPhotoToCloud(t)
        if let i = tickets.firstIndex(where: { $0.id == t.id }) {
            tickets[i] = t
        } else {
            tickets.append(t)
        }
        sortTickets()
        persist()
    }

    func delete(_ t: Ticket) {
        try? fm.removeItem(at: imageURL(t))
        thumbCache.removeObject(forKey: t.id as NSString)
        tickets.removeAll { $0.id == t.id }
        persist()
    }

    var months: [String] {
        Array(Set(tickets.map(\.monthKey))).sorted(by: >)
    }

    var toReviewCount: Int { tickets.filter(\.aVerifier).count }

    // MARK: Dossier iCloud Drive

    private let bookmarkKey = "cloudFolderBookmark"

    func setCloudFolder(_ url: URL) {
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }
        do {
            let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
            cloudFolderName = url.lastPathComponent
            lastCloudError = nil
        } catch {
            lastCloudError = "Impossible d'enregistrer ce dossier : \(error.localizedDescription)"
        }
    }

    func clearCloudFolder() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        cloudFolderName = nil
    }

    private func resolveCloudFolder() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) else {
            return nil
        }
        if stale {
            let ok = url.startAccessingSecurityScopedResource()
            if let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
                UserDefaults.standard.set(fresh, forKey: bookmarkKey)
            }
            if ok { url.stopAccessingSecurityScopedResource() }
        }
        return url
    }

    /// Exécute `body` avec l'accès au dossier iCloud choisi. Renvoie nil si aucun dossier.
    func withCloudFolder<T>(_ body: (URL) throws -> T) -> T? {
        guard let folder = resolveCloudFolder() else { return nil }
        let ok = folder.startAccessingSecurityScopedResource()
        defer { if ok { folder.stopAccessingSecurityScopedResource() } }
        do {
            let result = try body(folder)
            lastCloudError = nil
            return result
        } catch {
            lastCloudError = "iCloud Drive : \(error.localizedDescription)"
            return nil
        }
    }

    /// Copie la photo du ticket dans <dossier>/Photos/<AAAA-MM>/<nom lisible>.jpg
    private func copyPhotoToCloud(_ t: Ticket) -> String? {
        let src = imageURL(t)
        guard fm.fileExists(atPath: src.path) else { return t.cloudPhotoPath }
        let relative = "Photos/\(t.monthKey)/\(t.photoFileName)"
        let result: String? = withCloudFolder { folder in
            let dest = folder.appendingPathComponent(relative)
            // Supprime l'ancienne copie si le nom a changé (ticket modifié)
            if let old = t.cloudPhotoPath, old != relative {
                try? fm.removeItem(at: folder.appendingPathComponent(old))
            }
            try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
            try fm.copyItem(at: src, to: dest)
            return relative
        }
        return result ?? t.cloudPhotoPath
    }

    /// Recopie toutes les photos dans le dossier iCloud (après un changement de dossier par ex.)
    func syncAllPhotosToCloud() -> Int {
        var n = 0
        for i in tickets.indices {
            var t = tickets[i]
            t.cloudPhotoPath = nil
            if let p = copyPhotoToCloud(t) { tickets[i].cloudPhotoPath = p; n += 1 }
        }
        persist()
        return n
    }

    /// Écrit un fichier d'export dans <dossier>/Exports/. Renvoie le nom du fichier si réussi.
    func saveExportToCloud(_ file: URL, subfolder: String? = nil) -> String? {
        withCloudFolder { folder in
            var dir = folder.appendingPathComponent("Exports", isDirectory: true)
            var label = "\(folder.lastPathComponent)/Exports"
            if let subfolder {
                dir = dir.appendingPathComponent(subfolder, isDirectory: true)
                label += "/\(subfolder)"
            }
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let dest = dir.appendingPathComponent(file.lastPathComponent)
            if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
            try fm.copyItem(at: file, to: dest)
            return "\(label)/\(file.lastPathComponent)"
        }
    }

    var weeks: [String] {
        Array(Set(tickets.map(\.weekKey))).sorted(by: >)
    }

    // MARK: Sauvegarde et récupération via le dossier iCloud

    static let backupFolderName = "Sauvegarde Scan Tickets"
    private static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "heic"]

    /// Copie la base (tickets.json) et les photos d'origine dans <dossier>/Sauvegarde Scan Tickets/
    /// pour pouvoir tout retrouver après une réinstallation de l'app.
    private func backupToCloud() {
        guard cloudFolderName != nil, fm.fileExists(atPath: dataURL.path) else { return }
        _ = withCloudFolder { folder -> Bool in
            let dir = folder.appendingPathComponent(Self.backupFolderName, isDirectory: true)
            let photos = dir.appendingPathComponent("Photos", isDirectory: true)
            try fm.createDirectory(at: photos, withIntermediateDirectories: true)
            let dest = dir.appendingPathComponent("tickets.json")
            if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
            try fm.copyItem(at: dataURL, to: dest)
            for t in tickets {
                let src = imageURL(t)
                let d = photos.appendingPathComponent(src.lastPathComponent)
                if fm.fileExists(atPath: src.path), !fm.fileExists(atPath: d.path) {
                    try? fm.copyItem(at: src, to: d)
                }
            }
            return true
        }
    }

    /// Lit un fichier du dossier iCloud en le téléchargeant si besoin (fichier pas encore sur l'iPhone)
    private func coordinatedData(_ url: URL) -> Data? {
        var result: Data?
        var error: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &error) { u in
            result = try? Data(contentsOf: u)
        }
        return result
    }

    /// Nom réel d'un fichier iCloud pas encore téléchargé (« .photo.jpg.icloud » → « photo.jpg »)
    private static func realName(_ name: String) -> String {
        if name.hasPrefix("."), name.hasSuffix(".icloud") {
            return String(name.dropFirst().dropLast(".icloud".count))
        }
        return name
    }

    struct CloudScan {
        var restorable = 0          // tickets de la sauvegarde absents de l'app
        var loosePhotos: [URL] = [] // photos du dossier sans ticket correspondant
        var isEmpty: Bool { restorable == 0 && loosePhotos.isEmpty }
    }

    /// Analyse le dossier iCloud : sauvegarde à restaurer et photos à réimporter
    func scanCloudFolder() -> CloudScan? {
        withCloudFolder { folder -> CloudScan in
            var scan = CloudScan()
            let known = Set(tickets.map(\.id))

            // 1. Sauvegarde complète (créée automatiquement par l'app)
            let backup = folder.appendingPathComponent(Self.backupFolderName)
            if let data = coordinatedData(backup.appendingPathComponent("tickets.json")) {
                let dec = JSONDecoder()
                dec.dateDecodingStrategy = .iso8601
                let saved = (try? dec.decode([Ticket].self, from: data)) ?? []
                scan.restorable = saved.filter { !known.contains($0.id) }.count
            }

            // 2. Photos rangées dans le dossier (Photos/AAAA-MM/…) sans ticket dans l'app
            let used = Set(tickets.compactMap(\.cloudPhotoPath))
            let base = folder.standardizedFileURL.path
            if let e = fm.enumerator(at: folder, includingPropertiesForKeys: nil) {
                for case let url as URL in e {
                    let rel = String(url.standardizedFileURL.path.dropFirst(base.count + 1))
                    if rel.hasPrefix(Self.backupFolderName) || rel.hasPrefix("Exports") { continue }
                    let name = Self.realName(url.lastPathComponent)
                    guard Self.imageExtensions.contains((name as NSString).pathExtension.lowercased()) else { continue }
                    let realURL = url.deletingLastPathComponent().appendingPathComponent(name)
                    let realRel = (rel as NSString).deletingLastPathComponent.isEmpty
                        ? name : (rel as NSString).deletingLastPathComponent + "/" + name
                    if !used.contains(realRel) { scan.loosePhotos.append(realURL) }
                }
            }
            return scan
        }
    }

    /// Restaure les tickets de la sauvegarde qui ne sont pas dans l'app. Renvoie le nombre ajouté.
    func restoreFromBackup() -> Int {
        let added: Int = withCloudFolder { folder -> Int in
            let dir = folder.appendingPathComponent(Self.backupFolderName)
            guard let data = coordinatedData(dir.appendingPathComponent("tickets.json")) else { return 0 }
            let dec = JSONDecoder()
            dec.dateDecodingStrategy = .iso8601
            let saved = try dec.decode([Ticket].self, from: data)
            let known = Set(tickets.map(\.id))
            var n = 0
            for t in saved where !known.contains(t.id) {
                if let img = coordinatedData(dir.appendingPathComponent("Photos/\(t.id).jpg")) {
                    try? img.write(to: imageURL(t), options: .atomic)
                }
                tickets.append(t)
                n += 1
            }
            return n
        } ?? 0
        if added > 0 {
            thumbCache.removeAllObjects()
            sortTickets()
            persist()
        }
        return added
    }

    /// Recrée des tickets à partir de photos du dossier. Les informations sont reprises du nom
    /// du fichier quand il vient de l'app (2026-09-14_Restaurant_Brasserie_39,50.jpg), sinon le ticket est relu.
    func importPhotos(_ urls: [URL], progress: @escaping (String) -> Void) async -> Int {
        var n = 0
        for (i, url) in urls.enumerated() {
            progress("Photo \(i + 1) sur \(urls.count)…")
            guard let data = withCloudFolder({ _ in coordinatedData(url) }) ?? nil,
                  let img = UIImage(data: data)?.resized(maxSide: 2000) else { continue }
            var t = Ticket.withDefaults()
            if let parsed = Self.ticketFromFileName(url.lastPathComponent) {
                t.date = parsed.date
                t.nature = parsed.nature
                t.commercant = parsed.commercant
                t.ttc = parsed.ttc
                t.source = "Import du dossier"
            } else if let r = try? await Analyzer.run(img) {
                r.apply(to: &t)
            }
            t.aVerifier = true
            save(t, image: img)
            n += 1
        }
        return n
    }

    /// Lit « [01_]2026-09-14_Restaurant_Brasserie_du_Port_39,50.jpg »
    static func ticketFromFileName(_ fileName: String) -> Ticket? {
        let stem = (fileName as NSString).deletingPathExtension
        var parts = stem.split(separator: "_").map(String.init)
        guard let di = parts.firstIndex(where: { Fmt.fromISO($0) != nil }), parts.count >= di + 3,
              let date = Fmt.fromISO(parts[di]) else { return nil }
        parts = Array(parts[di...])
        guard let amount = Fmt.parseAmount(parts.last ?? "") else { return nil }
        var t = Ticket()
        t.date = date
        t.ttc = amount
        let natureRaw = parts[1]
        if natureRaw == Fmt.safeName(Catalog.kmNature) {
            return nil
        }
        t.nature = Catalog.natures.first { Fmt.safeName($0) == natureRaw } ?? "Divers"
        t.commercant = parts.dropFirst(2).dropLast().joined(separator: " ")
        if t.commercant == "ticket" { t.commercant = "" }
        return t
    }
}
