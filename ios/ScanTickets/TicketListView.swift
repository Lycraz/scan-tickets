import SwiftUI

struct TicketListView: View {
    @EnvironmentObject var store: TicketStore
    var goToScan: () -> Void

    @State private var search = ""
    @State private var editing: Ticket?

    private struct MonthSection: Identifiable {
        let id: String
        let tickets: [Ticket]
        var total: Double { tickets.reduce(0) { $0 + ($1.ttc ?? 0) } }
    }

    private var filtered: [Ticket] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return store.tickets }
        return store.tickets.filter {
            [$0.commercant, $0.nature, $0.descriptionText, $0.notes, $0.paiement]
                .joined(separator: " ").lowercased().contains(q)
        }
    }

    private var sections: [MonthSection] {
        let groups = Dictionary(grouping: filtered, by: \.monthKey)
        return groups.keys.sorted(by: >).map { MonthSection(id: $0, tickets: groups[$0] ?? []) }
    }

    private var currentMonthTotal: Double {
        let key = Fmt.monthKey(Date())
        return store.tickets.filter { $0.monthKey == key }.reduce(0) { $0 + ($1.ttc ?? 0) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.tickets.isEmpty {
                    ContentUnavailableView {
                        Label("Aucun ticket", systemImage: "doc.text.viewfinder")
                    } description: {
                        Text("Scannez votre premier ticket : l'app lit le montant, la date et le commerçant.")
                    } actions: {
                        Button("Scanner un ticket", action: goToScan)
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        Section {
                            summary
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(Color.clear)
                        }
                        ForEach(sections) { section in
                            Section {
                                ForEach(section.tickets) { t in
                                    Button { editing = t } label: { TicketRow(ticket: t) }
                                        .buttonStyle(.plain)
                                        .swipeActions {
                                            Button(role: .destructive) { store.delete(t) } label: {
                                                Label("Supprimer", systemImage: "trash")
                                            }
                                        }
                                }
                            } header: {
                                HStack {
                                    Text(Fmt.monthTitle(section.id))
                                    Spacer()
                                    Text(Fmt.money(section.total)).monospacedDigit()
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .searchable(text: $search, prompt: "Commerçant, nature…")
                }
            }
            .navigationTitle("Mes tickets")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: goToScan) { Image(systemName: "plus.circle.fill") }
                }
            }
            .sheet(item: $editing) { t in
                TicketEditorView(ticket: t, image: store.image(for: t), isNew: false, autoAnalyze: false)
            }
        }
    }

    private var summary: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Ce mois-ci").font(.caption).opacity(0.85)
                Text(Fmt.money(currentMonthTotal)).font(.title2.bold()).monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .foregroundStyle(.white)
            .background(LinearGradient(colors: [Color(red: 0.39, green: 0.40, blue: 0.95), Color(red: 0.26, green: 0.22, blue: 0.79)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 16))
            VStack(alignment: .leading, spacing: 4) {
                Text("Tickets").font(.caption).foregroundStyle(.secondary)
                Text("\(store.tickets.count)").font(.title2.bold())
                if store.toReviewCount > 0 {
                    Text("\(store.toReviewCount) à vérifier").font(.caption2).foregroundStyle(.orange)
                }
            }
            .frame(width: 110, alignment: .leading)
            .padding()
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        }
        .padding(.vertical, 4)
    }
}

struct TicketRow: View {
    @EnvironmentObject var store: TicketStore
    let ticket: Ticket

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let img = store.thumbnail(for: ticket) {
                    Image(uiImage: img).resizable().scaledToFill()
                } else {
                    Image(systemName: Catalog.icon(for: ticket.nature))
                        .foregroundStyle(.tint)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(.tertiarySystemFill))
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 3) {
                Text(ticket.isKilometres
                     ? (ticket.descriptionText.isEmpty ? "Trajet en voiture" : ticket.descriptionText)
                     : (ticket.commercant.isEmpty ? "Sans nom" : ticket.commercant))
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(Fmt.shortDay(ticket.date))
                    Label(ticket.nature, systemImage: Catalog.icon(for: ticket.nature))
                        .labelStyle(.titleAndIcon)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                        .foregroundStyle(Color.accentColor)
                    if ticket.aVerifier {
                        Text("à vérifier")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.orange.opacity(0.18), in: Capsule())
                            .foregroundStyle(.orange)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Text(ticket.isKilometres ? "\(Fmt.amountString(ticket.km).replacingOccurrences(of: ",00", with: "")) km"
                                     : Fmt.money(ticket.ttc, ticket.devise))
                .font(.body.weight(.bold))
                .monospacedDigit()
        }
        .contentShape(Rectangle())
    }
}
