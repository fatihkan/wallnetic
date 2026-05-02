import Foundation
import Compression
import CryptoKit

/// Decrypts .mlw files from mylivewallpapers.com to standard MP4 video.
///
/// MLW format: AES-128-GCM encrypted MP4 container
/// Structure: [Magic Tag] [Version] [Metadata Block] [Encrypted Video Block]
enum MLWDecryptor {

    // MARK: - Keys (from MLWapp v0.1.3)

    private static let keyVideo = SymmetricKey(data: Data([
        0xd2, 0x7e, 0x15, 0x46, 0x28, 0xae, 0x2b, 0xa6,
        0xab, 0x4b, 0x97, 0x75, 0x16, 0x5f, 0xf7, 0x37
    ]))

    private static let keyDepth = SymmetricKey(data: Data([
        0xae, 0x2b, 0xd2, 0x4b, 0x97, 0xab, 0x75, 0x16,
        0x28, 0x37, 0xa6, 0x7e, 0x15, 0x46, 0xf7, 0x5f
    ]))

    private static let magicVideo = Data("MLW.VIDEO".utf8)
    private static let magicDepth = Data("MLW.DEPTH".utf8)

    enum MLWError: LocalizedError {
        case invalidMagic
        case unsupportedVersion(UInt32)
        case invalidBlockID(UInt32)
        case decryptionFailed
        case fileTooSmall
        case noMLWInArchive

        var errorDescription: String? {
            switch self {
            case .invalidMagic: return "Not a valid MLW file"
            case .unsupportedVersion(let v): return "Unsupported MLW version: \(v)"
            case .invalidBlockID(let id): return "Unexpected block ID: \(String(format: "0x%08X", id))"
            case .decryptionFailed: return "AES-GCM decryption failed"
            case .fileTooSmall: return "MLW file is too small"
            case .noMLWInArchive: return "No .mlw file found in ZIP archive"
            }
        }
    }

    // MARK: - Public API

    /// Decrypt an MLW file to MP4 data
    static func decrypt(data: Data) throws -> Data {
        guard data.count > 80 else { throw MLWError.fileTooSmall }

        var pos = 0

        // 1. Read magic tag (null-terminated)
        guard let nullIdx = data[pos...].firstIndex(of: 0) else { throw MLWError.invalidMagic }
        let magic = data[pos..<nullIdx]
        pos = nullIdx + 1

        let key: SymmetricKey
        if magic == magicVideo {
            key = keyVideo
        } else if magic == magicDepth {
            key = keyDepth
        } else {
            throw MLWError.invalidMagic
        }

        // 2. Read version (4 bytes, big-endian)
        let version = data.uint32BE(at: pos)
        pos += 4
        guard version <= 1 else { throw MLWError.unsupportedVersion(version) }

        // 3. Skip metadata block (block ID 0x01010101)
        let metaBlockID = data.uint32BE(at: pos)
        pos += 4
        guard metaBlockID == 0x01010101 else { throw MLWError.invalidBlockID(metaBlockID) }

        let metaBlockSize = Int(data.uint64BE(at: pos))
        pos += 8
        pos += metaBlockSize // skip metadata content

        // 4. Read encrypted data block (block ID 0x02020202)
        let dataBlockID = data.uint32BE(at: pos)
        pos += 4
        guard dataBlockID == 0x02020202 else { throw MLWError.invalidBlockID(dataBlockID) }

        let dataBlockSize = Int(data.uint64BE(at: pos))
        pos += 8

        // Block data: [16-byte IV] [encrypted payload] [16-byte GCM tag]
        let ivData = data[pos..<pos + 12]          // Only first 12 bytes used as GCM nonce
        pos += 16                                    // Skip full 16-byte IV field

        let ciphertextEnd = pos + dataBlockSize - 32 // 16 IV + 16 tag = 32
        let ciphertext = data[pos..<ciphertextEnd]
        let tag = data[ciphertextEnd..<ciphertextEnd + 16]

        // 5. Decrypt with AES-128-GCM
        do {
            let nonce = try AES.GCM.Nonce(data: ivData)
            let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
            let decrypted = try AES.GCM.open(sealedBox, using: key)
            return decrypted
        } catch {
            Log.mlw.error("Decryption error: \(error.localizedDescription, privacy: .public)")
            throw MLWError.decryptionFailed
        }
    }

    /// Decrypt an MLW file at the given path and write MP4 to output path
    @discardableResult
    static func decrypt(fileAt input: URL, to output: URL) throws -> URL {
        let data = try Data(contentsOf: input)
        let mp4 = try decrypt(data: data)
        try mp4.write(to: output)
        Log.mlw.info("Decrypted \(mp4.count) bytes → \(output.lastPathComponent, privacy: .public)")
        return output
    }

    /// Extract .mlw from a ZIP archive and decrypt to MP4 data
    static func decryptFromZIP(data zipData: Data) throws -> Data {
        guard let mlwData = ZIPReader.extractFirst(matching: ".mlw", from: zipData) else {
            throw MLWError.noMLWInArchive
        }
        return try decrypt(data: mlwData)
    }

    /// Extract .mlw from a ZIP file, decrypt, and write MP4
    @discardableResult
    static func decryptFromZIP(fileAt zipURL: URL, to output: URL) throws -> URL {
        let zipData = try Data(contentsOf: zipURL)
        let mp4 = try decryptFromZIP(data: zipData)
        try mp4.write(to: output)
        Log.mlw.info("ZIP → MLW → MP4: \(mp4.count) bytes → \(output.lastPathComponent, privacy: .public)")
        return output
    }

    /// Check if a URL points to a potential MLW zip download (from mylivewallpapers.com)
    static func isMLWSource(url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        return host.contains("mylivewallpapers.com")
    }
}

// MARK: - Minimal ZIP Reader

/// Reads ZIP local file headers to extract files without external dependencies.
enum ZIPReader {

    private static let localFileHeaderSig: UInt32 = 0x04034b50

    /// Extract the first file whose name ends with the given suffix
    static func extractFirst(matching suffix: String, from data: Data) -> Data? {
        var offset = 0

        while offset + 30 <= data.count {
            let sig = data.uint32LE(at: offset)
            guard sig == localFileHeaderSig else { break }

            let compressionMethod = data.uint16LE(at: offset + 8)
            let compressedSize = Int(data.uint32LE(at: offset + 18))
            let uncompressedSize = Int(data.uint32LE(at: offset + 22))
            let nameLength = Int(data.uint16LE(at: offset + 26))
            let extraLength = Int(data.uint16LE(at: offset + 28))

            let nameStart = offset + 30
            let nameEnd = nameStart + nameLength
            guard nameEnd <= data.count else { break }

            let fileName = String(data: data[nameStart..<nameEnd], encoding: .utf8) ?? ""
            let dataStart = nameEnd + extraLength

            guard dataStart + compressedSize <= data.count else { break }

            if fileName.lowercased().hasSuffix(suffix.lowercased()) {
                let fileData = data[dataStart..<dataStart + compressedSize]

                if compressionMethod == 0 {
                    // Stored (no compression)
                    return Data(fileData)
                } else if compressionMethod == 8 {
                    // Deflate — use zlib to decompress
                    return inflate(Data(fileData), expectedSize: uncompressedSize)
                }
            }

            offset = dataStart + compressedSize

            // Skip optional data descriptor (if bit 3 of general purpose flag is set)
            let flags = data.uint16LE(at: offset - compressedSize - nameLength - extraLength - 30 + 6)
            if flags & 0x0008 != 0 {
                // Data descriptor: may have optional signature + crc32 + sizes
                if offset + 4 <= data.count && data.uint32LE(at: offset) == 0x08074b50 {
                    offset += 16 // sig + crc32 + compressed + uncompressed (4 bytes each)
                } else {
                    offset += 12 // crc32 + compressed + uncompressed
                }
            }
        }
        return nil
    }

    /// Inflate (decompress) deflate-compressed data using raw deflate (no zlib header)
    private static func inflate(_ data: Data, expectedSize: Int) -> Data? {
        // Use NSData's built-in decompression isn't available, use compression framework
        var decompressed = Data(count: expectedSize)
        let result = decompressed.withUnsafeMutableBytes { destPtr in
            data.withUnsafeBytes { srcPtr in
                compression_decode_buffer(
                    destPtr.bindMemory(to: UInt8.self).baseAddress!,
                    expectedSize,
                    srcPtr.bindMemory(to: UInt8.self).baseAddress!,
                    data.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }
        guard result > 0 else { return nil }
        decompressed.count = result
        return decompressed
    }
}

// MARK: - Data Helpers (alignment-safe, byte-by-byte)

private extension Data {
    func uint16LE(at i: Int) -> UInt16 {
        UInt16(self[i]) | UInt16(self[i+1]) << 8
    }

    func uint32LE(at i: Int) -> UInt32 {
        UInt32(self[i]) | UInt32(self[i+1]) << 8 | UInt32(self[i+2]) << 16 | UInt32(self[i+3]) << 24
    }

    func uint32BE(at i: Int) -> UInt32 {
        UInt32(self[i]) << 24 | UInt32(self[i+1]) << 16 | UInt32(self[i+2]) << 8 | UInt32(self[i+3])
    }

    func uint64BE(at i: Int) -> UInt64 {
        let hi: UInt64 = UInt64(self[i]) << 56 | UInt64(self[i+1]) << 48 | UInt64(self[i+2]) << 40 | UInt64(self[i+3]) << 32
        let lo: UInt64 = UInt64(self[i+4]) << 24 | UInt64(self[i+5]) << 16 | UInt64(self[i+6]) << 8 | UInt64(self[i+7])
        return hi | lo
    }
}
