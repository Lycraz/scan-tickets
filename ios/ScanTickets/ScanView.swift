import SwiftUI
import PhotosUI
import VisionKit

struct ScanView: View {
    @EnvironmentObject var store: TicketStore
    var onFinished: () -> Void

    private struct Pending: Identifiable {
        let id = UUID()
        let image: UIImage
    }

    @State private var showScanner = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var pending: Pending?
    @State private var batchProgress: String?
    @State private var message: String?
    @State private var countBefore = 0
    @State private var kmDraft: Ticket?
    @AppStorage("engine") private var engine = "auto"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Button {
                        if VNDocumentCameraViewController.isSupported {
                            showScanner = true
                        } else {
                            message = "Le scanner n'est pas disponible sur cet appareil (simulateur ?). Utilisez « Choisir des photos »."
                        }
                    } label: {
                        VStack(spacing: 12) {
                            Image(systemName: "doc.viewfinder.fill").font(.system(size: 54))
                            Text("Scanner un ticket").font(.title3.bold())
                            Text("Recadrage automatique · plusieurs tickets d'affilée possibles")
                                .font(.footnote).opacity(0.85)
                                .multilineTextAlignment(.center)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 210)
                        .padding(.horizontal)
                        .background(LinearGradient(colors: [Color(red: 0.39, green: 0.40, blue: 0.95), Color(red: 0.26, green: 0.22, blue: 0.79)],
                                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                                    in: RoundedRectangle(cornerRadius: 24))
                        .shadow(color: .indigo.opacity(0.35), radius: 16, y: 8)
                    }
                    .buttonStyle(.plain)

                    PhotosPicker(selection: $photoItems, maxSelectionCount: 30, matching: .images) {
                        HStack(spacing: 12) {
                            Image(systemName: "photo.on.rectangle.angled").font(.title2)
                            Text("Choisir des photos").font(.headline)
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
                    }
                    .buttonStyle(.plain)

                    Button {
                        countBefore = store.tickets.count
                        kmDraft = Ticket.withDefaults(nature: Catalog.kmNature)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "car.fill").font(.title2)
                            Text("Ajouter des kilomètres").font(.headline)
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
                    }
                    .buttonStyle(.plain)
                    .sheet(item: $kmDraft, onDismiss: {
                        if store.tickets.count > countBefore { onFinished() }
                    }) { t in
                        TicketEditorView(ticket: t, image: nil, isNew: true, autoAnalyze: false)
                    }

                    if let batchProgress {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text(batchProgress).font(.subheadline)
                            Spacer()
                        }
                        .padding()
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
                    }

                    Label(engineDescription, systemImage: "sparkles")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Scanner")
            .disabled(batchProgress != nil)
            .fullScreenCover(isPresented: $showScanner) {
                DocumentScanner { images in
                    showScanner = false
                    handle(images)
                } onCancel: {
                    showScanner = false
                }
                .ignoresSafeArea()
            }
            .onChange(of: photoItems) { _, items in
                guard !items.isEmpty else { return }
                Task { await loadPhotos(items) }
            }
            .sheet(item: $pending, onDismiss: {
                if store.tickets.count > countBefore { onFinished() }
            }) { p in
                TicketEditorView(ticket: Ticket.withDefaults(), image: p.image, isNew: true, autoAnalyze: true)
            }
            .alert("Scan Tickets", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(message ?? "")
            }
        }
    }

    private var engineDescription: String {
        let hasKey = !Prefs.apiKey.isEmpty
        switch engine {
        case "none": return "Saisie manuelle (lecture automatique désactivée)."
        case "local": return "Lecture sur l'iPhone, gratuite et hors ligne."
        case "claude": return "Lecture par l'IA Claude."
        default:
            return hasKey ? "Lecture par l'IA Claude, avec lecture sur l'iPhone en secours."
                          : "Lecture sur l'iPhone (gratuite). Ajoutez une clé API dans Réglages pour plus de précision."
        }
    }

    private func loadPhotos(_ items: [PhotosPickerItem]) async {
        var images: [UIImage] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                images.append(img)
            }
        }
        photoItems = []
        if images.isEmpty { message = "Impossible de lire ces photos." }
        handle(images)
    }

    private func handle(_ images: [UIImage]) {
        let prepared = images.map { $0.resized(maxSide: 2000) }
        if prepared.count == 1 {
            countBefore = store.tickets.count
            // Laisse le temps au scanner de se fermer avant d'ouvrir la fiche
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                pending = Pending(image: prepared[0])
            }
        } else if prepared.count > 1 {
            Task { await processBatch(prepared) }
        }
    }

    /// Plusieurs tickets : lecture en série, enregistrés avec le badge « à vérifier »
    @MainActor
    private func processBatch(_ images: [UIImage]) async {
        var ok = 0
        for (i, img) in images.enumerated() {
            batchProgress = "Ticket \(i + 1) sur \(images.count)…"
            var t = Ticket.withDefaults()
            if let r = try? await Analyzer.run(img) { r.apply(to: &t) }
            t.aVerifier = true
            store.save(t, image: img)
            ok += 1
        }
        batchProgress = nil
        message = "\(ok) tickets ajoutés. Ils sont marqués « à vérifier » : touchez-les pour contrôler."
        onFinished()
    }
}

// MARK: - Scanner de documents Apple (VisionKit)

struct DocumentScanner: UIViewControllerRepresentable {
    var onScan: ([UIImage]) -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController()
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: VNDocumentCameraViewController, context: Context) {}

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: DocumentScanner
        init(_ parent: DocumentScanner) { self.parent = parent }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            let images = (0..<scan.pageCount).map { scan.imageOfPage(at: $0) }
            parent.onScan(images)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            parent.onCancel()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            parent.onCancel()
        }
    }
}
