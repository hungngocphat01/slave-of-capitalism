import Foundation
import Observation

@MainActor
@Observable
final class SummaryViewModel {
    enum UsageThreshold: Equatable {
        case neutral
        case safe
        case warning
        case danger
    }

    private let apiClient: any APIClientProtocol

    private(set) var monthlySummary: MonthlySummaryResponse?
    private(set) var dailySummary: DailySummaryResponse?
    var year: Int
    var month: Int
    private(set) var isLoading = false
    var error: APIError?

    init(
        apiClient: any APIClientProtocol,
        year: Int = Calendar.current.component(.year, from: .now),
        month: Int = Calendar.current.component(.month, from: .now)
    ) {
        self.apiClient = apiClient
        self.year = year
        self.month = month
    }

    var monthKey: String {
        String(format: "%04d-%02d", year, month)
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            async let monthlyTask = apiClient.budgetMonthlySummary(year: year, month: month, periodBoundaries: nil)
            async let dailyTask = apiClient.budgetDailySummary(year: year, month: month)
            monthlySummary = try await monthlyTask
            dailySummary = try await dailyTask
            error = nil
        } catch let apiError as APIError {
            monthlySummary = nil
            dailySummary = nil
            error = apiError
        } catch is CancellationError {
            // Ignore task cancellations (e.g., rapid month changes).
        } catch {
            monthlySummary = nil
            dailySummary = nil
            self.error = .networkError(error)
        }
    }

    func threshold(for percentage: Double) -> UsageThreshold {
        if percentage == 0 {
            return .neutral
        }
        if percentage < 90 {
            return .safe
        }
        if percentage <= 110 {
            return .warning
        }
        return .danger
    }
}
