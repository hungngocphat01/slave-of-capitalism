import Foundation
import Observation

@MainActor
@Observable
final class BudgetViewModel {
    private let apiClient: any APIClientProtocol

    private(set) var budgets: [BudgetWithCategory] = []
    private(set) var isLoading = false
    private(set) var isMutating = false
    var error: APIError?

    private var selectedYear: Int
    private var selectedMonth: Int

    init(
        apiClient: any APIClientProtocol,
        year: Int = Calendar.current.component(.year, from: .now),
        month: Int = Calendar.current.component(.month, from: .now)
    ) {
        self.apiClient = apiClient
        self.selectedYear = year
        self.selectedMonth = month
    }

    func load(year: Int, month: Int) async {
        selectedYear = year
        selectedMonth = month

        isLoading = true
        defer { isLoading = false }

        do {
            budgets = try await apiClient.listBudgets(year: year, month: month, categoryId: nil)
            error = nil
        } catch let apiError as APIError {
            error = apiError
        } catch is CancellationError {
            // Ignore task cancellations (e.g., rapid month changes).
        } catch {
            self.error = .networkError(error)
        }
    }

    func budget(for categoryId: Int) -> BudgetWithCategory? {
        budgets.first { $0.categoryId == categoryId }
    }

    @discardableResult
    func create(categoryId: Int, amount: Decimal) async -> Bool {
        await mutate {
            _ = try await apiClient.createBudget(
                BudgetCreate(
                    categoryId: categoryId,
                    year: selectedYear,
                    month: selectedMonth,
                    amount: amount
                )
            )
        }
    }

    @discardableResult
    func update(id: Int, amount: Decimal) async -> Bool {
        await mutate {
            _ = try await apiClient.updateBudget(id: id, BudgetUpdate(amount: amount))
        }
    }

    @discardableResult
    func delete(id: Int) async -> Bool {
        await mutate {
            try await apiClient.deleteBudget(id: id)
        }
    }

    @discardableResult
    private func mutate(_ operation: () async throws -> Void) async -> Bool {
        guard !isMutating else { return false }

        isMutating = true
        defer { isMutating = false }

        do {
            try await operation()
            await load(year: selectedYear, month: selectedMonth)
            return true
        } catch let apiError as APIError {
            error = apiError
            return false
        } catch is CancellationError {
            return false
        } catch {
            self.error = .networkError(error)
            return false
        }
    }
}
