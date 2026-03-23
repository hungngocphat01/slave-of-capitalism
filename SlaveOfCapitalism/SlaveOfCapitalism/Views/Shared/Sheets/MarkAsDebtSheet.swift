import SwiftUI

struct MarkAsDebtSheet: View {
    private let apiClient: any APIClientProtocol
    private let transaction: TransactionWithDetails
    private let onComplete: () async -> Void

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
        MarkAsLoanSheet(
            apiClient: apiClient,
            transaction: transaction,
            isDebt: true,
            onComplete: onComplete
        )
    }
}
