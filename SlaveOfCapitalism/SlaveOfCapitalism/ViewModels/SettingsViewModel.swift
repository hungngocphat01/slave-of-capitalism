import Foundation
import Observation
import AppKit

@Observable
final class SettingsViewModel {
    let settings: AppSettings
    private let backendManager: BackendManager

    // Editing copies (so changes don't take effect until applied)
    var editingDbPath: String
    var editingPortMode: String // "auto" or "custom"
    var editingCustomPort: Int

    var needsRestart: Bool {
        let dbChanged = editingDbPath != settings.databasePath
        let portModeChanged = editingPortMode != settings.backendPortMode
        let portChanged = editingPortMode == "custom" && editingCustomPort != settings.customBackendPort
        return dbChanged || portModeChanged || portChanged
    }

    var portValidationError: String? {
        guard editingPortMode == "custom" else { return nil }
        guard editingCustomPort >= 1024 && editingCustomPort <= 65535 else {
            return "Port must be between 1024 and 65535"
        }
        return nil
    }

    var currentPort: UInt16 { backendManager.port }

    init(settings: AppSettings, backendManager: BackendManager) {
        self.settings = settings
        self.backendManager = backendManager
        self.editingDbPath = settings.databasePath
        self.editingPortMode = settings.backendPortMode
        self.editingCustomPort = settings.customBackendPort
    }

    func applyBackendChanges() async {
        settings.databasePath = editingDbPath
        settings.backendPortMode = editingPortMode
        settings.customBackendPort = editingCustomPort

        let dbPath = editingDbPath.isEmpty ? nil : editingDbPath
        let preferredPort: UInt16? = editingPortMode == "custom" ? UInt16(editingCustomPort) : nil
        await backendManager.restart(dbPath: dbPath, preferredPort: preferredPort)
    }

    func resetToDefaults() {
        settings.currency = "¥"
        settings.decimals = 0
        settings.language = "en"
        editingDbPath = ""
        editingPortMode = "auto"
        editingCustomPort = 8000
    }

    func browseForDatabase() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder for the database"
        panel.prompt = "Select"
        if panel.runModal() == .OK, let url = panel.url {
            editingDbPath = url.appendingPathComponent("expense.db").path
        }
    }
}
