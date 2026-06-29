import XCTest
@testable import KTStackKit

final class WordPressArgumentValidatorTests: XCTestCase {
    func testAcceptsValidURLs() throws {
        XCTAssertEqual(try WordPressArgumentValidator.validateURL("https://old.test"), "https://old.test")
        XCTAssertEqual(try WordPressArgumentValidator.validateURL("http://old.test:8080"), "http://old.test:8080")
        XCTAssertEqual(try WordPressArgumentValidator.validateURL("nadestore.vn"), "nadestore.vn")
    }

    func testRejectsOptionInjection() {
        for hostile in ["--require=/staging/evil.php", "-require=x", "--ssh=evil", "--path=/etc"] {
            XCTAssertThrowsError(try WordPressArgumentValidator.validateURL(hostile)) { error in
                guard let argError = error as? WordPressArgumentError,
                      case .invalidURL = argError
                else {
                    return XCTFail("expected invalidURL for \(hostile), got \(error)")
                }
            }
        }
    }

    func testRejectsLeadingDashHost() {
        for hostile in ["http://-evil.com", "-evil.com", "https://-x"] {
            XCTAssertThrowsError(try WordPressArgumentValidator.validateURL(hostile)) { error in
                XCTAssertEqual(error as? WordPressArgumentError, .invalidURL(hostile))
            }
        }
    }

    func testRejectsControlAndQuoteCharacters() {
        for hostile in ["https://old.test\u{0}", "https://old.test ; rm -rf", "https://old'test", "https://old\"test"] {
            XCTAssertThrowsError(try WordPressArgumentValidator.validateURL(hostile))
        }
    }

    func testTablePrefixValidation() throws {
        XCTAssertEqual(try WordPressArgumentValidator.validateTablePrefix("wp_"), "wp_")
        XCTAssertThrowsError(try WordPressArgumentValidator.validateTablePrefix("wp_; DROP"))
        XCTAssertThrowsError(try WordPressArgumentValidator.validateTablePrefix("--require"))
    }

    func testDatabaseNameValidation() throws {
        XCTAssertEqual(try WordPressArgumentValidator.validateDatabaseName("nadestore_2"), "nadestore_2")
        XCTAssertThrowsError(try WordPressArgumentValidator.validateDatabaseName("db; DROP"))
    }

    func testHostExtraction() {
        XCTAssertEqual(WordPressArgumentValidator.host(of: "https://old.test/wp"), "old.test")
        XCTAssertEqual(WordPressArgumentValidator.host(of: "http://old.test:8080"), "old.test:8080")
        XCTAssertEqual(WordPressArgumentValidator.host(of: "old.test"), "old.test")
    }
}
