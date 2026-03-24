import SwiftUI

struct MarkAsSplitPreview: Equatable {
    let counterpartyLabel: String
    let counterpartyAmount: Decimal
}

enum MarkAsSplitSheetPresentation {
    static func preview(
        totalAmount: Decimal,
        userAmountText: String,
        counterpartyName: String
    ) -> MarkAsSplitPreview? {
        guard let userAmount = decimal(from: userAmountText) else { return nil }

        return MarkAsSplitPreview(
            counterpartyLabel: counterpartyLabel(for: counterpartyName),
            counterpartyAmount: max(.zero, totalAmount - userAmount)
        )
    }

    static func counterpartyLabel(for counterpartyName: String) -> String {
        let trimmedName = counterpartyName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? "Counterparty Share" : "\(trimmedName)'s Share"
    }

    private static func decimal(from text: String) -> Decimal? {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "")
        guard !normalized.isEmpty else { return nil }
        return Decimal(string: normalized)
    }
}

struct MarkAsSplitSheet: View {
    private let apiClient: any APIClientProtocol
    let transaction: TransactionWithDetails
    let onComplete: () async -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var counterpartyName = ""
    @State private var userAmountText = ""
    @State private var notes = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(
        apiClient: any APIClientProtocol,
        transaction: TransactionWithDetails,
        onComplete: @escaping () async -> Void
    ) {
        self.apiClient = apiClient
        self.transaction = transaction
        self.onComplete = onComplete
    }

    var body: some View {
        SheetDialogScaffold(
            title: "Mark as Split",
            subtitle: "Define your share first so the remaining balance can be tracked against the other person."
        ) {
            if let errorMessage {
                SheetInlineMessage(errorMessage, tone: .error)
            }

            SheetSectionContainer(
                title: "Selected Transaction",
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(transaction.description ?? "No description")
                        .font(.title2.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 10) {
                        GridRow {
                            SheetValueLabel("Amount")
                            Text(Formatters.currency(transaction.amount))
                                .fontWeight(.semibold)
                                .monospacedDigit()
                        }

                        GridRow {
                            SheetValueLabel("Date")
                            Text(transaction.date)
                                .foregroundStyle(.secondary)
                        }

                        GridRow {
                            SheetValueLabel("Direction")
                            Text(transaction.direction.rawValue.capitalized)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            SheetSectionContainer(
                title: "Split Details",
            ) {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 14) {
                    GridRow {
                        SheetFieldLabel("Counterparty")
                        TextField("Who shared this expense?", text: $counterpartyName)
                            .textFieldStyle(.roundedBorder)
                    }

                    GridRow {
                        SheetFieldLabel("Your Share")
                        CurrencyField(title: "Your share", text: $userAmountText, prompt: "0.00")
                            .textFieldStyle(.roundedBorder)
                    }

                    if let splitPreview {
                        GridRow(alignment: .top) {
                            SheetFieldLabel("Remaining")
                            VStack(alignment: .leading, spacing: 6) {
                                Text(splitPreview.counterpartyLabel)
                                    .font(.subheadline.weight(.semibold))
                                Text(Formatters.currency(splitPreview.counterpartyAmount))
                                    .font(.title3.weight(.semibold))
                                    .monospacedDigit()
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }

                    GridRow(alignment: .top) {
                        SheetFieldLabel("Notes")
                        TextField("Optional notes for the split entry", text: $notes, axis: .vertical)
                            .lineLimit(3...5)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }
        } actions: {
            SheetActionBar(
                message: errorMessage ?? validationMessage,
                isError: errorMessage != nil,
                isWorking: isSaving
            ) {
                Button("Cancel") { dismiss() }
                    .disabled(isSaving)
            } primaryAction: {
                Button("Save") {
                    Task { await submit() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isSaving || validationMessage != nil)
            }
        }
        .frame(minWidth: 520, minHeight: 430)
    }

    private var validationMessage: String? {
        if counterpartyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Counterparty is required."
        }

        guard let value = decimal(from: userAmountText), value > 0 else {
            return "Enter a valid user amount."
        }

        if value > transaction.amount {
            return "Your amount cannot be greater than total amount."
        }

        return nil
    }

    private var splitPreview: MarkAsSplitPreview? {
        MarkAsSplitSheetPresentation.preview(
            totalAmount: transaction.amount,
            userAmountText: userAmountText,
            counterpartyName: counterpartyName
        )
    }

    private func submit() async {
        guard validationMessage == nil, let userAmount = decimal(from: userAmountText) else { return }

        isSaving = true
        defer { isSaving = false }

        do {
            _ = try await apiClient.markAsSplit(
                id: transaction.id,
                MarkAsSplitRequest(
                    counterpartyName: counterpartyName.trimmingCharacters(in: .whitespacesAndNewlines),
                    userAmount: userAmount,
                    notes: optionalTrimmedValue(notes)
                )
            )
            errorMessage = nil
            await onComplete()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func decimal(from text: String) -> Decimal? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: "")
        guard !normalized.isEmpty else { return nil }
        return Decimal(string: normalized)
    }

    private func optionalTrimmedValue(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct SheetDialogScaffold<Content: View, Actions: View>: View {
    let title: String
    let subtitle: String
    let content: Content
    let actions: Actions

    init(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content,
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
        self.actions = actions()
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.title2.weight(.semibold))

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 18)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }

            Divider()

            actions
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
        }
        .background(.background)
    }
}

struct SheetSectionContainer<Content: View>: View {
    let title: String
    let subtitle: String?
    let content: Content

    init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)

                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SheetValueLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(width: 90, alignment: .leading)
    }
}

struct SheetFieldLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(width: 96, alignment: .leading)
            .padding(.top, 6)
    }
}

struct SheetInlineMessage: View {
    enum Tone {
        case error
        case info

        var foregroundStyle: Color {
            switch self {
            case .error:
                return .red
            case .info:
                return .secondary
            }
        }

        var backgroundStyle: Color {
            switch self {
            case .error:
                return .red.opacity(0.08)
            case .info:
                return .secondary.opacity(0.08)
            }
        }
    }

    let message: String
    let tone: Tone

    init(_ message: String, tone: Tone) {
        self.message = message
        self.tone = tone
    }

    var body: some View {
        Text(message)
            .font(.subheadline)
            .foregroundStyle(tone.foregroundStyle)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(tone.backgroundStyle, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct SheetActionBar<SecondaryAction: View, PrimaryAction: View>: View {
    let message: String?
    let isError: Bool
    let isWorking: Bool
    let secondaryAction: SecondaryAction
    let primaryAction: PrimaryAction

    init(
        message: String?,
        isError: Bool,
        isWorking: Bool,
        @ViewBuilder secondaryAction: () -> SecondaryAction,
        @ViewBuilder primaryAction: () -> PrimaryAction
    ) {
        self.message = message
        self.isError = isError
        self.isWorking = isWorking
        self.secondaryAction = secondaryAction()
        self.primaryAction = primaryAction()
    }

    var body: some View {
        HStack(spacing: 12) {
            if let message {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(isError ? .red : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if isWorking {
                ProgressView()
                    .controlSize(.small)
            }

            Spacer(minLength: 12)

            secondaryAction
            primaryAction
        }
    }
}
