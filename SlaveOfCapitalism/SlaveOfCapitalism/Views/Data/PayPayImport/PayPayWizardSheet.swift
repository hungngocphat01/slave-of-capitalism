import SwiftUI

struct PayPayWizardSheet: View {
    @Environment(APIClient.self) private var apiClient
    @Environment(CategoryStore.self) private var categoryStore
    @Environment(WalletStore.self) private var walletStore
    @Environment(\.dismiss) private var dismiss

    @State private var step = 1
    @State private var csvContent: String?
    @State private var rulesContent: String?
    @State private var walletMapping: [String: Int] = PayPayWizardSheet.loadSavedWalletMapping()
    @State private var categoryMapping: [String: CategoryMapEntry] = [:]
    @State private var transformedRows: [TransformedRow] = []
    @State private var importPayload: PayPayImportPayload?
    @State private var importResult: BulkImportResponse?
    @State private var transfersImported: Int = 0
    @State private var importError: String?
    @State private var isImporting = false

    private let stepLabels = ["File", "Map", "Preview", "Import"]

    var body: some View {
        VStack(spacing: 0) {
            // Step indicator
            VStack(spacing: 4) {
                // Circles and connecting lines
                HStack(spacing: 0) {
                    ForEach(Array(stepLabels.enumerated()), id: \.offset) { index, _ in
                        let stepNum = index + 1
                        let isActive = stepNum == step
                        let isComplete = stepNum < step

                        if index > 0 {
                            Rectangle()
                                .fill(isComplete ? Color.accentColor : Color.secondary.opacity(0.25))
                                .frame(height: 2)
                        }

                        ZStack {
                            Circle()
                                .fill(isActive ? Color.accentColor : isComplete ? Color.accentColor : Color.secondary.opacity(0.2))
                                .frame(width: 28, height: 28)
                            if isComplete {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.white)
                            } else {
                                Text("\(stepNum)")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(isActive ? .white : .secondary)
                            }
                        }
                    }
                }

                // Labels row
                HStack(spacing: 0) {
                    ForEach(Array(stepLabels.enumerated()), id: \.offset) { index, label in
                        let stepNum = index + 1
                        let isActive = stepNum == step

                        if index > 0 {
                            Spacer()
                        }

                        Text(label)
                            .font(.caption)
                            .foregroundStyle(isActive ? .primary : .secondary)
                            .frame(width: 28)

                        if index < stepLabels.count - 1 {
                            Spacer()
                        }
                    }
                }
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 16)

            Divider()

            // Step content
            Group {
                switch step {
                case 1:
                    PayPayFileStep(csvContent: $csvContent, rulesContent: $rulesContent)
                case 2:
                    PayPayMappingStep(rows: transformedRows, walletMapping: $walletMapping, wallets: walletStore.wallets)
                case 3:
                    PayPayPreviewStep(rows: transformedRows, categoryMapping: $categoryMapping, categories: categoryStore.categories)
                case 4:
                    PayPayConfirmStep(
                        transactionCount: importPayload?.transactions.count ?? 0,
                        transferCount: importPayload?.transfers.count ?? 0,
                        result: importResult,
                        transfersImported: transfersImported,
                        error: importError,
                        isImporting: isImporting
                    )
                default:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Navigation buttons
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                Spacer()
                if step > 1 && importResult == nil {
                    Button("Back") { step -= 1 }
                }
                if step < 4 {
                    Button("Next") { advanceStep() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!canAdvance)
                } else if importResult == nil && importError == nil {
                    Button("Import") { performImport() }
                        .buttonStyle(.borderedProminent)
                        .disabled(isImporting || (importPayload?.transactions.isEmpty ?? true && importPayload?.transfers.isEmpty ?? true))
                } else {
                    Button("Done") { dismiss() }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
        .frame(width: 700, height: 500)
    }

    private var canAdvance: Bool {
        switch step {
        case 1: return csvContent != nil
        case 2: return true
        case 3: return true
        default: return false
        }
    }

    private func advanceStep() {
        switch step {
        case 1:
            // Parse and transform
            if let csv = csvContent {
                let raw = PayPayParser.parseCSV(csv)
                transformedRows = PayPayParser.transform(raw)
                // Apply rules if provided
                if let rulesText = rulesContent {
                    let rules = PayPayRuleEngine.compile(rulesText.components(separatedBy: "\n"))
                    PayPayRuleEngine.execute(rules: rules, rows: &transformedRows)
                }
            }
            step = 2
        case 2:
            // Apply wallet mapping
            PayPayTransformer.mapWallets(rows: &transformedRows, mapping: walletMapping)
            saveWalletMapping(walletMapping)
            step = 3
        case 3:
            // Build import payload
            importPayload = PayPayTransformer.buildPayload(
                rows: transformedRows,
                walletMapping: walletMapping,
                categoryMapping: categoryMapping
            )
            step = 4
        default:
            break
        }
    }

    private func performImport() {
        guard let payload = importPayload else { return }
        isImporting = true
        Task {
            do {
                // Import regular transactions via bulk import
                var bulkResult: BulkImportResponse?
                if !payload.transactions.isEmpty {
                    bulkResult = try await apiClient.bulkImport(BulkImportRequest(items: payload.transactions))
                }

                // Import wallet transfers individually
                var transferCount = 0
                for transfer in payload.transfers {
                    _ = try await apiClient.transfer(transfer)
                    transferCount += 1
                }

                await MainActor.run {
                    transfersImported = transferCount
                    importResult = bulkResult ?? BulkImportResponse(importedCount: 0, message: "Done")
                    isImporting = false
                }
            } catch {
                await MainActor.run {
                    importError = error.localizedDescription
                    isImporting = false
                }
            }
        }
    }

    private static func loadSavedWalletMapping() -> [String: Int] {
        (UserDefaults.standard.dictionary(forKey: "paypayWalletMapping") as? [String: Int]) ?? [:]
    }

    private func saveWalletMapping(_ mapping: [String: Int]) {
        UserDefaults.standard.set(mapping, forKey: "paypayWalletMapping")
    }
}
