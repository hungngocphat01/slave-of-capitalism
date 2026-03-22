import SwiftUI

struct Sidebar: View {
    @Binding var selection: Screen

    var body: some View {
        List(selection: $selection) {
            Section("Main") {
                Label("Transactions", systemImage: "list.bullet.rectangle")
                    .tag(Screen.transactions)
                Label("Summary", systemImage: "chart.bar")
                    .tag(Screen.summary)
                Label("Wallets", systemImage: "wallet.pass")
                    .tag(Screen.wallets)
                Label("Pending", systemImage: "clock")
                    .tag(Screen.pending)
                Label("Categories", systemImage: "folder")
                    .tag(Screen.categories)
            }

            Section {
                Label("Data", systemImage: "square.and.arrow.down")
                    .tag(Screen.data)
                Label("Audit", systemImage: "checkmark.shield")
                    .tag(Screen.audit)
                Label("Settings", systemImage: "gear")
                    .tag(Screen.settings)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Slave of Capitalism")
    }
}

#Preview {
    Sidebar(selection: .constant(.transactions))
}
