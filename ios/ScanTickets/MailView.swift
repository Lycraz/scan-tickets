import SwiftUI
import MessageUI
import UIKit

// ---------- Envoi par e-mail (note de frais, récapitulatif, justificatifs) ----------

/// Mémoire des adresses e-mail déjà utilisées
enum MailMemory {
    private static let recentKey = "mail_recent"

    static var recent: [String] { UserDefaults.standard.stringArray(forKey: recentKey) ?? [] }

    /// Ajoute les adresses en tête de liste (sans doublon, 12 au maximum)
    static func remember(_ addresses: [String]) {
        guard !addresses.isEmpty else { return }
        var list = recent.filter { old in !addresses.contains { $0.caseInsensitiveCompare(old) == .orderedSame } }
        list.insert(contentsOf: addresses, at: 0)
        UserDefaults.standard.set(Array(list.prefix(12)), forKey: recentKey)
    }

    static func forget(_ address: String) {
        UserDefaults.standard.set(recent.filter { $0 != address }, forKey: recentKey)
    }

    static var lastTo: String {
        get { UserDefaults.standard.string(forKey: "mail_to") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "mail_to") }
    }
    static var lastCc: String {
        get { UserDefaults.standard.string(forKey: "mail_cc") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "mail_cc") }
    }

    /// « a@b.fr, c@d.fr » → ["a@b.fr", "c@d.fr"]
    static func split(_ s: String) -> [String] {
        s.split(whereSeparator: { ",; \n".contains($0) })
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    static func isValid(_ a: String) -> Bool {
        a.range(of: #"^[^@\s]+@[^@\s]+\.[^@\s]+$"#, options: .regularExpression) != nil
    }

    /// Ajoute une adresse à un champ « À » ou « Cc » si elle n'y est pas déjà
    static func adding(_ address: String, to field: String) -> String {
        var list = split(field)
        if !list.contains(where: { $0.caseInsensitiveCompare(address) == .orderedSame }) { list.append(address) }
        return list.joined(separator: ", ")
    }
}

/// Contenu proposé pour le mail
struct MailDraft: Identifiable {
    let id = UUID()
    var subject: String
    var body: String
    var attachments: [URL]
}

/// Formulaire d'envoi : destinataires (avec mémoire), objet, message, pièces jointes
struct MailFormView: View {
    let draft: MailDraft
    /// Appelé avec un message à afficher une fois le mail envoyé
    var onFinish: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var to = MailMemory.lastTo
    @State private var cc = MailMemory.lastCc
    @State private var subject = ""
    @State private var messageBody = ""
    @State private var recent = MailMemory.recent
    @State private var showComposer = false
    @State private var sent = false
    @State private var fallbackInfo = false
    @State private var fallbackShare = false
    @State private var error: String?

    private static let sizeLimit: Int64 = 20 * 1024 * 1024

    private var totalSize: Int64 {
        draft.attachments.reduce(0) { sum, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            return sum + Int64(size)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("À", text: $to, prompt: Text("À : adresse@entreprise.fr"))
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Cc", text: $cc, prompt: Text("Cc (facultatif)"))
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Destinataires")
                } footer: {
                    Text("Plusieurs adresses : séparez-les par une virgule. Les adresses utilisées sont mémorisées.")
                }

                if !recent.isEmpty {
                    Section {
                        ForEach(recent, id: \.self) { address in
                            HStack {
                                Text(address).lineLimit(1).truncationMode(.middle)
                                Spacer()
                                Button("À") { to = MailMemory.adding(address, to: to) }
                                    .buttonStyle(.bordered).controlSize(.small)
                                Button("Cc") { cc = MailMemory.adding(address, to: cc) }
                                    .buttonStyle(.bordered).controlSize(.small)
                            }
                        }
                        .onDelete { offsets in
                            offsets.map { recent[$0] }.forEach(MailMemory.forget)
                            recent = MailMemory.recent
                        }
                    } header: {
                        Text("Adresses mémorisées")
                    } footer: {
                        Text("Balayez une adresse vers la gauche pour l'oublier.")
                    }
                }

                Section("Message") {
                    TextField("Objet", text: $subject)
                    TextEditor(text: $messageBody)
                        .frame(minHeight: 150)
                }

                Section {
                    ForEach(draft.attachments, id: \.self) { url in
                        Label(url.lastPathComponent,
                              systemImage: url.pathExtension.lowercased() == "xlsx" ? "tablecells" : "photo")
                            .font(.footnote)
                            .lineLimit(1).truncationMode(.middle)
                    }
                    LabeledContent("Taille totale", value: ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file))
                    if totalSize > Self.sizeLimit {
                        Label("Plus de 20 Mo : certaines messageries refusent les mails aussi lourds. Désactivez « Joindre les justificatifs » ou envoyez en plusieurs fois.",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote).foregroundStyle(.orange)
                    }
                } header: {
                    Text("Pièces jointes (\(draft.attachments.count))")
                }
            }
            .navigationTitle("Envoyer par mail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Continuer", action: send)
                        .bold()
                        .disabled(MailMemory.split(to).isEmpty)
                }
            }
            .onAppear {
                if subject.isEmpty { subject = draft.subject }
                if messageBody.isEmpty { messageBody = draft.body }
            }
            .sheet(isPresented: $showComposer, onDismiss: {
                if sent {
                    onFinish("Mail envoyé ✓")
                    dismiss()
                }
            }) {
                MailComposer(to: MailMemory.split(to), cc: MailMemory.split(cc), subject: subject,
                             body: messageBody, attachments: draft.attachments) { result in
                    sent = (result == .sent)
                    showComposer = false
                }
                .ignoresSafeArea()
            }
            .sheet(isPresented: $fallbackShare) {
                ActivityView(items: [messageBody as Any] + draft.attachments.map { $0 as Any })
                    .presentationDetents([.medium, .large])
            }
            .alert("App Mail non configurée", isPresented: $fallbackInfo) {
                Button("Continuer") { fallbackShare = true }
                Button("Annuler", role: .cancel) {}
            } message: {
                Text("Choisissez votre messagerie (Gmail, Outlook…) dans la fenêtre suivante. L'adresse du destinataire a été copiée : collez-la dans le champ « À ».")
            }
            .alert("Envoi par mail", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(error ?? "")
            }
        }
    }

    private func send() {
        let toList = MailMemory.split(to)
        let ccList = MailMemory.split(cc)
        if let bad = (toList + ccList).first(where: { !MailMemory.isValid($0) }) {
            error = "Adresse invalide : \(bad)"
            return
        }
        // Mémorise les adresses pour les prochains envois
        MailMemory.remember(toList + ccList)
        MailMemory.lastTo = toList.joined(separator: ", ")
        MailMemory.lastCc = ccList.joined(separator: ", ")
        recent = MailMemory.recent

        if MFMailComposeViewController.canSendMail() {
            sent = false
            showComposer = true
        } else {
            UIPasteboard.general.string = toList.joined(separator: ", ")
            fallbackInfo = true
        }
    }
}

/// Fenêtre d'envoi de l'app Mail, pré-remplie
struct MailComposer: UIViewControllerRepresentable {
    let to: [String]
    let cc: [String]
    let subject: String
    let body: String
    let attachments: [URL]
    let onResult: (MFMailComposeResult) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onResult: onResult) }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = context.coordinator
        vc.setToRecipients(to)
        if !cc.isEmpty { vc.setCcRecipients(cc) }
        vc.setSubject(subject)
        vc.setMessageBody(body, isHTML: false)
        for url in attachments {
            guard let data = try? Data(contentsOf: url) else { continue }
            let mime = url.pathExtension.lowercased() == "xlsx"
                ? "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
                : "image/jpeg"
            vc.addAttachmentData(data, mimeType: mime, fileName: url.lastPathComponent)
        }
        return vc
    }

    func updateUIViewController(_ vc: MFMailComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onResult: (MFMailComposeResult) -> Void
        init(onResult: @escaping (MFMailComposeResult) -> Void) { self.onResult = onResult }

        func mailComposeController(_ controller: MFMailComposeViewController,
                                   didFinishWith result: MFMailComposeResult, error: Error?) {
            onResult(result)
        }
    }
}
