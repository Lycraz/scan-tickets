import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var store: TicketStore

    @AppStorage("engine") private var engine = "auto"
    @AppStorage("model") private var model = Prefs.defaultModel
    @State private var apiKey = Prefs.apiKey
    @State private var models: [ClaudeClient.ModelInfo] = []
    @State private var keyStatus: String?
    @State private var keyOK = false
    @State private var testing = false
    @State private var pickFolder = false
    @State private var info: String?
    @State private var scan: TicketStore.CloudScan?
    @State private var recovering: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Moteur", selection: $engine) {
                        Text("Automatique").tag("auto")
                        Text("IA Claude uniquement").tag("claude")
                        Text("Sur l'iPhone (gratuit)").tag("local")
                        Text("Saisie manuelle").tag("none")
                    }
                    SecureField("Clé API Anthropic (sk-ant-…)", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit(saveKey)
                    Picker("Modèle", selection: $model) {
                        if models.isEmpty {
                            Text(model).tag(model)
                        } else {
                            ForEach(models) { Text($0.name).tag($0.id) }
                        }
                    }
                    Button {
                        Task { await testKey() }
                    } label: {
                        HStack {
                            Text("Enregistrer et tester la clé")
                            Spacer()
                            if testing { ProgressView() }
                            else if let keyStatus {
                                Text(keyStatus).font(.footnote).foregroundStyle(keyOK ? .green : .red)
                            }
                        }
                    }
                    .disabled(testing)
                } header: {
                    Text("Lecture des tickets")
                } footer: {
                    Text("« Automatique » utilise l'IA si une clé est enregistrée, sinon la lecture gratuite de l'iPhone. La clé est stockée dans le trousseau sécurisé de l'iPhone. Créez-la sur console.anthropic.com et fixez-y une limite de dépense.")
                }

                Section {
                    if let name = store.cloudFolderName {
                        LabeledContent("Dossier", value: name)
                        Button("Recopier toutes les photos maintenant") {
                            let n = store.syncAllPhotosToCloud()
                            info = store.lastCloudError ?? "\(n) photo(s) copiée(s) dans « \(name) »."
                        }
                        Button {
                            checkFolder(silentIfEmpty: false)
                        } label: {
                            HStack {
                                Label("Récupérer les tickets du dossier", systemImage: "arrow.clockwise.icloud")
                                if let recovering {
                                    Spacer()
                                    ProgressView()
                                    Text(recovering).font(.footnote).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .disabled(recovering != nil)
                        Button("Changer de dossier") { pickFolder = true }
                        Button("Ne plus utiliser de dossier", role: .destructive) { store.clearCloudFolder() }
                    } else {
                        Button {
                            pickFolder = true
                        } label: {
                            Label("Choisir un dossier iCloud Drive", systemImage: "icloud.and.arrow.up")
                        }
                    }
                    if let err = store.lastCloudError {
                        Text(err).font(.footnote).foregroundStyle(.red)
                    }
                } header: {
                    Text("iCloud Drive")
                } footer: {
                    Text("Chaque ticket enregistré y est copié automatiquement (Photos/AAAA-MM/…), avec une sauvegarde complète (dossier « \(TicketStore.backupFolderName) ») et les exports Excel. Après une réinstallation, choisissez le même dossier : l'app propose de récupérer vos tickets.")
                }

                Section("Note de frais") {
                    NavigationLink { ProfileView() } label: {
                        Label("Profil (en-tête de la note)", systemImage: "person.text.rectangle")
                    }
                    NavigationLink { ListsView() } label: {
                        Label("Listes (affaires, lieux…)", systemImage: "list.bullet.rectangle")
                    }
                    NavigationLink { TemplateView() } label: {
                        Label("Modèle Excel", systemImage: "tablecells")
                    }
                }

                Section("À propos") {
                    LabeledContent("Tickets enregistrés", value: "\(store.tickets.count)")
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    Text("Les données sont aussi visibles dans l'app Fichiers › Sur mon iPhone › Scan Tickets.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Réglages")
            .fileImporter(isPresented: $pickFolder, allowedContentTypes: [.folder]) { result in
                switch result {
                case .success(let url):
                    store.setCloudFolder(url)
                    guard store.lastCloudError == nil else { break }
                    // Récupère d'abord ce qui est déjà dans le dossier, puis y copie les tickets de l'app
                    checkFolder(silentIfEmpty: true)
                    if !store.tickets.isEmpty { _ = store.syncAllPhotosToCloud() }
                case .failure(let error):
                    info = error.localizedDescription
                }
            }
            .confirmationDialog("Tickets trouvés dans le dossier", isPresented: Binding(get: { scan != nil }, set: { if !$0 { scan = nil } }),
                                titleVisibility: .visible, presenting: scan) { found in
                if found.restorable > 0 {
                    Button("Restaurer \(found.restorable) ticket(s) de la sauvegarde") {
                        let n = store.restoreFromBackup()
                        info = "\(n) ticket(s) restauré(s)."
                    }
                }
                if !found.loosePhotos.isEmpty {
                    Button("Importer \(found.loosePhotos.count) photo(s) comme nouveaux tickets") {
                        Task { await importLoose(found.loosePhotos) }
                    }
                }
                Button("Plus tard", role: .cancel) {}
            } message: { found in
                Text(found.restorable > 0
                     ? "Une sauvegarde de l'app a été trouvée. Les tickets déjà présents ne seront pas dupliqués."
                     : "Ces photos n'ont pas de ticket dans l'app. Elles seront ajoutées avec le badge « à vérifier » (date, nature et montant repris du nom du fichier quand c'est possible).")
            }
            .alert("Réglages", isPresented: Binding(get: { info != nil }, set: { if !$0 { info = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(info ?? "")
            }
        }
    }

    /// Cherche une sauvegarde ou des photos à récupérer dans le dossier iCloud
    private func checkFolder(silentIfEmpty: Bool) {
        recovering = "Analyse…"
        let found = store.scanCloudFolder()
        recovering = nil
        if let found, !found.isEmpty {
            scan = found
        } else if !silentIfEmpty {
            info = store.lastCloudError ?? "Rien à récupérer : tous les tickets du dossier sont déjà dans l'app."
        }
    }

    private func importLoose(_ urls: [URL]) async {
        recovering = "0/\(urls.count)"
        let n = await store.importPhotos(urls) { msg in recovering = msg }
        recovering = nil
        info = "\(n) ticket(s) importé(s). Ils sont marqués « à vérifier » : touchez-les pour contrôler."
    }

    private func saveKey() {
        apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        Prefs.apiKey = apiKey
    }

    private func testKey() async {
        saveKey()
        guard !apiKey.isEmpty else { keyStatus = "Aucune clé"; keyOK = false; return }
        testing = true
        defer { testing = false }
        do {
            let list = try await ClaudeClient.listModels(key: apiKey).filter { $0.id.contains("claude") }
            models = list
            // Par défaut : le modèle « Sonnet » le plus récent (bon rapport précision / prix)
            if !list.contains(where: { $0.id == model }),
               let pick = list.first(where: { $0.id.contains("sonnet") }) ?? list.first {
                model = pick.id
            }
            keyStatus = "✓ Clé valide"
            keyOK = true
        } catch {
            keyStatus = "✗ \(error.localizedDescription)"
            keyOK = false
        }
    }
}
