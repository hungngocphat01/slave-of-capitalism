import SwiftUI

struct WalletFormSheet: View {
    private let apiClient: any APIClientProtocol
    private let wallet: WalletWithBalance?
    private let onComplete: () async -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var walletType: WalletType
    @State private var emoji: String
    @State private var creditLimitText: String
    @State private var initialBalanceText: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(
        apiClient: any APIClientProtocol,
        wallet: WalletWithBalance? = nil,
        onComplete: @escaping () async -> Void
    ) {
        self.apiClient = apiClient
        self.wallet = wallet
        self.onComplete = onComplete

        _name = State(initialValue: wallet?.name ?? "")
        _walletType = State(initialValue: wallet?.walletType ?? .normal)
        _emoji = State(initialValue: wallet?.emoji ?? (wallet?.walletType == .credit ? "💳" : "💰"))
        _creditLimitText = State(initialValue: Self.decimalString(wallet?.creditLimit ?? 0))
        _initialBalanceText = State(initialValue: "0")
    }

    var body: some View {
        NavigationStack {
            Form {
                if let validationMessage {
                    Section {
                        Text(validationMessage)
                            .foregroundStyle(.red)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }

                Section("Details") {
                    TextField("Wallet name", text: $name)
                    TextField("Emoji", text: $emoji)
                        .frame(maxWidth: 80)
                    Picker("Type", selection: $walletType) {
                        Text("Normal").tag(WalletType.normal)
                        Text("Credit").tag(WalletType.credit)
                    }
                    .disabled(wallet != nil)
                }

                Section("Balances") {
                    if wallet == nil {
                        TextField("Initial balance", text: $initialBalanceText)
                    }

                    if walletType == .credit {
                        TextField("Credit limit", text: $creditLimitText)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(wallet == nil ? "Add Wallet" : "Edit Wallet")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isSaving)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(wallet == nil ? "Create" : "Save") {
                        Task {
                            await save()
                        }
                    }
                    .disabled(isSaving || validationMessage != nil)
                }
            }
        }
        .frame(minWidth: 420, minHeight: 280)
    }

    private func save() async {
        guard validationMessage == nil else {
            return
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedEmoji = emoji.trimmingCharacters(in: .whitespacesAndNewlines)
        let emojiValue = normalizedEmoji.isEmpty ? nil : normalizedEmoji
        let creditLimit = walletType == .credit ? parsedCreditLimit! : 0
        let initialBalance = wallet == nil && walletType == .normal ? parsedInitialBalance! : 0

        isSaving = true
        defer { isSaving = false }

        do {
            if let wallet {
                let body = WalletUpdate(
                    name: trimmedName,
                    walletType: walletType,
                    creditLimit: walletType == .credit ? creditLimit : 0,
                    emoji: emojiValue
                )
                _ = try await apiClient.updateWallet(id: wallet.id, body)
            } else {
                let body = WalletCreate(
                    name: trimmedName,
                    walletType: walletType,
                    creditLimit: walletType == .credit ? creditLimit : 0,
                    emoji: emojiValue,
                    initialBalance: initialBalance
                )
                _ = try await apiClient.createWallet(body)
            }

            errorMessage = nil
            await onComplete()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var validationMessage: String? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            return "Wallet name is required."
        }

        if wallet == nil, walletType == .normal, parsedInitialBalance == nil {
            return "Enter a valid initial balance."
        }

        if wallet == nil, walletType == .normal, let parsedInitialBalance, parsedInitialBalance < 0 {
            return "Initial balance cannot be negative."
        }

        if walletType == .credit, parsedCreditLimit == nil {
            return "Enter a valid credit limit."
        }

        if walletType == .credit, let parsedCreditLimit, parsedCreditLimit < 0 {
            return "Credit limit cannot be negative."
        }

        return nil
    }

    private var parsedCreditLimit: Decimal? {
        guard walletType == .credit else { return 0 }
        return decimalValue(from: creditLimitText)
    }

    private var parsedInitialBalance: Decimal? {
        guard wallet == nil, walletType == .normal else { return 0 }
        return decimalValue(from: initialBalanceText)
    }

    private func decimalValue(from text: String) -> Decimal? {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "")
        guard !normalized.isEmpty else { return nil }
        return Decimal(string: normalized)
    }

    private static func decimalString(_ decimal: Decimal) -> String {
        NSDecimalNumber(decimal: decimal).stringValue
    }
}
