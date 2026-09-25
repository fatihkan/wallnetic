import XCTest
import CryptoKit
import Compression
@testable import Wallnetic

final class MLWDecryptorTests: XCTestCase {
    func testValidContainerAndNonzeroBasedSliceDecrypt() throws {
        let (container, plaintext) = try fixture()
        XCTAssertEqual(try MLWDecryptor.decrypt(data: container), plaintext)
        let padded = Data([0xff]) + container
        XCTAssertEqual(try MLWDecryptor.decrypt(data: padded.dropFirst()), plaintext)
    }

    func testEveryTruncatedPrefixIsRejectedWithoutTrapping() throws {
        let (container, _) = try fixture()
        for length in 0..<container.count {
            XCTAssertThrowsError(try MLWDecryptor.decrypt(data: Data(container.prefix(length))), "length=\(length)")
        }
    }

    func testUntrustedBlockSizesAreRejectedBeforeConversionOrSlicing() throws {
        let (container, _) = try fixture()
        for offset in [18, 30] {
            for size in [UInt64.max, UInt64(Int.max), UInt64(container.count)] {
                var malformed = container
                malformed.replaceSubrange(offset..<offset + 8, with: bytesBE(size))
                XCTAssertThrowsError(try MLWDecryptor.decrypt(data: malformed))
            }
        }
        for size: UInt64 in [0, 1, 12, 16, 31] {
            var malformed = container
            malformed.replaceSubrange(30..<38, with: bytesBE(size))
            XCTAssertThrowsError(try MLWDecryptor.decrypt(data: malformed))
        }
    }

    func testZIPStoredContainerStillDecrypts() throws {
        let (container, plaintext) = try fixture()
        let archive = zipEntry(payload: container, expandedSize: UInt32(container.count), method: 0)
        XCTAssertEqual(try MLWDecryptor.decryptFromZIP(data: archive), plaintext)
    }

    func testZIPDeflatedContainerStillDecrypts() throws {
        let (container, plaintext) = try fixture()
        var compressed = Data(count: 1024)
        let count = compressed.withUnsafeMutableBytes { output in
            container.withUnsafeBytes { input in
                compression_encode_buffer(output.bindMemory(to: UInt8.self).baseAddress!, 1024,
                                          input.bindMemory(to: UInt8.self).baseAddress!, container.count,
                                          nil, COMPRESSION_ZLIB)
            }
        }
        XCTAssertGreaterThan(count, 0)
        compressed.count = count
        let archive = zipEntry(payload: compressed, expandedSize: UInt32(container.count), method: 8)
        XCTAssertEqual(try MLWDecryptor.decryptFromZIP(data: archive), plaintext)
    }

    func testZIPRejectsOversizedAndEmptyDeflateHeaders() {
        for size in [UInt32.max, UInt32(ZIPReader.maximumExtractedSize + 1), 0] {
            let archive = zipEntry(payload: Data([0]), expandedSize: size, method: 8)
            XCTAssertNil(ZIPReader.extractFirst(matching: ".mlw", from: archive))
        }
        XCTAssertNil(ZIPReader.extractFirst(matching: ".mlw", from: zipEntry(payload: Data(), expandedSize: 16, method: 8)))
    }

    private func fixture() throws -> (Data, Data) {
        let key = SymmetricKey(data: Data([
            0xd2, 0x7e, 0x15, 0x46, 0x28, 0xae, 0x2b, 0xa6,
            0xab, 0x4b, 0x97, 0x75, 0x16, 0x5f, 0xf7, 0x37
        ]))
        let plaintext = Data(repeating: 0x42, count: 64)
        let nonceData = Data(repeating: 0x11, count: 12)
        let sealed = try AES.GCM.seal(plaintext, using: key, nonce: AES.GCM.Nonce(data: nonceData))
        var data = Data("MLW.VIDEO\0".utf8)
        data += Data([0, 0, 0, 1, 1, 1, 1, 1]) // Version 1, metadata block ID.
        data += bytesBE(0)
        data += Data([2, 2, 2, 2])
        data += bytesBE(UInt64(sealed.ciphertext.count + 32))
        data += nonceData + Data(repeating: 0, count: 4)
        data += sealed.ciphertext + sealed.tag
        return (data, plaintext)
    }

    private func bytesBE(_ value: UInt64) -> Data {
        var value = value.bigEndian
        return withUnsafeBytes(of: &value) { Data($0) }
    }

    private func zipEntry(payload: Data, expandedSize: UInt32, method: UInt16) -> Data {
        var header = Data(repeating: 0, count: 30)
        header.replaceSubrange(0..<4, with: [0x50, 0x4b, 0x03, 0x04])
        var methodLE = method.littleEndian
        withUnsafeBytes(of: &methodLE) { header.replaceSubrange(8..<10, with: $0) }
        var compressedLE = UInt32(payload.count).littleEndian
        withUnsafeBytes(of: &compressedLE) { header.replaceSubrange(18..<22, with: $0) }
        var expandedLE = expandedSize.littleEndian
        withUnsafeBytes(of: &expandedLE) { header.replaceSubrange(22..<26, with: $0) }
        let name = Data("clip.mlw".utf8)
        header[26] = UInt8(name.count)
        return header + name + payload
    }

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
