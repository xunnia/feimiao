import XCTest
@testable import QingJiCore

final class AmountExpressionTests: XCTestCase {
    func testTypingSimpleAmount() {
        var expression = AmountExpression()
        expression.insertDigit("1")
        expression.insertDigit("2")
        expression.insertDot()
        expression.insertDigit("5")
        XCTAssertEqual(expression.displayText, "12.5")
        XCTAssertEqual(expression.value, Decimal(string: "12.5"))
        XCTAssertFalse(expression.isCompound)
    }

    func testLeadingZeroIsReplaced() {
        var expression = AmountExpression()
        expression.insertDigit("0")
        expression.insertDigit("7")
        XCTAssertEqual(expression.displayText, "7")
    }

    func testFractionDigitsLimitedToTwo() {
        var expression = AmountExpression()
        expression.insertDigit("1")
        expression.insertDot()
        expression.insertDigit("2")
        expression.insertDigit("3")
        expression.insertDigit("4")
        XCTAssertEqual(expression.displayText, "1.23")
    }

    func testSecondDotIsIgnored() {
        var expression = AmountExpression()
        expression.insertDigit("3")
        expression.insertDot()
        expression.insertDot()
        expression.insertDigit("5")
        XCTAssertEqual(expression.displayText, "3.5")
    }

    func testDotOnEmptyFieldPrependsZero() {
        var expression = AmountExpression()
        expression.insertDot()
        expression.insertDigit("5")
        XCTAssertEqual(expression.displayText, "0.5")
        XCTAssertEqual(expression.value, Decimal(string: "0.5"))
    }

    func testAddition() {
        var expression = AmountExpression()
        expression.insertDigit("1")
        expression.insertDigit("2")
        expression.beginAddition()
        expression.insertDigit("3")
        expression.insertDot()
        expression.insertDigit("5")
        XCTAssertEqual(expression.displayText, "12+3.5")
        XCTAssertEqual(expression.value, Decimal(string: "15.5"))
        XCTAssertTrue(expression.isCompound)
    }

    func testAdditionRequiresCurrentNumber() {
        var expression = AmountExpression()
        expression.beginAddition()
        XCTAssertEqual(expression.displayText, "0")
        XCTAssertFalse(expression.isCompound)
    }

    func testDeleteBackwardCrossesTerms() {
        var expression = AmountExpression()
        expression.insertDigit("8")
        expression.beginAddition()
        expression.insertDigit("2")
        expression.deleteBackward() // 删掉 2
        expression.deleteBackward() // 删掉空的第二段
        XCTAssertEqual(expression.displayText, "8")
        XCTAssertFalse(expression.isCompound)
        expression.deleteBackward() // 删掉 8
        XCTAssertTrue(expression.isEmpty)
        XCTAssertEqual(expression.value, 0)
    }

    func testClear() {
        var expression = AmountExpression()
        expression.insertDigit("9")
        expression.clear()
        XCTAssertTrue(expression.isEmpty)
        XCTAssertEqual(expression.displayText, "0")
    }
}
