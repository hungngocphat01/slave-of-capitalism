import SwiftUI

@main
struct SlaveOfCapitalismApp: App {
    @State private var backendManager = BackendManager()
    @State private var categoryStore = CategoryStore()
    @State private var walletStore = WalletStore()
    @State private var appSettings = AppSettings()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(backendManager)
                .environment(backendManager.apiClient)
                .environment(categoryStore)
                .environment(walletStore)
                .environment(appSettings)
                .task {
                    let dbPath = appSettings.databasePath.isEmpty ? nil : appSettings.databasePath
                    let preferredPort: UInt16? = appSettings.backendPortMode == "custom" ? UInt16(appSettings.customBackendPort) : nil
                    await backendManager.start(dbPath: dbPath, preferredPort: preferredPort)
                }
                .onChange(of: backendManager.isReady) { _, isReady in
                    guard isReady else { return }
                    categoryStore.configure(apiClient: backendManager.apiClient)
                    walletStore.configure(apiClient: backendManager.apiClient)

                    Task {
                        await categoryStore.refresh()
                        await walletStore.refresh()
                    }
                }
        }
    }
}
