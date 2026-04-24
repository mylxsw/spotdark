import XCTest
@testable import SpotdarkCore

final class CalculatorProviderTests: XCTestCase {
    func testEvaluateRecognizesBasicMathExpression() {
        let calculator = ExpressionCalculator()

        let result = calculator.evaluate(query: "32+24")

        XCTAssertEqual(result?.displayResult, "56")
        XCTAssertEqual(result?.copyValue, "56")
    }

    func testEvaluateRecognizesFullWidthMathExpression() {
        let calculator = ExpressionCalculator()

        let result = calculator.evaluate(query: "３２＋２４")

        XCTAssertEqual(result?.displayResult, "56")
        XCTAssertEqual(result?.copyValue, "56")
    }

    func testEvaluateRecognizesFullWidthParenthesesAndMultiplication() {
        let calculator = ExpressionCalculator()

        let result = calculator.evaluate(query: "（３＋２）×４")

        XCTAssertEqual(result?.displayResult, "20")
        XCTAssertEqual(result?.copyValue, "20")
    }
}
