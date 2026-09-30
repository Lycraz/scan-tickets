import SwiftUI
import UIKit

struct ExportView: View {
    @EnvironmentObject var store: TicketStore

    enum Mode: String { case note, recap }
    @AppStorage("exportMode") private var mode: Mode = .note

    // Note de frais (modèle de l'entreprise)
    @State private var week = ""
    @State private var feuilleMission = ""

    // Récapitulatif simple
    @State private var month = ""          // "" = tous les mois

    @State private var includePhotos = true
    @State private var saveToCloud = true
    @State private var shareItems: ShareItems?
    @State private var resultMessage: String?
    @State private var working = false

    @State private var created: Created?
    @State private var mailDraft: MailDraft?

    struct ShareItems: Identifiable {
        let id = UUID()
        let urls: [URL]
    }

    /// Résultat d'un export : fichiers créés et texte proposé pour le mail
    struct Created: Identifiable {
        let id = UUID()
        let title: String
        let urls: [URL]
        let info: String?
        let subject: String
        let body: String
    }

    private var weekTickets: [Ticket] { store.tickets.filter { $0.weekKey == week } }
    private var monthTickets: [Ticket] { store.tickets.filter { month.isEmpty || $0.monthKey == month } }
    private var selection: [Ticket] { mode == .note ? weekTickets : monthTickets }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type d'export", selection: $mode) {
                        Text("Note de frais").tag(Mode.note)
                        Text("Récapitulatif").tag(Mode.recap)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                if mode == .note { noteSections } else { recapSections }

                Section {
                    Toggle(mode == .note ? "Joindre les justificatifs numérotés" : "Joindre les photos des tickets", isOn: $includePhotos)
                    if store.cloudFolderName != nil {
                        Toggle("Enregistrer aussi dans « \(store.cloudFolderName ?? "") »", isOn: $saveToCloud)
                    }
                } footer: {
                    Text(store.cloudFolderName == nil
                         ? "Astuce : choisissez un dossier iCloud Drive dans Réglages pour que les photos et les exports y soient rangés automatiquement."
                         : "Les fichiers seront rangés dans le sous-dossier Exports de votre dossier iCloud.")
                }

                Section {
                    Button(action: export) {
                        HStack {
                            Spacer()
                            if working { ProgressView().padding(.trailing, 6) }
                            Label(mode == .note ? "Créer la note de frais" : "Créer le récapitulatif",
                                  systemImage: "tablecells.badge.ellipsis").bold()
                            Spacer()
                        }
                    }
                    .disabled(selection.isEmpty || working)
                }
            }
            .navigationTitle("Export Excel")
            .onAppear {
                if week.isEmpty || !store.weeks.contains(week), let first = store.weeks.first { week = first }
                if month.isEmpty, let first = store.months.first { month = first }
                loadFeuilleMission()
            }
            .onChange(of: week) { _, _ in loadFeuilleMission() }
            .sheet(item: $shareItems) { items in
                ActivityView(items: items.urls)
                    .presentationDetents([.medium, .large])
            }
            .sheet(item: $mailDraft) { draft in
                MailFormView(draft: draft) { msg in resultMessage = msg }
            }
            .confirmationDialog(created?.title ?? "", isPresented: Binding(get: { created != nil }, set: { if !$0 { created = nil } }),
                                titleVisibility: .visible, presenting: created) { c in
                Button("Envoyer par mail") {
                    mailDraft = MailDraft(subject: c.subject, body: c.body, attachments: c.urls)
                }
                Button("Ouvrir / partager…") { shareItems = ShareItems(urls: c.urls) }
                Button("Fermer", role: .cancel) {}
            } message: { c in
                Text(summary(c))
            }
            .alert("Export", isPresented: Binding(get: { resultMessage != nil }, set: { if !$0 { resultMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(resultMessage ?? "")
            }
        }
    }

    // MARK: Note de frais

    @ViewBuilder private var noteSections: some View {
        Section {
            Picker("Semaine", selection: $week) {
                ForEach(store.weeks, id: \.self) { Text(Fmt.weekTitle($0)).tag($0) }
            }
            TextField("N° feuille de mission (ex. FM002158)", text: $feuilleMission)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .onChange(of: feuilleMission) { _, v in
                    UserDefaults.standard.set(v, forKey: "fm_" + week)
                    UserDefaults.standard.set(v, forKey: "fm_last")
                }
            LabeledContent("Lignes", value: "\(weekTickets.count)")
            LabeledContent("Total") {
                Text(Fmt.money(weekTickets.reduce(0) { $0 + ($1.ttc ?? 0) })).bold().monospacedDigit()
            }
            let km = weekTickets.reduce(0) { $0 + ($1.km ?? 0) }
            if km > 0 {
                LabeledContent("Kilomètres", value: "\(Fmt.amountString(km).replacingOccurrences(of: ",00", with: "")) km")
            }
            if weekTickets.count > NoteDeFrais.capacity {
                Label("Plus de \(NoteDeFrais.capacity) lignes : la note sera répartie sur plusieurs fichiers.",
                      systemImage: "doc.on.doc").font(.footnote).foregroundStyle(.secondary)
            }
            if weekTickets.contains(where: \.aVerifier) {
                Label("Certains tickets sont encore « à vérifier ».", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote).foregroundStyle(.orange)
            }
            if !NoteDeFrais.hasTemplate {
                Label("Importez d'abord votre modèle Excel dans Réglages › Note de frais › Modèle Excel.", systemImage: "doc.badge.plus")
                    .font(.footnote).foregroundStyle(.orange)
            }
            if Prefs.profile("nom").isEmpty {
                Label("Renseignez votre nom dans Réglages › Profil pour remplir l'en-tête.", systemImage: "person.crop.circle.badge.exclamationmark")
                    .font(.footnote).foregroundStyle(.orange)
            }
        } header: {
            Text("Note de frais (modèle)")
        } footer: {
            Text("Remplit votre modèle Excel : en-tête, une ligne par justificatif, colonnes selon la nature, kilomètres et totaux.")
        }
    }

    private func summary(_ c: Created) -> String {
        let sheets = c.urls.filter { $0.pathExtension.lowercased() == "xlsx" }.map { $0.lastPathComponent }
        var lines: [String] = sheets
        let photos = c.urls.count - sheets.count
        if photos > 0 { lines.append("+ \(photos) photo(s)") }
        if let info = c.info { lines.append(info) }
        return lines.joined(separator: "\n")
    }

    private func loadFeuilleMission() {
        feuilleMission = UserDefaults.standard.string(forKey: "fm_" + week)
            ?? UserDefaults.standard.string(forKey: "fm_last") ?? ""
    }

    // MARK: Récapitulatif

    @ViewBuilder private var recapSections: some View {
        Section("Période") {
            Picker("Mois", selection: $month) {
                Text("Tous les mois").tag("")
                ForEach(store.months, id: \.self) { Text(Fmt.monthTitle($0)).tag($0) }
            }
            LabeledContent("Tickets", value: "\(monthTickets.count)")
            LabeledContent("Total TTC") {
                Text(Fmt.money(monthTickets.reduce(0) { $0 + ($1.ttc ?? 0) })).bold().monospacedDigit()
            }
            if monthTickets.contains(where: \.aVerifier) {
                Label("Certains tickets sont encore « à vérifier ».", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote).foregroundStyle(.orange)
            }
        }
    }

    // MARK: Export

    private func export() {
        working = true
        defer { working = false }
        do {
            if mode == .note { try exportNote() } else { try exportRecap() }
        } catch {
            resultMessage = "Export impossible : \(error.localizedDescription)"
        }
    }

    private func exportNote() throws {
        let header = NoteDeFrais.Header(
            entite: Prefs.profile("entite"),
            nom: Prefs.profile("nom"),
            vehicule: Prefs.profile("vehicule"),
            immatriculation: Prefs.profile("immat"),
            feuilleMission: feuilleMission.trimmingCharacters(in: .whitespaces),
            cv: Prefs.profile("cv", "5 cv"),
            moteur: Prefs.profile("moteur", "Thermique"),
            date: Date()
        )
        let result = try NoteDeFrais.build(week: week, tickets: weekTickets, header: header)
        var urls = result.files
        if includePhotos {
            // Justificatifs numérotés comme la colonne « Just » : 01_…, 02_…
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Justificatifs_\(week)", isDirectory: true)
            try? FileManager.default.removeItem(at: dir)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let multi = result.files.count > 1
            let sorted = weekTickets.sorted { $0.date != $1.date ? $0.date < $1.date : $0.createdAt < $1.createdAt }
            for (i, t) in sorted.enumerated() {
                let src = store.imageURL(t)
                guard FileManager.default.fileExists(atPath: src.path), let n = result.numbers[t.id] else { continue }
                let prefix = multi ? "F\(i / NoteDeFrais.capacity + 1)-" : ""
                let dest = dir.appendingPathComponent(String(format: "%@%02d_", prefix, n) + t.photoFileName)
                try? FileManager.default.removeItem(at: dest)
                try? FileManager.default.copyItem(at: src, to: dest)
                urls.append(dest)
            }
        }
        var info: String?
        if saveToCloud, store.cloudFolderName != nil {
            var saved = 0
            for u in urls where store.saveExportToCloud(u, subfolder: week) != nil { saved += 1 }
            info = saved == urls.count
                ? "Enregistrée dans iCloud Drive : \(store.cloudFolderName ?? "")/Exports/\(week)"
                : (store.lastCloudError ?? "Impossible d'écrire dans le dossier iCloud.")
        }
        let nom = Prefs.profile("nom")
        let fm = header.feuilleMission
        let total = weekTickets.reduce(0) { $0 + ($1.ttc ?? 0) }
        var subject = "Note de frais \(week)"
        if !fm.isEmpty { subject += " – \(fm)" }
        if !nom.isEmpty { subject += " – \(nom)" }
        var text = "Bonjour,\n\nVeuillez trouver ci-joint ma note de frais de la semaine \(Fmt.weekTitle(week))"
        if !fm.isEmpty { text += " (feuille de mission \(fm))" }
        text += " : \(weekTickets.count) ligne(s), total \(Fmt.money(total))."
        if includePhotos { text += "\nLes justificatifs sont joints, numérotés comme dans la colonne « Just »." }
        text += "\n\nCordialement,\n\(nom)"
        created = Created(title: "Note de frais créée", urls: urls, info: info, subject: subject, body: text)
    }

    private func exportRecap() throws {
        let period = month.isEmpty ? "tout" : month
        let xlsx = try ExcelExport.build(tickets: monthTickets, period: period)
        var urls = [xlsx]
        if includePhotos {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Photos_\(period)", isDirectory: true)
            try? FileManager.default.removeItem(at: dir)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            for t in monthTickets {
                let src = store.imageURL(t)
                guard FileManager.default.fileExists(atPath: src.path) else { continue }
                let dest = dir.appendingPathComponent(t.photoFileName)
                try? FileManager.default.removeItem(at: dest)
                try? FileManager.default.copyItem(at: src, to: dest)
                urls.append(dest)
            }
        }
        var info: String?
        if saveToCloud, store.cloudFolderName != nil {
            if let path = store.saveExportToCloud(xlsx) {
                info = "Enregistré dans iCloud Drive : \(path)"
            } else {
                info = store.lastCloudError ?? "Impossible d'écrire dans le dossier iCloud."
            }
        }
        let nom = Prefs.profile("nom")
        let label = month.isEmpty ? "tous les mois" : Fmt.monthTitle(month)
        let total = monthTickets.reduce(0) { $0 + ($1.ttc ?? 0) }
        var text = "Bonjour,\n\nVeuillez trouver ci-joint le récapitulatif de mes frais (\(label)) : \(monthTickets.count) ticket(s), total \(Fmt.money(total))."
        if includePhotos { text += "\nLes photos des tickets sont jointes." }
        text += "\n\nCordialement,\n\(nom)"
        created = Created(title: "Récapitulatif créé", urls: urls, info: info,
                          subject: "Récapitulatif des frais – \(label)" + (nom.isEmpty ? "" : " – \(nom)"), body: text)
    }
}

/// Feuille de partage iOS (Enregistrer dans Fichiers, Mail, AirDrop…)
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
