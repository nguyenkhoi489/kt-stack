import XCTest
@testable import KTStackKit

final class MongoJSONMapperTests: XCTestCase {
    private func roundTrip(_ json: String) throws -> Any {
        let document = try MongoJSONMapper.document(fromJSON: json)
        let encoded = try MongoJSONMapper.encodedJSON(from: document, pretty: false)
        return try JSONSerialization.jsonObject(with: Data(encoded.utf8), options: [.fragmentsAllowed])
    }

    func testScalarTypesRoundTrip() throws {
        let result = try roundTrip(#"{"name":"a","count":3,"ratio":1.5,"active":true,"missing":null}"#)
        let dictionary = try XCTUnwrap(result as? [String: Any])
        XCTAssertEqual(dictionary["name"] as? String, "a")
        XCTAssertEqual(dictionary["count"] as? Int, 3)
        XCTAssertEqual(dictionary["ratio"] as? Double, 1.5)
        XCTAssertEqual(dictionary["active"] as? Bool, true)
        XCTAssertTrue(dictionary["missing"] is NSNull)
    }

    func testBooleanIsNotCoercedToInteger() throws {
        let result = try roundTrip(#"{"flag":true,"zero":0}"#)
        let dictionary = try XCTUnwrap(result as? [String: Any])
        XCTAssertEqual((dictionary["flag"] as? NSNumber), true)
        XCTAssertFalse((dictionary["flag"] as? NSNumber) === (dictionary["zero"] as? NSNumber))
        XCTAssertEqual(dictionary["zero"] as? Int, 0)
    }

    func testNestedDocumentAndArrayRoundTrip() throws {
        let result = try roundTrip(#"{"meta":{"tags":["x","y"],"n":2},"items":[1,2,3]}"#)
        let dictionary = try XCTUnwrap(result as? [String: Any])
        let meta = try XCTUnwrap(dictionary["meta"] as? [String: Any])
        XCTAssertEqual(meta["tags"] as? [String], ["x", "y"])
        XCTAssertEqual(meta["n"] as? Int, 2)
        XCTAssertEqual(dictionary["items"] as? [Int], [1, 2, 3])
    }

    func testObjectIdHintRoundTrips() throws {
        let result = try roundTrip(#"{"_id":{"$oid":"507f1f77bcf86cd799439011"}}"#)
        let dictionary = try XCTUnwrap(result as? [String: Any])
        let id = try XCTUnwrap(dictionary["_id"] as? [String: Any])
        XCTAssertEqual(id["$oid"] as? String, "507f1f77bcf86cd799439011")
    }

    func testDateHintRoundTrips() throws {
        let result = try roundTrip(#"{"created":{"$date":"2026-01-02T03:04:05.000Z"}}"#)
        let dictionary = try XCTUnwrap(result as? [String: Any])
        let date = try XCTUnwrap(dictionary["created"] as? [String: Any])
        XCTAssertEqual(date["$date"] as? String, "2026-01-02T03:04:05.000Z")
    }

    func testLargeIntegerRoundTripsWithoutTruncation() throws {
        let result = try roundTrip(#"{"ts":1700000000000}"#)
        let dictionary = try XCTUnwrap(result as? [String: Any])
        XCTAssertEqual((dictionary["ts"] as? NSNumber)?.int64Value, 1_700_000_000_000)
    }

    func testBinaryHintRoundTrips() throws {
        let base64 = Data([0x01, 0x02, 0x03]).base64EncodedString()
        let result = try roundTrip(#"{"blob":{"$binary":"\#(base64)"}}"#)
        let dictionary = try XCTUnwrap(result as? [String: Any])
        let blob = try XCTUnwrap(dictionary["blob"] as? [String: Any])
        XCTAssertEqual(blob["$binary"] as? String, base64)
    }

    func testTimestampHintRoundTrips() throws {
        let result = try roundTrip(#"{"ts":{"$timestamp":{"t":1700000000,"i":2}}}"#)
        let dictionary = try XCTUnwrap(result as? [String: Any])
        let timestamp = try XCTUnwrap(dictionary["ts"] as? [String: Any])
        let inner = try XCTUnwrap(timestamp["$timestamp"] as? [String: Any])
        XCTAssertEqual(inner["t"] as? Int, 1_700_000_000)
        XCTAssertEqual(inner["i"] as? Int, 2)
    }

    func testMalformedJSONThrows() {
        XCTAssertThrowsError(try MongoJSONMapper.document(fromJSON: "{not json"))
    }

    func testNonObjectTopLevelThrows() {
        XCTAssertThrowsError(try MongoJSONMapper.document(fromJSON: "[1,2,3]")) { error in
            XCTAssertEqual(error as? DatabaseError, .syntax("A document must be a JSON object."))
        }
    }
}
