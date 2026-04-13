import XCTest
@testable import Wallnetic

final class ColorCategoryTests: XCTestCase {

    // MARK: - Color Classification

    func testBlackDetection() {
        let color = NSColor(red: 0.05, green: 0.05, blue: 0.05, alpha: 1.0)
        XCTAssertEqual(ColorCategory.from(color: color), .black)
    }

    func testWhiteDetection() {
        let color = NSColor(red: 0.95, green: 0.95, blue: 0.95, alpha: 1.0)
        XCTAssertEqual(ColorCategory.from(color: color), .white)
    }

    func testGrayDetection() {
        let color = NSColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0)
        XCTAssertEqual(ColorCategory.from(color: color), .gray)
    }

    func testRedDetection() {
        let color = NSColor(red: 0.9, green: 0.1, blue: 0.1, alpha: 1.0)
        XCTAssertEqual(ColorCategory.from(color: color), .red)
    }

    func testBlueDetection() {
        let color = NSColor(red: 0.1, green: 0.2, blue: 0.9, alpha: 1.0)
        XCTAssertEqual(ColorCategory.from(color: color), .blue)
    }

    func testGreenDetection() {
        let color = NSColor(red: 0.1, green: 0.8, blue: 0.2, alpha: 1.0)
        XCTAssertEqual(ColorCategory.from(color: color), .green)
    }

    func testYellowDetection() {
        let color = NSColor(red: 0.9, green: 0.9, blue: 0.1, alpha: 1.0)
        XCTAssertEqual(ColorCategory.from(color: color), .yellow)
    }

    func testOrangeDetection() {
        let color = NSColor(red: 0.95, green: 0.5, blue: 0.1, alpha: 1.0)
        XCTAssertEqual(ColorCategory.from(color: color), .orange)
    }

    func testPurpleDetection() {
        let color = NSColor(red: 0.5, green: 0.1, blue: 0.8, alpha: 1.0)
        XCTAssertEqual(ColorCategory.from(color: color), .purple)
    }

    // MARK: - All Cases

    func testAllCasesHaveUniqueIds() {
        let ids = ColorCategory.allCases.map { $0.id }
        XCTAssertEqual(ids.count, Set(ids).count, "All color categories should have unique ids")
    }

    func testAllCasesCount() {
        XCTAssertEqual(ColorCategory.allCases.count, 11)
    }

    // MARK: - NSColor Hex

    func testNSColorHexInit() {
        let color = NSColor(hex: "#FF0000")
        XCTAssertNotNil(color)

        let rgb = color!.usingColorSpace(.sRGB)!
        XCTAssertEqual(rgb.redComponent, 1.0, accuracy: 0.01)
        XCTAssertEqual(rgb.greenComponent, 0.0, accuracy: 0.01)
        XCTAssertEqual(rgb.blueComponent, 0.0, accuracy: 0.01)
    }

    func testNSColorHexWithoutHash() {
        let color = NSColor(hex: "00FF00")
        XCTAssertNotNil(color)
    }

    func testNSColorHexInvalid() {
        XCTAssertNil(NSColor(hex: "invalid"))
        XCTAssertNil(NSColor(hex: ""))
        XCTAssertNil(NSColor(hex: "#ZZZ"))
    }
}
