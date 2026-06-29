import XCTest
@testable import KTStackKit

final class APIVariableInterpolatorTests: XCTestCase {
    func testResolvesSingleVariable() {
        let result = APIVariableInterpolator.resolve("https://{{host}}/api", with: ["host": "app.test"])
        XCTAssertEqual(result, "https://app.test/api")
    }

    func testResolvesMultipleVariables() {
        let result = APIVariableInterpolator.resolve(
            "{{scheme}}://{{host}}/{{path}}",
            with: ["scheme": "https", "host": "app.test", "path": "users"]
        )
        XCTAssertEqual(result, "https://app.test/users")
    }

    func testTrimsWhitespaceInsideBraces() {
        let result = APIVariableInterpolator.resolve("Bearer {{ token }}", with: ["token": "abc"])
        XCTAssertEqual(result, "Bearer abc")
    }

    func testUnknownVariableKeptVerbatim() {
        let result = APIVariableInterpolator.resolve("{{missing}}/x", with: ["host": "app.test"])
        XCTAssertEqual(result, "{{missing}}/x")
    }

    func testDoesNotTouchSingleBraces() {
        let result = APIVariableInterpolator.resolve("/users/{id}", with: ["id": "5"])
        XCTAssertEqual(result, "/users/{id}")
    }

    func testTextWithoutVariablesUnchanged() {
        let result = APIVariableInterpolator.resolve("plain text", with: ["a": "b"])
        XCTAssertEqual(result, "plain text")
    }

    func testUnterminatedBraceKeptVerbatim() {
        let result = APIVariableInterpolator.resolve("start {{ open", with: ["open": "x"])
        XCTAssertEqual(result, "start {{ open")
    }

    func testValueContainingSpecialCharacters() {
        let result = APIVariableInterpolator.resolve("token={{t}}", with: ["t": "a&b=c"])
        XCTAssertEqual(result, "token=a&b=c")
    }

    func testEmptyValueResolvesToEmpty() {
        let result = APIVariableInterpolator.resolve("x{{e}}y", with: ["e": ""])
        XCTAssertEqual(result, "xy")
    }
}
