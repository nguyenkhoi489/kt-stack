import CoreImage
import XCTest
@testable import KTStackKit

final class QRCodeGeneratorTests: XCTestCase {
    func testImageForValidURLReturnsRequestedSizeOrLarger() throws {
        let url = try XCTUnwrap(URL(string: "https://demo.trycloudflare.com"))
        let image = try XCTUnwrap(QRCodeGenerator.image(for: url, size: 200))

        XCTAssertGreaterThanOrEqual(image.size.width, 200)
        XCTAssertGreaterThanOrEqual(image.size.height, 200)
        XCTAssertEqual(image.size.width, image.size.height)
    }

    func testDifferentRequestedSizesProduceDifferentImageSizes() throws {
        let url = try XCTUnwrap(URL(string: "https://demo.trycloudflare.com"))
        let smallImage = try XCTUnwrap(QRCodeGenerator.image(for: url, size: 120))
        let largeImage = try XCTUnwrap(QRCodeGenerator.image(for: url, size: 240))

        XCTAssertGreaterThan(largeImage.size.width, smallImage.size.width)
        XCTAssertGreaterThan(largeImage.size.height, smallImage.size.height)
    }

    func testLongURLReturnsImage() throws {
        let longPath = String(repeating: "mobile-testing-path/", count: 20)
        let url = try XCTUnwrap(URL(string: "https://demo.trycloudflare.com/\(longPath)?preview=1"))

        XCTAssertNotNil(QRCodeGenerator.image(for: url, size: 200))
    }

    func testGeneratedQRDecodesToOriginalURL() throws {
        let url = try XCTUnwrap(URL(string: "https://demo.trycloudflare.com/mobile"))
        let image = try XCTUnwrap(QRCodeGenerator.image(for: url, size: 200))
        let imageData = try XCTUnwrap(image.tiffRepresentation)
        let ciImage = try XCTUnwrap(CIImage(data: imageData))
        let detector = try XCTUnwrap(CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [
            CIDetectorAccuracy: CIDetectorAccuracyHigh,
        ]))
        let features = detector.features(in: ciImage).compactMap { $0 as? CIQRCodeFeature }

        XCTAssertEqual(features.first?.messageString, url.absoluteString)
    }

    func testEmptyTextReturnsNil() {
        XCTAssertNil(QRCodeGenerator.image(for: "", size: 200))
        XCTAssertNil(QRCodeGenerator.image(for: "   ", size: 200))
    }

    func testNonPositiveSizeReturnsNil() throws {
        let url = try XCTUnwrap(URL(string: "https://demo.trycloudflare.com"))

        XCTAssertNil(QRCodeGenerator.image(for: url, size: 0))
    }
}
