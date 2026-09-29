import SwiftUI

struct TicketEditorView: View {
    @EnvironmentObject var store: TicketStore
    @Environment(\.dismiss) private var dismiss

    let image: UIImage?
    let isNew: Bool
    let autoAnalyze: Bool

    @State private var draft: Ticket
    @State private var ttcText: String
    @State private var tvaText: String
    @State private var htText: String
    @State private var analyzing = false
    @State private var status = "Lecture du ticket…"
    @State private var note: String?
    @State private var noteIsWarning = false
    @State private var showPhoto = false
    @State private var confirmDelete = false
    @State private var alertMessage: String?
    @State private var kmText: String

    init(ticket: Ticket, image: UIImage?, isNew: Bool, autoAnalyze: Bool) {
        self.image = image
        self.isNew = isNew
        self.autoAnalyze = autoAnalyze
        _draft = State(initialValue: ticket)
        _ttcText = State(initialValue: Fmt.amountString(ticket.ttc))
        _tvaText = State(initialValue: Fmt.amountString(ticket.tva))
        _htText = State(initialValue: Fmt.amountString(ticket.ht))
        _kmText = State(initialValue: ticket.km.map { Fmt.amountString($0).replacingOccurrences(of: ",00", with: "") } ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                if let image {
                    Section {
                        ZStack {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity, maxHeight: 240)
                                .onTapGesture { showPhoto = true }
                            if analyzing {
                                RoundedRectangle(cornerRadius: 8).fill(.black.opacity(0.55))
                                VStack(spacing: 10) {
                                    ProgressView().tint(.white).controlSize(.large)
                                    Text(status).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                                }
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                    } footer: {
                        if let note {
                            Label(note, systemImage: noteIsWarning ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                                .foregroundStyle(noteIsWarning ? .orange : .green)
                                .font(.footnote)
                        }
                    }
                }

                if draft.isKilometres {
                    Section {
                        DatePicker("Date", selection: $draft.date, displayedComponents: .date)
                            .environment(\.locale, Fmt.fr)
                        HStack {
                            Text("Distance").fontWeight(.semibold)
                            Spacer()
                            TextField("0", text: $kmText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .monospacedDigit()
                                .frame(maxWidth: 120)
                            Text("km").foregroundStyle(.secondary)
                        }
                        TextField("Trajet (ex. Nantes → Rennes)", text: $draft.descriptionText)
                    } header: {
                        Text("Trajet en véhicule personnel")
                    } footer: {
                        Text("Le montant est calculé dans la note de frais selon le barème (CV et moteur réglés dans Réglages).")
                    }
                } else {
                Section("Ticket") {
                    TextField("Commerçant", text: $draft.commercant)
                        .textInputAutocapitalization(.words)
                    DatePicker("Date", selection: $draft.date, displayedComponents: .date)
                        .environment(\.locale, Fmt.fr)
                    Picker("Nature", selection: $draft.nature) {
                        ForEach(Catalog.natures, id: \.self) { n in
                            Label(n, systemImage: Catalog.icon(for: n)).tag(n)
                        }
                    }
                }

                Section("Montants") {
                    amountField("Montant TTC", text: $ttcText, bold: true)
                    amountField("TVA", text: $tvaText)
                    amountField("Montant HT", text: $htText)
                    HStack {
                        Text("Devise")
                        Spacer()
                        TextField("EUR", text: $draft.devise)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.characters)
                            .frame(width: 80)
                    }
                }
                .onChange(of: tvaText) { _, _ in autoHT() }
                .onChange(of: ttcText) { _, _ in autoHT() }

                Section("Détails") {
                    Picker("Paiement", selection: $draft.paiement) {
                        Text("—").tag("")
                        ForEach(Catalog.paiements, id: \.self) { Text($0).tag($0) }
                    }
                    TextField("Description (ex. Déjeuner client)", text: $draft.descriptionText)
                    if draft.nature == "Restaurant" {
                        TextField("Personnes invitées (ex. Mickael Le Fur)", text: $draft.invites)
                            .textInputAutocapitalization(.words)
                    }
                }
                }

                Section {
                    ListPicker(kind: .affaire, selection: $draft.affaire)
                    ListPicker(kind: .lieu, selection: $draft.lieu)
                    ListPicker(kind: .partenaire, selection: $draft.partenaire)
                    ListPicker(kind: .raison, selection: $draft.raison)
                    TextField("Notes", text: $draft.notes, axis: .vertical)
                        .lineLimit(2...5)
                } header: {
                    Text("Note de frais")
                } footer: {
                    Text("Les listes se modifient dans Réglages › Listes de la note de frais.")
                }

                Section {
                    if image != nil {
                        Button {
                            Task { await analyze() }
                        } label: {
                            Label("Relire le ticket", systemImage: "text.viewfinder")
                        }
                        .disabled(analyzing)
                    }
                    if !isNew {
                        Button(role: .destructive) { confirmDelete = true } label: {
                            Label("Supprimer le ticket", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle(draft.isKilometres ? (isNew ? "Nouveau trajet" : "Modifier le trajet") : (isNew ? "Nouveau ticket" : "Modifier"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer", action: save)
                        .bold()
                        .disabled(analyzing)
                }
            }
            .task {
                if autoAnalyze { await analyze() }
            }
            .fullScreenCover(isPresented: $showPhoto) {
                PhotoViewer(image: image)
            }
            .confirmationDialog("Supprimer ce ticket ?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Supprimer", role: .destructive) {
                    store.delete(draft)
                    dismiss()
                }
            }
            .alert("Information manquante", isPresented: Binding(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(alertMessage ?? "")
            }
        }
        .interactiveDismissDisabled(analyzing)
    }

    private func amountField(_ label: String, text: Binding<String>, bold: Bool = false) -> some View {
        HStack {
            Text(label).fontWeight(bold ? .semibold : .regular)
            Spacer()
            TextField("0,00", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .fontWeight(bold ? .semibold : .regular)
                .frame(maxWidth: 140)
            Text(draft.devise == "EUR" ? "€" : draft.devise).foregroundStyle(.secondary)
        }
    }

    private func autoHT() {
        if let ttc = Fmt.parseAmount(ttcText), let tva = Fmt.parseAmount(tvaText) {
            htText = Fmt.amountString(((ttc - tva) * 100).rounded() / 100)
        }
    }

    private func analyze() async {
        guard let image else { return }
        analyzing = true
        defer { analyzing = false }
        do {
            guard let result = try await Analyzer.run(image, progress: { msg in
                Task { @MainActor in status = msg }
            }) else {
                note = "Saisie manuelle : complétez les champs."
                noteIsWarning = false
                return
            }
            result.apply(to: &draft)
            ttcText = Fmt.amountString(draft.ttc)
            tvaText = Fmt.amountString(draft.tva)
            htText = Fmt.amountString(draft.ht)
            let low = result.confiance == "basse"
            noteIsWarning = low || result.warning != nil
            note = result.warning ?? "Lu par \(result.source)" + (low ? " — vérifiez bien les montants." : ". Vérifiez puis enregistrez.")
        } catch {
            noteIsWarning = true
            note = "Lecture impossible : \(error.localizedDescription). Complétez à la main."
        }
    }

    private func save() {
        draft.devise = draft.devise.trimmingCharacters(in: .whitespaces).uppercased()
        if draft.devise.isEmpty { draft.devise = "EUR" }
        if draft.isKilometres {
            draft.km = Fmt.parseAmount(kmText)
            guard let km = draft.km, km > 0 else { alertMessage = "Indiquez le nombre de kilomètres."; return }
            draft.ttc = nil; draft.tva = nil; draft.ht = nil
            if draft.commercant.isEmpty { draft.commercant = "Véhicule personnel" }
        } else {
            draft.commercant = draft.commercant.trimmingCharacters(in: .whitespaces)
            draft.ttc = Fmt.parseAmount(ttcText)
            draft.tva = Fmt.parseAmount(tvaText)
            draft.ht = Fmt.parseAmount(htText)
            guard !draft.commercant.isEmpty else { alertMessage = "Indiquez le commerçant."; return }
            guard draft.ttc != nil else { alertMessage = "Indiquez le montant TTC."; return }
        }
        draft.aVerifier = false
        Prefs.setLast(.affaire, draft.affaire)
        Prefs.setLast(.lieu, draft.lieu)
        Prefs.setLast(.partenaire, draft.partenaire)
        Prefs.setLast(.raison, draft.raison)
        store.save(draft, image: isNew ? image : nil)
        dismiss()
    }
}

struct PhotoViewer: View {
    let image: UIImage?
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .gesture(MagnificationGesture().onChanged { scale = max(1, $0) }.onEnded { _ in
                        withAnimation { scale = 1 }
                    })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 30))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .white.opacity(0.3))
            }
            .padding()
        }
    }
}

/// Choix d'une valeur parmi une liste réglable (N° affaire, lieu, partenaire, raison)
struct ListPicker: View {
    let kind: Prefs.ListKind
    @Binding var selection: String

    var body: some View {
        let options = Prefs.list(kind)
        Picker(kind.title, selection: $selection) {
            Text("—").tag("")
            ForEach(options, id: \.self) { Text($0).tag($0) }
            // Valeur enregistrée qui n'est plus dans la liste
            if !selection.isEmpty && !options.contains(selection) {
                Text(selection).tag(selection)
            }
        }
    }
}

extension Ticket {
    /// Nouveau ticket pré-rempli avec les derniers choix de la note de frais
    static func withDefaults(nature: String? = nil) -> Ticket {
        var t = Ticket()
        t.affaire = Prefs.last(.affaire)
        t.lieu = Prefs.last(.lieu)
        t.partenaire = Prefs.last(.partenaire)
        t.raison = Prefs.last(.raison)
        if let nature { t.nature = nature }
        return t
    }
}
