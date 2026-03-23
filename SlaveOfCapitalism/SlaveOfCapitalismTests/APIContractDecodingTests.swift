import Foundation
import XCTest
@testable import SlaveOfCapitalism

final class APIContractDecodingTests: XCTestCase {
    func testWalletsFixtureDecodesWithCurrentDecoder() throws {
        let data = try loadFixture(named: "wallets-list")
        let decoder = makeDecoder()

        XCTAssertNoThrow(try decoder.decode([WalletWithBalance].self, from: data))
    }

    func testTransactionsFixtureDecodesWithCurrentDecoder() throws {
        let data = try loadFixture(named: "transactions-list")
        let decoder = makeDecoder()

        XCTAssertNoThrow(try decoder.decode([TransactionWithDetails].self, from: data))
    }

    func testBudgetsSummaryFixtureDecodesWithCurrentDecoder() throws {
        let data = try loadFixture(named: "budgets-summary")
        let decoder = makeDecoder()

        XCTAssertNoThrow(try decoder.decode(MonthlySummaryResponse.self, from: data))
    }

    func testBudgetsDailySummaryFixtureDecodesWithCurrentDecoder() throws {
        let data = try loadFixture(named: "budgets-daily-summary")
        let decoder = makeDecoder()

        XCTAssertNoThrow(try decoder.decode(DailySummaryResponse.self, from: data))
    }

    private func makeDecoder() -> JSONDecoder {
        // Mirrors the current APIClient decoder strategy so this stays a contract test.
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    private func loadFixture(named name: String) throws -> Data {
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/API/\(name).json")
        return try Data(contentsOf: fixtureURL)
    }
}
