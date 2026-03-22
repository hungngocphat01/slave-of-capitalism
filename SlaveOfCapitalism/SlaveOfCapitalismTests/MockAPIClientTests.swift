import XCTest
@testable import SlaveOfCapitalism

final class MockAPIClientTests: XCTestCase {
    func testTrackCallRecordsOrderAndPerMethodCounts() async throws {
        let client = MockAPIClient()
        client.walletsResult = []

        _ = try await client.listWallets()
        _ = try await client.healthCheck()
        _ = try await client.listWallets()

        XCTAssertEqual(client.lastCalledMethod, "listWallets")
        XCTAssertEqual(client.callLog, ["listWallets", "healthCheck", "listWallets"])
        XCTAssertEqual(client.callCount["listWallets"], 2)
        XCTAssertEqual(client.callCount["healthCheck"], 1)
    }

    func testUnconfiguredConfiguredReturnThrowsMockError() async {
        let client = MockAPIClient()

        do {
            _ = try await client.getWallet(id: 42)
            XCTFail("Expected unconfigured mock error")
        } catch let error as MockAPIClientError {
            XCTAssertEqual(error, .unconfigured("getWallet"))
            XCTAssertEqual(client.lastCalledMethod, "getWallet")
            XCTAssertEqual(client.callLog, ["getWallet"])
            XCTAssertEqual(client.callCount["getWallet"], 1)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testExplicitErrorStillThrowsAfterTracking() async {
        let client = MockAPIClient()
        client.errorToThrow = APIError.backendNotReady

        do {
            _ = try await client.listWallets()
            XCTFail("Expected configured error")
        } catch {
            XCTAssertEqual(client.lastCalledMethod, "listWallets")
            XCTAssertEqual(client.callLog, ["listWallets"])
            XCTAssertEqual(client.callCount["listWallets"], 1)
        }
    }
}
