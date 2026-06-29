import NIOCore
import XCTest
@testable import KTStackKit

/// Engine-free coverage of the text-protocol value → `Cell` classification — CI-blocking. The core
/// takes raw MySQL type/charset codes (the same bytes the wire protocol sends) so the rules are
/// proven without a live server. Raw codes used: 0x03 LONG, 0x05 DOUBLE, 0xfd VAR_STRING, 0xfc BLOB;
/// charset 33 utf8, 63 binary.
final class MySQLCellMapperTests: XCTestCase {
    private func buf(_ s: String) -> ByteBuffer {
        ByteBuffer(string: s)
    }

    private func bytes(_ b: [UInt8]) -> ByteBuffer {
        ByteBuffer(bytes: b)
    }

    func testNullBufferMapsToNullCell() {
        XCTAssertEqual(MySQLCellMapper.cell(typeRaw: 0xFD, charsetRaw: 33, value: nil), .null)
    }

    func testIntegerTypeParsesToIntCell() {
        XCTAssertEqual(MySQLCellMapper.cell(typeRaw: 0x03, charsetRaw: 63, value: buf("42")), .int(42))
    }

    func testIntegerOverflowFallsBackToTextNotLoss() {
        // Out-of-Int64-range value can't be an .int; keep it as text rather than dropping it.
        let huge = "99999999999999999999999999"
        XCTAssertEqual(MySQLCellMapper.cell(typeRaw: 0x08, charsetRaw: 63, value: buf(huge)), .text(huge))
    }

    func testFloatTypeParsesToDoubleCell() {
        XCTAssertEqual(MySQLCellMapper.cell(typeRaw: 0x05, charsetRaw: 63, value: buf("1.5")), .double(1.5))
    }

    func testDecimalStaysTextToPreserveExactDigits() {
        // NEWDECIMAL (0xf6) is exact fixed-point — routing through Double would truncate, so it stays
        // .text with the server's verbatim digits (a money column must not lose precision).
        let exact = "12345678901234567890.12345"
        XCTAssertEqual(MySQLCellMapper.cell(typeRaw: 0xF6, charsetRaw: 63, value: buf(exact)), .text(exact))
    }

    func testTextTypeStaysTextAndEmptyStringIsNotNull() {
        XCTAssertEqual(MySQLCellMapper.cell(typeRaw: 0xFD, charsetRaw: 33, value: buf("hello")), .text("hello"))
        XCTAssertEqual(MySQLCellMapper.cell(typeRaw: 0xFD, charsetRaw: 33, value: buf("")), .text(""))
    }

    func testBinaryCharsetOnBlobTypeBecomesBlob() {
        let raw: [UInt8] = [0x00, 0x01, 0xFF]
        XCTAssertEqual(MySQLCellMapper.cell(typeRaw: 0xFC, charsetRaw: 63, value: bytes(raw)), .blob(Data(raw)))
    }

    func testTextTypeWithUTF8CharsetIsNotTreatedAsBlob() {
        // A VAR_STRING in utf8 (charset 33) is character data, not a blob — even though VAR_STRING is
        // in the string/blob type family.
        XCTAssertFalse(MySQLCellMapper.isBinary(typeRaw: 0xFD, charsetRaw: 33))
        XCTAssertEqual(MySQLCellMapper.cell(typeRaw: 0xFD, charsetRaw: 33, value: buf("text")), .text("text"))
    }
}
