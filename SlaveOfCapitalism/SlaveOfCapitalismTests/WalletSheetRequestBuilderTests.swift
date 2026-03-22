import XCTest
@testable import SlaveOfCapitalism

final class WalletSheetRequestBuilderTests: XCTestCase {
    func testTransferRequestBuilderConstructsWalletTransferRequest() throws {
        let date = makeDate(year: 2026, month: 3, day: 22)

        let request = try TransferSheetRequestBuilder.makeRequest(
            fromWalletId: 1,
            toWalletId: 2,
            amountText: "1,250.50",
            description: "Move to savings",
            date: date
        )

        XCTAssertEqual(request.fromWalletId, 1)
        XCTAssertEqual(request.toWalletId, 2)
        XCTAssertEqual(request.amount, Decimal(string: "1250.50"))
        XCTAssertEqual(request.description, "Move to savings")
        XCTAssertEqual(request.date, "2026-03-22")
        XCTAssertNil(request.time)
    }

    func testCalibrateRequestBuilderConstructsCalibrationRequest() throws {
        let request = try CalibrateSheetRequestBuilder.makeRequest(
            correctBalanceText: "9,999",
            categoryId: 42
        )

        XCTAssertEqual(request.correctBalance, Decimal(string: "9999"))
        XCTAssertEqual(request.miscCategoryId, 42)
    }

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.year = year
        components.month = month
        components.day = day
        components.timeZone = TimeZone(secondsFromGMT: 0)
        return components.date!
    }
}
