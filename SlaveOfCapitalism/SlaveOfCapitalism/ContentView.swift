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
    @State private var isRestartingBackend = false

    var body: some View {
        Group {
            switch backendManager.state {
            case .starting:
                LoadingView()
            case .error(let message), .crashed(let message):
                ErrorView(
                    message: message,
                    onRetry: isRestartingBackend ? nil : { restartBackend(openSettings: false) },
                    onOpenSettings: isRestartingBackend ? nil : { restartBackend(openSettings: true) }
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
            TransactionListView()
        case .summary:
            Text("Summary - Task 14")
        case .wallets:
            WalletListView(apiClient: backendManager.apiClient)
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
        guard !isRestartingBackend else { return }

        if openSettings {
            selectedScreen = .settings
        }

        let dbPath = appSettings.databasePath.isEmpty ? nil : appSettings.databasePath
        isRestartingBackend = true
        Task {
            await backendManager.restart(dbPath: dbPath)
            await MainActor.run {
                isRestartingBackend = false
            }
        }
    }
}
