import XCTest
@testable import KTStackKit

final class DumpEventDecoderTests: XCTestCase {
    private func json(_ dict: [String: Any]) -> Data {
        let payload: [String: Any] = [
            "timestamp": 1_700_000_000.0,
            "file": "/app/src/Controller.php",
            "line": 42,
            "value": dict,
        ]
        return try! JSONSerialization.data(withJSONObject: payload)
    }

    func testDecodesFileAndLine() throws {
        let event = try DumpEventDecoder.decode(line: json(["type": "null"]))
        XCTAssertEqual(event.file, "/app/src/Controller.php")
        XCTAssertEqual(event.line, 42)
    }

    func testDecodesTimestamp() throws {
        let event = try DumpEventDecoder.decode(line: json(["type": "null"]))
        XCTAssertEqual(event.timestamp.timeIntervalSince1970, 1_700_000_000.0, accuracy: 0.001)
    }

    func testDecodesNull() throws {
        let event = try DumpEventDecoder.decode(line: json(["type": "null"]))
        XCTAssertEqual(event.root, .scalar("null"))
    }

    func testDecodesBoolTrue() throws {
        let event = try DumpEventDecoder.decode(line: json(["type": "bool", "value": true]))
        XCTAssertEqual(event.root, .scalar("true"))
    }

    func testDecodesBoolFalse() throws {
        let event = try DumpEventDecoder.decode(line: json(["type": "bool", "value": false]))
        XCTAssertEqual(event.root, .scalar("false"))
    }

    func testDecodesInt() throws {
        let event = try DumpEventDecoder.decode(line: json(["type": "int", "value": 99]))
        XCTAssertEqual(event.root, .scalar("99"))
    }

    func testDecodesFloat() throws {
        let event = try DumpEventDecoder.decode(line: json(["type": "float", "value": 3.14]))
        if case let .scalar(s) = event.root {
            XCTAssertTrue(s.hasPrefix("3.14"), "Expected scalar to start with 3.14, got \(s)")
        } else {
            XCTFail("Expected scalar node")
        }
    }

    func testDecodesStringWithLength() throws {
        let event = try DumpEventDecoder.decode(line: json(["type": "string", "value": "hello", "length": 5]))
        XCTAssertEqual(event.root, .scalar("\"hello\" (5)"))
    }

    func testDecodesEmptyArray() throws {
        let event = try DumpEventDecoder.decode(line: json(["type": "array", "count": 0, "items": []]))
        if case let .array(items) = event.root {
            XCTAssertTrue(items.isEmpty)
        } else {
            XCTFail("Expected array node")
        }
    }

    func testDecodesArrayWithItems() throws {
        let items: [[String: Any]] = [
            ["key": "0", "value": ["type": "int", "value": 1]],
            ["key": "1", "value": ["type": "string", "value": "x", "length": 1]],
        ]
        let event = try DumpEventDecoder.decode(line: json(["type": "array", "count": 2, "items": items]))
        guard case let .array(children) = event.root else { return XCTFail("Expected array") }
        XCTAssertEqual(children.count, 2)
        XCTAssertEqual(children[0].key, "0")
        XCTAssertEqual(children[0].value, .scalar("1"))
        XCTAssertEqual(children[1].key, "1")
        XCTAssertEqual(children[1].value, .scalar("\"x\" (1)"))
    }

    func testDecodesObject() throws {
        let props: [[String: Any]] = [
            ["key": "name", "value": ["type": "string", "value": "KD", "length": 2]],
        ]
        let event = try DumpEventDecoder.decode(line: json(["type": "object", "class": "App\\User", "properties": props]))
        guard case let .object(cls, children) = event.root else { return XCTFail("Expected object") }
        XCTAssertEqual(cls, "App\\User")
        XCTAssertEqual(children.count, 1)
        XCTAssertEqual(children[0].key, "name")
    }

    func testDecodesTruncated() throws {
        let event = try DumpEventDecoder.decode(line: json(["type": "truncated"]))
        XCTAssertEqual(event.root, .scalar("…"))
    }

    func testDecodesResource() throws {
        let event = try DumpEventDecoder.decode(line: json(["type": "resource"]))
        XCTAssertEqual(event.root, .scalar("resource"))
    }

    func testThrowsOnInvalidJSON() {
        let garbage = "not json at all".data(using: .utf8)!
        XCTAssertThrowsError(try DumpEventDecoder.decode(line: garbage)) { error in
            XCTAssertEqual(error as? DumpEventDecoder.DecoderError, .invalidJSON)
        }
    }
}

extension DumpNode: Equatable {
    public static func == (lhs: DumpNode, rhs: DumpNode) -> Bool {
        switch (lhs, rhs) {
        case let (.scalar(a), .scalar(b)):
            return a == b
        case let (.reference(a), .reference(b)):
            return a == b
        case let (.array(a), .array(b)):
            guard a.count == b.count else { return false }
            return zip(a, b).allSatisfy { $0.key == $1.key && $0.value == $1.value }
        case let (.object(ac, ap), .object(bc, bp)):
            guard ac == bc, ap.count == bp.count else { return false }
            return zip(ap, bp).allSatisfy { $0.key == $1.key && $0.value == $1.value }
        default:
            return false
        }
    }
}
