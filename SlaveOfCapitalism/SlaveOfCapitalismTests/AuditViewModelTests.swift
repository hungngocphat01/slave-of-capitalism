import XCTest
@testable import SlaveOfCapitalism

@MainActor
final class AuditViewModelTests: XCTestCase {
    func testLoadFetchesAudits() async {
        let client = MockAPIClient()
        client.auditsResult = [
            makeAudit(id: 1, date: "2026-03-20", netPosition: 1200),
            makeAudit(id: 2, date: "2026-03-21", netPosition: 1400)
        ]

        let viewModel = AuditViewModel(apiClient: client)
        await viewModel.load()

        XCTAssertEqual(client.callLog, ["getAudits"])
        XCTAssertEqual(viewModel.audits.map(\.id), [1, 2])
        XCTAssertNil(viewModel.error)
        XCTAssertFalse(viewModel.isLoading)
    }

    func testLoadStoresAPIErrors() async {
        let client = MockAPIClient()
        client.errorToThrow = APIError.serverError("Audit load failed")

        let viewModel = AuditViewModel(apiClient: client)
        await viewModel.load()

        guard case .serverError(let message)? = viewModel.error else {
            return XCTFail("Expected server error, got \(String(describing: viewModel.error))")
        }

        XCTAssertEqual(message, "Audit load failed")
        XCTAssertTrue(viewModel.audits.isEmpty)
        XCTAssertFalse(viewModel.isLoading)
    }

    func testTakeSnapshotCreatesAuditAndReloadsAudits() async {
        let client = MockAPIClient()
        client.createAuditResult = makeAudit(id: 3, date: "2026-03-22", netPosition: 1800)
        client.auditsResult = [
            makeAudit(id: 3, date: "2026-03-22", netPosition: 1800)
        ]

        let viewModel = AuditViewModel(apiClient: client)
        let didTakeSnapshot = await viewModel.takeSnapshot()

        XCTAssertTrue(didTakeSnapshot)
        XCTAssertEqual(client.callLog, ["createAudit", "getAudits"])
        XCTAssertEqual(viewModel.audits.map(\.id), [3])
        XCTAssertNil(viewModel.error)
        XCTAssertFalse(viewModel.isTakingSnapshot)
    }

    func testTakeSnapshotStoresErrorsAndSkipsReloadOnFailure() async {
        let client = MockAPIClient()
        client.errorToThrow = APIError.serverError("Snapshot failed")

        let viewModel = AuditViewModel(apiClient: client)
        let didTakeSnapshot = await viewModel.takeSnapshot()

        XCTAssertFalse(didTakeSnapshot)
        XCTAssertEqual(client.callLog, ["createAudit"])

        guard case .serverError(let message)? = viewModel.error else {
            return XCTFail("Expected server error, got \(String(describing: viewModel.error))")
        }

        XCTAssertEqual(message, "Snapshot failed")
        XCTAssertTrue(viewModel.audits.isEmpty)
        XCTAssertFalse(viewModel.isTakingSnapshot)
    }

    private func makeAudit(id: Int, date: String, netPosition: Decimal) -> BalanceAuditResponse {
        BalanceAuditResponse(
            id: id,
            date: date,
            balances: ["Cash": 1200, "Visa": 400],
            debts: 300,
            owed: 150,
            netPosition: netPosition,
            createdAt: "2026-03-22T00:00:00Z",
            updatedAt: "2026-03-22T00:00:00Z"
        )
    }
}
