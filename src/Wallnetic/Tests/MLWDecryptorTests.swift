import XCTest
@testable import Wallnetic

final class MLWDecryptorTests: XCTestCase {

    // MARK: - Magic Bytes Detection

    func testDetectsMLWVideoMagic() {
        let data = Data("MLW.VIDEO".utf8) + Data(repeating: 0, count: 100)
        let result = try? MLWDecryptor.decrypt(data: data)
        XCTAssertNil(result) // Incomplete but should not crash
    }

    func testDetectsMLWDepthMagic() {
        let data = Data("MLW.DEPTH".utf8) + Data(repeating: 0, count: 100)
        let result = try? MLWDecryptor.decrypt(data: data)
        XCTAssertNil(result)
    }

    func testRejectsNonMLWData() {
        let data = Data("NOT_MLW_FILE".utf8)
        XCTAssertThrowsError(try MLWDecryptor.decrypt(data: data))
    }

    func testEmptyDataThrows() {
        XCTAssertThrowsError(try MLWDecryptor.decrypt(data: Data()))
    }

    func testSmallDataThrows() {
        XCTAssertThrowsError(try MLWDecryptor.decrypt(data: Data([0x01, 0x02, 0x03])))
    }
}
