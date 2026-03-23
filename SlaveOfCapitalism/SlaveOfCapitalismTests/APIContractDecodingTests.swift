import Foundation
import XCTest
@testable import SlaveOfCapitalism

final class APIContractDecodingTests: XCTestCase {
    func testWalletsFixtureDecodesWithCurrentDecoder() throws {
        let data = try loadFixture(named: "wallets-list")
        XCTAssertNoThrow(try APIModelDecoder.decode([WalletWithBalance].self, from: data))
    }

    func testTransactionsFixtureDecodesWithCurrentDecoder() throws {
        let data = try loadFixture(named: "transactions-list")
        XCTAssertNoThrow(try APIModelDecoder.decode([TransactionWithDetails].self, from: data))
    }

    func testBudgetsSummaryFixtureDecodesWithCurrentDecoder() throws {
        let data = try loadFixture(named: "budgets-summary")
        XCTAssertNoThrow(try APIModelDecoder.decode(MonthlySummaryResponse.self, from: data))
    }

    func testBudgetsDailySummaryFixtureDecodesWithCurrentDecoder() throws {
        let data = try loadFixture(named: "budgets-daily-summary")
        XCTAssertNoThrow(try APIModelDecoder.decode(DailySummaryResponse.self, from: data))
    }

    func testNumericStringFallbackNormalizesOnlyNumericTokens() throws {
        struct Fixture: Decodable {
            let invoice: Invoice
            let label: String
        }

        struct Invoice: Decodable {
            let amount: Decimal
            let code: String
        }

        let data = Data(#"""
        {
          "invoice": {
            "amount": "19.75",
            "code": "01234"
          },
          "label": "invoice-001"
        }
        """#.utf8)

        let decoded = try APIModelDecoder.decode(Fixture.self, from: data)

        XCTAssertEqual(NSDecimalNumber(decimal: decoded.invoice.amount), NSDecimalNumber(string: "19.75"))
        XCTAssertEqual(decoded.invoice.code, "01234")
        XCTAssertEqual(decoded.label, "invoice-001")
    }

    func testDecimalStringPreservesHighPrecision() throws {
        struct Fixture: Decodable {
            let amount: Decimal
        }

        let expected = "12345678901234567890.123456789012345678"
        let data = Data(#"""
        {
          "amount": "\#(expected)"
        }
        """#.utf8)

        let decoded = try APIModelDecoder.decode(Fixture.self, from: data)

        XCTAssertEqual(NSDecimalNumber(decimal: decoded.amount), NSDecimalNumber(string: expected))
    }

    func testNumericLookingStringFieldRemainsStringWhenDecimalAlsoDecodes() throws {
        struct Fixture: Decodable {
            let postalCode: String
            let amount: Decimal
            let note: String
        }

        let data = Data(#"""
        {
          "postal_code": "01234",
          "amount": "19.75",
          "note": "invoice 01234"
        }
        """#.utf8)

        let decoded = try APIModelDecoder.decode(Fixture.self, from: data)

        XCTAssertEqual(decoded.postalCode, "01234")
        XCTAssertEqual(NSDecimalNumber(decimal: decoded.amount), NSDecimalNumber(string: "19.75"))
        XCTAssertEqual(decoded.note, "invoice 01234")
    }

    private func loadFixture(named name: String) throws -> Data {
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/API/\(name).json")
        return try Data(contentsOf: fixtureURL)
    }
}
