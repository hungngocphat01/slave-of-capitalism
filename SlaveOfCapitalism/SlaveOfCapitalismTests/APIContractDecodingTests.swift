import Foundation
import XCTest
@testable import SlaveOfCapitalism

final class APIContractDecodingTests: XCTestCase {
    func testWalletsFixtureDecodesWithCurrentDecoder() throws {
        let data = try loadFixture(named: "wallets-list")
        XCTAssertNoThrow(try APIModelDecoder.decode([WalletWithBalance].self, from: data, endpoint: "/api/wallets/"))
    }

    func testTransactionsFixtureDecodesWithCurrentDecoder() throws {
        let data = try loadFixture(named: "transactions-list")
        XCTAssertNoThrow(try APIModelDecoder.decode([TransactionWithDetails].self, from: data, endpoint: "/api/transactions/"))
    }

    func testBudgetsSummaryFixtureDecodesWithCurrentDecoder() throws {
        let data = try loadFixture(named: "budgets-summary")
        XCTAssertNoThrow(try APIModelDecoder.decode(MonthlySummaryResponse.self, from: data, endpoint: "/api/budgets/summary/2026/3"))
    }

    func testBudgetsDailySummaryFixtureDecodesWithCurrentDecoder() throws {
        let data = try loadFixture(named: "budgets-daily-summary")
        XCTAssertNoThrow(try APIModelDecoder.decode(DailySummaryResponse.self, from: data, endpoint: "/api/budgets/daily-summary/2026/3"))
    }

    func testNumericStringFallbackNormalizesOnlyNumericTokens() throws {
        struct Fixture: Decodable {
            let count: Int
            let amount: Decimal
            let label: String
            let nested: Nested
        }

        struct Nested: Decodable {
            let ratio: Double
            let note: String
        }

        let data = Data(#"""
        {
          "count": "42",
          "amount": "19.75",
          "label": "invoice-001",
          "nested": {
            "ratio": "0.5",
            "note": "v1.2.3"
          }
        }
        """#.utf8)

        let decoded = try APIModelDecoder.decode(Fixture.self, from: data, endpoint: "/api/test")

        XCTAssertEqual(decoded.count, 42)
        XCTAssertEqual(NSDecimalNumber(decimal: decoded.amount), NSDecimalNumber(string: "19.75"))
        XCTAssertEqual(decoded.label, "invoice-001")
        XCTAssertEqual(decoded.nested.ratio, 0.5)
        XCTAssertEqual(decoded.nested.note, "v1.2.3")
    }

    private func loadFixture(named name: String) throws -> Data {
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/API/\(name).json")
        return try Data(contentsOf: fixtureURL)
    }
}
