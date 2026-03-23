import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var appSettings
    @Environment(BackendManager.self) private var backendManager
    @State private var viewModel: SettingsViewModel?

    var body: some View {
        Group {
            if let viewModel {
                settingsForm(viewModel)
            } else {
                ProgressView()
            }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = SettingsViewModel(settings: appSettings, backendManager: backendManager)
            }
        }
        .navigationTitle("Settings")
    }

    private func settingsForm(_ vm: SettingsViewModel) -> some View {
        Form {
            // Currency section
            Section("Currency") {
                @Bindable var settings = vm.settings
                TextField("Symbol", text: $settings.currency)
                    .frame(width: 100)
                HStack {
                    ForEach(["¥", "$", "€", "£", "₫"], id: \.self) { symbol in
                        Button(symbol) { settings.currency = symbol }
                            .buttonStyle(.bordered)
                    }
                }
                Stepper("Decimal places: \(settings.decimals)", value: $settings.decimals, in: 0...4)
            }

            // Language section
            Section("Language") {
                @Bindable var settings = vm.settings
                Picker("Language", selection: $settings.language) {
                    Text("English").tag("en")
                    Text("Vietnamese").tag("vi")
                }
                .pickerStyle(.segmented)
            }

            // Database section
            Section("Database") {
                HStack {
                    TextField("Path", text: Bindable(vm).editingDbPath)
                    Button("Browse...") { vm.browseForDatabase() }
                }
                if vm.editingDbPath != vm.settings.databasePath {
                    Text("Restart required to apply")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Text("Default: ~/Library/Application Support/SlaveOfCapitalism/expense.db")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Backend section
            Section("Backend") {
                Picker("Port mode", selection: Bindable(vm).editingPortMode) {
                    Text("Auto").tag("auto")
                    Text("Custom").tag("custom")
                }
                .pickerStyle(.segmented)

                if vm.editingPortMode == "custom" {
                    TextField("Port", value: Bindable(vm).editingCustomPort, format: .number)
                        .frame(width: 100)
                    if let err = vm.portValidationError {
                        Text(err).font(.caption).foregroundStyle(.red)
                    }
                }

                Text("Current port: \(vm.currentPort)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if vm.needsRestart {
                    Button("Apply & Restart Backend") {
                        Task { await vm.applyBackendChanges() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(vm.portValidationError != nil)
                }
            }

            // Reset section
            Section {
                Button("Reset to Defaults", role: .destructive) {
                    vm.resetToDefaults()
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: 500)
    }
}
