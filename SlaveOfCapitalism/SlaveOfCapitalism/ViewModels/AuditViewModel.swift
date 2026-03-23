import Foundation
import Observation

@MainActor
@Observable
final class AuditViewModel {
    private let apiClient: any APIClientProtocol

    private(set) var audits: [BalanceAuditResponse] = []
    private(set) var isLoading = false
    private(set) var isTakingSnapshot = false
    var error: APIError?

    init(apiClient: any APIClientProtocol) {
        self.apiClient = apiClient
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            audits = try await apiClient.getAudits()
            error = nil
        } catch let apiError as APIError {
            audits = []
            error = apiError
        } catch {
            audits = []
            self.error = .networkError(error)
        }
    }

    @discardableResult
    func takeSnapshot() async -> Bool {
        isTakingSnapshot = true
        defer { isTakingSnapshot = false }

        do {
            _ = try await apiClient.createAudit(BalanceAuditCreate(date: Self.todayDateString()))
            error = nil
            await load()
            return true
        } catch let apiError as APIError {
            error = apiError
        } catch {
            self.error = .networkError(error)
        }

        return false
    }

    private static func todayDateString(now: Date = .now) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: now)
    }
}
