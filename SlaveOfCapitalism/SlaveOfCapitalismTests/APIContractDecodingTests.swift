import Foundation
import XCTest
@testable import SlaveOfCapitalism

final class APIContractDecodingTests: XCTestCase {
    func testDecodeFailureDescriptionIncludesEndpointAndPreview() async throws {
        let payload = #"{"broken":true,"items":[1,2,3]}"#
        let client = makeClient(responseBody: Data(payload.utf8))
        defer { MockURLProtocol.requestHandler = nil }

        do {
            let _: [WalletWithBalance] = try await client.listWallets()
            XCTFail("Expected decode failure")
        } catch let error as APIError {
            let description = error.localizedDescription
            XCTAssertTrue(description.contains("api/wallets/"), "Expected endpoint in description: \(description)")
            XCTAssertTrue(description.contains(payload), "Expected payload preview in description: \(description)")
        } catch {
            XCTFail("Expected APIError, got \(error)")
        }
    }

    func testDecodeFailureDescriptionPreviewIsBoundedToFirst500Bytes() async throws {
        var bytes = [UInt8]()
        bytes.reserveCapacity(505)

        for _ in 0..<249 {
            bytes.append(0xC3)
            bytes.append(0xA9)
        }

        bytes.append(0x41)
        bytes.append(0xC3)
        bytes.append(0xA9)
        bytes.append(contentsOf: Array("TAIL".utf8))

        let client = makeClient(responseBody: Data(bytes))
        defer { MockURLProtocol.requestHandler = nil }

        do {
            let _: [WalletWithBalance] = try await client.listWallets()
            XCTFail("Expected decode failure")
        } catch let error as APIError {
            let description = error.localizedDescription
            XCTAssertTrue(description.contains("api/wallets/"), "Expected endpoint in description: \(description)")
            XCTAssertFalse(description.contains("TAIL"), "Expected preview to exclude bytes after the first 500: \(description)")
        } catch {
            XCTFail("Expected APIError, got \(error)")
        }
    }

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

    func testQuotedNumericFieldsDecodeWithoutTouchingStrings() throws {
        struct Fixture: Decodable {
            let count: Int
            let ratio: Double
            let amount: Decimal
            let code: String
        }

        let data = Data(#"""
        {
          "count": "42",
          "ratio": "0.125",
          "amount": "19.75",
          "code": "01234"
        }
        """#.utf8)

        let decoded = try APIModelDecoder.decode(Fixture.self, from: data)

        XCTAssertEqual(decoded.count, 42)
        XCTAssertEqual(decoded.ratio, 0.125)
        XCTAssertEqual(NSDecimalNumber(decimal: decoded.amount), NSDecimalNumber(string: "19.75"))
        XCTAssertEqual(decoded.code, "01234")
    }

    func testDecimalStringWithPrecisionLossDoesNotDecode() throws {
        struct Fixture: Decodable {
            let amount: Decimal
        }

        let expected = "1234567890123456789012345678901234567890.1234567890"
        let data = Data(#"""
        {
          "amount": "\#(expected)"
        }
        """#.utf8)

        XCTAssertThrowsError(try APIModelDecoder.decode(Fixture.self, from: data)) { error in
            guard case let DecodingError.typeMismatch(_, context) = error else {
                return XCTFail("Expected typeMismatch, got \(error)")
            }
            XCTAssertEqual(context.codingPath.map(\.stringValue), ["amount"])
        }
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

    private func makeClient(responseBody: Data) -> APIClient {
        MockURLProtocol.requestHandler = { request in
            let url = request.url ?? URL(string: "https://example.com")!
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseBody)
        }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        return APIClient(baseURL: URL(string: "https://example.com")!, session: session)
    }
}

private final class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
