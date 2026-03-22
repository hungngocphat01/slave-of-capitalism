import SwiftUI

enum Screen: String, Hashable, CaseIterable {
    case transactions
    case summary
    case wallets
    case pending
    case categories
    case data
    case audit
    case settings
}

struct ContentView: View {
    @Environment(BackendManager.self) private var backendManager
    @Environment(AppSettings.self) private var appSettings
    @State private var selectedScreen: Screen = .transactions

    var body: some View {
        Group {
            switch backendManager.state {
            case .starting:
                LoadingView()
            case .error(let message), .crashed(let message):
                ErrorView(
                    message: message,
                    onRetry: { restartBackend(openSettings: false) },
                    onOpenSettings: { restartBackend(openSettings: true) }
                )
            case .ready:
                NavigationSplitView {
                    Sidebar(selection: $selectedScreen)
                } detail: {
                    detailView
                }
            }
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selectedScreen {
        case .transactions:
            Text("Transactions - Task 11")
        case .summary:
            Text("Summary - Task 14")
        case .wallets:
            Text("Wallets - Task 10")
        case .pending:
            Text("Pending - Task 13")
        case .categories:
            Text("Categories - Task 12")
        case .data:
            Text("Data - Task 17")
        case .audit:
            Text("Audit - Task 15")
        case .settings:
            Text("Settings - Task 16")
        }
    }

    private func restartBackend(openSettings: Bool) {
        if openSettings {
            selectedScreen = .settings
        }

        let dbPath = appSettings.databasePath.isEmpty ? nil : appSettings.databasePath
        Task {
            await backendManager.restart(dbPath: dbPath)
        }
    }
}
