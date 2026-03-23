import XCTest
@testable import SlaveOfCapitalism

final class PayPayParserTests: XCTestCase {

    func testParseCSVLine() {
        let fields = PayPayParser.parseCSVLine("a,b,c")
        XCTAssertEqual(fields, ["a", "b", "c"])
    }

    func testParseCSVLineWithQuotes() {
        let fields = PayPayParser.parseCSVLine("\"hello, world\",b,c")
        XCTAssertEqual(fields, ["hello, world", "b", "c"])
    }

    func testParseCSVLineWithEscapedQuotes() {
        let fields = PayPayParser.parseCSVLine("\"he said \"\"hi\"\"\",b")
        XCTAssertEqual(fields, ["he said \"hi\"", "b"])
    }

    func testParseJapaneseNumber() {
        XCTAssertEqual(PayPayParser.parseJapaneseNumber("1,000"), 1000)
        XCTAssertEqual(PayPayParser.parseJapaneseNumber("-"), 0)
        XCTAssertEqual(PayPayParser.parseJapaneseNumber(""), 0)
        XCTAssertEqual(PayPayParser.parseJapaneseNumber("500"), 500)
    }

    func testTranslateMethod() {
        XCTAssertEqual(PayPayParser.translateMethod("支払い"), "payment")
        XCTAssertEqual(PayPayParser.translateMethod("チャージ"), "charge")
        XCTAssertEqual(PayPayParser.translateMethod("unknown"), "unknown")
    }

    func testParseFullCSV() {
        let csv = """
        取引日,出金金額（円）,入金金額（円）,取引内容,取引先,取引方法,取引番号
        2025/12/10 12:17:20,500,-,支払い,コンビニ,PayPay残高,TX001
        2025/12/11 09:00:00,-,1000,受け取った金額,友人,PayPay残高,TX002
        """
        let rows = PayPayParser.parseCSV(csv)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].counterparty, "コンビニ")
        XCTAssertEqual(rows[1].depositAmount, "1000")
    }

    func testTransformRows() {
        let csv = """
        取引日,出金金額（円）,入金金額（円）,取引内容,取引先,取引方法,取引番号
        2025/12/10 12:17:20,500,-,支払い,コンビニ,PayPay残高,TX001
        """
        let raw = PayPayParser.parseCSV(csv)
        let transformed = PayPayParser.transform(raw)
        XCTAssertEqual(transformed.count, 1)
        XCTAssertEqual(transformed[0].date, "2025-12-10")
        XCTAssertEqual(transformed[0].time, "12:17:20")
        XCTAssertEqual(transformed[0].amount, 500)
        XCTAssertEqual(transformed[0].direction, "outflow")
        XCTAssertEqual(transformed[0].method, "payment")
    }
}
