import Foundation
import Observation

@MainActor
@Observable
final class PendingViewModel {
    private let apiClient: any APIClientProtocol

    private(set) var entries: [LinkedEntryWithDetails] = []
    private(set) var isLoading = false
    private(set) var isLinking = false
    private(set) var linkableTransactionsByEntry: [Int: [TransactionWithDetails]] = [:]
    var error: APIError?

    init(apiClient: any APIClientProtocol) {
        self.apiClient = apiClient
    }

    var owedEntries: [LinkedEntryWithDetails] {
        entries.filter { $0.linkType == .splitPayment || $0.linkType == .loan }
    }

    var debtEntries: [LinkedEntryWithDetails] {
        entries.filter { $0.linkType == .debt }
    }

    var installmentEntries: [LinkedEntryWithDetails] {
        entries.filter { $0.linkType == .installment }
    }

    var totalOwed: Decimal {
        owedEntries.reduce(0) { $0 + $1.pendingAmount }
    }

    var totalDebt: Decimal {
        debtEntries.reduce(0) { $0 + $1.pendingAmount }
    }

    var totalInstallments: Decimal {
        installmentEntries.reduce(0) { $0 + $1.pendingAmount }
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            entries = try await apiClient.pendingEntries()
            error = nil
        } catch let apiError as APIError {
            error = apiError
        } catch is CancellationError {
            // Ignore task cancellations.
        } catch {
            self.error = .networkError(error)
        }
    }

    func loadLinkableTransactions(for entry: LinkedEntryWithDetails) async {
        do {
            let direction: TransactionDirection = (entry.linkType == .splitPayment || entry.linkType == .loan) ? .inflow : .outflow
            let all = try await apiClient.listTransactions(
                walletId: nil,
                categoryId: nil,
                month: nil,
                direction: direction,
                classification: nil
            )

            let filtered = all
                .filter { isCandidate($0, for: entry.linkType) }
                .sorted {
                    if $0.date == $1.date {
                        return $0.id > $1.id
                    }
                    return $0.date > $1.date
                }

            linkableTransactionsByEntry[entry.id] = filtered
            error = nil
        } catch let apiError as APIError {
            error = apiError
            linkableTransactionsByEntry[entry.id] = []
        } catch is CancellationError {
            // Ignore task cancellations.
        } catch {
            self.error = .networkError(error)
            linkableTransactionsByEntry[entry.id] = []
        }
    }

    func linkableTransactions(for entryId: Int) -> [TransactionWithDetails] {
        linkableTransactionsByEntry[entryId] ?? []
    }

    func clearLinkableTransactions(for entryId: Int) {
        linkableTransactionsByEntry[entryId] = nil
    }

    func linkTransaction(entryId: Int, transactionId: Int) async -> Bool {
        guard !isLinking else { return false }

        isLinking = true
        defer { isLinking = false }

        do {
            _ = try await apiClient.linkTransaction(entryId: entryId, LinkTransactionRequest(transactionId: transactionId))
            linkableTransactionsByEntry[entryId] = nil
            await load()
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

    private func isCandidate(_ transaction: TransactionWithDetails, for linkType: LinkType) -> Bool {
        guard !transaction.isLinkedToEntry else { return false }

        switch linkType {
        case .splitPayment, .loan:
            return transaction.direction == .inflow &&
                (transaction.classification == .income || transaction.classification == .debtCollection)
        case .debt:
            return transaction.direction == .outflow &&
                (transaction.classification == .expense || transaction.classification == .loanRepayment)
        case .installment:
            return transaction.direction == .outflow &&
                (transaction.classification == .expense || transaction.classification == .installmtChrge)
        }
    }
}
