import SwiftUI

@main
struct ScanTicketsApp: App {
    @StateObject private var store = TicketStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var store: TicketStore
    @State private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            TicketListView(goToScan: { tab = 1 })
                .tabItem { Label("Tickets", systemImage: "list.bullet.rectangle.portrait") }
                .badge(store.toReviewCount)
                .tag(0)
            ScanView(onFinished: { tab = 0 })
                .tabItem { Label("Scanner", systemImage: "doc.viewfinder") }
                .tag(1)
            ExportView()
                .tabItem { Label("Export", systemImage: "tablecells") }
                .tag(2)
            SettingsView()
                .tabItem { Label("Réglages", systemImage: "gearshape") }
                .tag(3)
        }
    }
}
