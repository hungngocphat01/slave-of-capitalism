import Foundation
import Observation

@MainActor
@Observable
final class TransactionViewModel {
    private let apiClient: any APIClientProtocol

    private(set) var transactions: [TransactionWithDetails] = []
    var selectedMonth: Int
    var selectedYear: Int
    var selectedIds: Set<Int> = []
    private(set) var isLoading = false
    var error: APIError?

    init(
        apiClient: any APIClientProtocol,
        selectedYear: Int = Calendar.current.component(.year, from: .now),
        selectedMonth: Int = Calendar.current.component(.month, from: .now)
    ) {
        self.apiClient = apiClient
        self.selectedYear = selectedYear
        self.selectedMonth = selectedMonth
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            transactions = try await apiClient.listTransactions(
                walletId: nil,
                categoryId: nil,
                month: monthKey,
                direction: nil,
                classification: nil
            )
            selectedIds.formIntersection(transactions.map(\.id))
            error = nil
        } catch let apiError as APIError {
            error = apiError
        } catch {
            self.error = .networkError(error)
        }
    }

    func deleteSelected() async {
        await performBulkMutation { ids in
            try await apiClient.deleteTransactions(ids: ids)
        }
    }

    func ignoreSelected() async {
        await performBulkMutation { ids in
            try await apiClient.ignoreTransactions(ids: ids)
        }
    }

    func unignoreSelected() async {
        await performBulkMutation { ids in
            try await apiClient.unignoreTransactions(ids: ids)
        }
    }

    var monthKey: String {
        String(format: "%04d-%02d-01", selectedYear, selectedMonth)
    }

    private func performBulkMutation(
        _ mutation: ([Int]) async throws -> Void
    ) async {
        let ids = selectedIds.sorted()
        guard !ids.isEmpty else { return }

        do {
            try await mutation(ids)
            selectedIds.removeAll()
            await load()
        } catch let apiError as APIError {
            error = apiError
        } catch is CancellationError {
            // Ignore task cancellations (e.g., rapid month changes).
        } catch {
            self.error = .networkError(error)
        }
    }
}
