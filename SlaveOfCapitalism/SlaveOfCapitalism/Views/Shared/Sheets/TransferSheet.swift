import SwiftUI

struct TransferSheet: View {
    private let apiClient: any APIClientProtocol
    private let wallets: [WalletWithBalance]
    private let onComplete: () async -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var fromWalletId: Int
    @State private var toWalletId: Int
    @State private var amountText = ""
    @State private var descriptionText = "Transfer"
    @State private var transferDate = Date.now
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(
        apiClient: any APIClientProtocol,
        wallets: [WalletWithBalance],
        initialFromWalletId: Int? = nil,
        onComplete: @escaping () async -> Void
    ) {
        self.apiClient = apiClient
        self.wallets = wallets
        self.onComplete = onComplete

        let fromId = initialFromWalletId ?? wallets.first?.id ?? 0
        let toId = wallets.first(where: { $0.id != fromId })?.id ?? 0

        _fromWalletId = State(initialValue: fromId)
        _toWalletId = State(initialValue: toId)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }

                Section("Wallets") {
                    Picker("From", selection: $fromWalletId) {
                        ForEach(wallets) { wallet in
                            Text(wallet.name).tag(wallet.id)
                        }
                    }

                    Picker("To", selection: $toWalletId) {
                        ForEach(destinationWallets) { wallet in
                            Text(wallet.name).tag(wallet.id)
                        }
                    }
                }

                Section("Transfer") {
                    DatePicker("Date", selection: $transferDate, displayedComponents: .date)
                    TextField("Amount", text: $amountText)
                    TextField("Description", text: $descriptionText)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Transfer")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await submitTransfer()
                        }
                    }
                    .disabled(isSaving || wallets.count < 2)
                }
            }
            .onChange(of: fromWalletId) { _, newValue in
                if newValue == toWalletId {
                    toWalletId = destinationWallets.first?.id ?? 0
                }
            }
        }
        .frame(minWidth: 420, minHeight: 260)
    }

    private var destinationWallets: [WalletWithBalance] {
        wallets.filter { $0.id != fromWalletId }
    }

    private func submitTransfer() async {
        guard fromWalletId != 0, toWalletId != 0 else {
            errorMessage = "Choose both wallets."
            return
        }

        guard fromWalletId != toWalletId else {
            errorMessage = "Source and destination wallets must be different."
            return
        }

        guard let amount = decimalValue(from: amountText), amount > 0 else {
            errorMessage = "Enter a valid transfer amount."
            return
        }

        isSaving = true
        defer { isSaving = false }

        do {
            let request = WalletTransferRequest(
                fromWalletId: fromWalletId,
                toWalletId: toWalletId,
                amount: amount,
                description: descriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Transfer" : descriptionText,
                date: isoDateString(from: transferDate),
                time: nil
            )
            _ = try await apiClient.transfer(request)
            errorMessage = nil
            await onComplete()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func decimalValue(from text: String) -> Decimal? {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "")
        guard !normalized.isEmpty else { return nil }
        return Decimal(string: normalized)
    }

    private func isoDateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
