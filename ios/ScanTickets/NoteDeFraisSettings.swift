import SwiftUI
import UniformTypeIdentifiers

// MARK: - Profil : en-tête de la note de frais

struct ProfileView: View {
    @AppStorage("profile_nom") private var nom = ""
    @AppStorage("profile_entite") private var entite = ""
    @AppStorage("profile_vehicule") private var vehicule = ""
    @AppStorage("profile_immat") private var immat = ""
    @AppStorage("profile_cv") private var cv = "5 cv"
    @AppStorage("profile_moteur") private var moteur = "Thermique"

    var body: some View {
        Form {
            Section {
                TextField("Nom Prénom (ex. LEMERCIER Fabien)", text: $nom)
                    .textInputAutocapitalization(.characters)
                TextField("Entité (ex. CUP)", text: $entite)
                    .textInputAutocapitalization(.characters)
            } header: {
                Text("Salarié")
            }
            Section {
                TextField("Véhicule", text: $vehicule)
                TextField("Immatriculation", text: $immat)
                    .textInputAutocapitalization(.characters)
                Picker("Puissance fiscale", selection: $cv) {
                    ForEach(NoteDeFrais.cvOptions, id: \.self) { Text($0).tag($0) }
                }
                Picker("Moteur", selection: $moteur) {
                    ForEach(NoteDeFrais.moteurOptions, id: \.self) { Text($0).tag($0) }
                }
            } header: {
                Text("Véhicule personnel")
            } footer: {
                Text("Sert au barème kilométrique de la note de frais.")
            }
        }
        .navigationTitle("Profil")
    }
}

// MARK: - Listes : N° affaire, lieux, partenaires, raisons

struct ListsView: View {
    var body: some View {
        Form {
            Section {
                ForEach(Prefs.ListKind.allCases) { kind in
                    NavigationLink {
                        ListEditorView(kind: kind)
                    } label: {
                        LabeledContent(kind.plural, value: "\(Prefs.list(kind).count)")
                    }
                }
            } footer: {
                Text("Ces valeurs se choisissent sur chaque ticket. Le dernier choix est repris automatiquement sur le ticket suivant.")
            }
        }
        .navigationTitle("Listes")
    }
}

struct ListEditorView: View {
    let kind: Prefs.ListKind
    @State private var values: [String] = []
    @State private var newValue = ""
    @FocusState private var focused: Bool

    var body: some View {
        List {
            Section {
                HStack {
                    TextField("Ajouter…", text: $newValue)
                        .focused($focused)
                        .onSubmit(add)
                        .submitLabel(.done)
                    Button(action: add) { Image(systemName: "plus.circle.fill").font(.title3) }
                        .disabled(newValue.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            Section {
                if values.isEmpty {
                    Text("Aucune valeur pour l'instant.").foregroundStyle(.secondary)
                }
                ForEach(values, id: \.self) { Text($0) }
                    .onDelete { values.remove(atOffsets: $0); save() }
                    .onMove { values.move(fromOffsets: $0, toOffset: $1); save() }
            }
        }
        .navigationTitle(kind.plural)
        .toolbar { EditButton() }
        .onAppear { values = Prefs.list(kind) }
    }

    private func add() {
        let v = newValue.trimmingCharacters(in: .whitespaces)
        guard !v.isEmpty, !values.contains(v) else { newValue = ""; return }
        values.append(v)
        newValue = ""
        save()
        focused = true
    }

    private func save() { Prefs.setList(kind, values) }
}

// MARK: - Modèle Excel

struct TemplateView: View {
    @State private var importing = false
    @State private var hasCustom = FileManager.default.fileExists(atPath: NoteDeFrais.customTemplateURL.path)
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                LabeledContent("Modèle utilisé", value: hasCustom ? "Importé" : (NoteDeFrais.hasTemplate ? "Modèle de base" : "Aucun"))
                Button {
                    importing = true
                } label: {
                    Label("Importer un nouveau modèle (.xlsx)", systemImage: "square.and.arrow.down")
                }
                if hasCustom {
                    Button(NoteDeFrais.hasTemplateInBundle ? "Revenir au modèle de base" : "Supprimer le modèle importé", role: .destructive) {
                        try? FileManager.default.removeItem(at: NoteDeFrais.customTemplateURL)
                        hasCustom = false
                    }
                }
            } footer: {
                Text("Un modèle de note de frais générique est fourni avec l'app. L'en-tête (nom, entité, véhicule, immatriculation…) est rempli avec votre Profil. Vous pouvez importer la trame de votre entreprise si elle garde la même disposition : justificatifs lignes 14 à 44, mêmes colonnes et mêmes cases d'en-tête.")
            }
        }
        .navigationTitle("Modèle Excel")
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [UTType(filenameExtension: "xlsx") ?? .data]) { result in
            switch result {
            case .success(let url):
                let ok = url.startAccessingSecurityScopedResource()
                defer { if ok { url.stopAccessingSecurityScopedResource() } }
                do {
                    let data = try Data(contentsOf: url)
                    // Vérifie que le modèle est exploitable avant de l'adopter
                    _ = try NoteDeFrais.fill(template: data, header: .init(), lines: [])
                    try data.write(to: NoteDeFrais.customTemplateURL, options: .atomic)
                    hasCustom = true
                    message = "Modèle importé."
                } catch {
                    message = "Ce fichier ne peut pas servir de modèle : \(error.localizedDescription)"
                }
            case .failure(let error):
                message = error.localizedDescription
            }
        }
        .alert("Modèle Excel", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
    }
}
