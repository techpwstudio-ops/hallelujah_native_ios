import CommonCrypto
import CryptoKit
import Foundation

/// Read-only decoder for the AES-encrypted Hive box the Flutter build kept
/// its session in (`StorageService`, `lib/services/storage_service.dart`) —
/// just enough of hive 2.2.3's on-disk format for
/// `LegacyFlutterSessionMigration` to carry a signed-in user over on the
/// App Store update.
///
/// A box file is frames appended back to back (`BinaryWriterImpl.writeFrame`),
/// a later frame overriding an earlier one with the same key and a frame with
/// no value deleting it:
///
///     u32 LE  frame length — counts itself and the trailing CRC
///     u8      key type: 0 = u32 key, 1 = UTF-8 string key (u8 length + bytes)
///     …       16-byte IV + AES-256-CBC/PKCS7 of the typed value (absent = deleted)
///     u32 LE  CRC-32 of everything before it, seeded with CRC-32(SHA-256(key))
enum FlutterHiveBox {
    /// The live string-keyed entries, as Hive itself would read them back:
    /// `String`, `Int`, `Double`, `Bool`, `NSNull`, `Data`, `[Any]` or
    /// `[String: Any]`. `nil` when `aesKey` isn't a 256-bit key.
    static func entries(in data: Data, aesKey: [UInt8]) -> [String: Any]? {
        guard aesKey.count == kCCKeySizeAES256 else { return nil }
        let bytes = [UInt8](data)
        let keyCRC = crc32(SHA256.hash(data: Data(aesKey)))
        var entries: [String: Any] = [:]
        var offset = 0

        while bytes.count - offset >= 4 {
            let frameLength = Int(uint32(bytes[offset ..< offset + 4]))
            // Hive treats the first frame it can't trust as the end of the
            // box (and truncates the file there on its next open) — so does this.
            guard frameLength >= 8, frameLength <= bytes.count - offset else { break }
            let crcOffset = offset + frameLength - 4
            guard crc32(bytes[offset ..< crcOffset], seed: keyCRC) == uint32(bytes[crcOffset ..< crcOffset + 4]) else { break }

            var frame = Reader(bytes: bytes, position: offset + 4, end: crcOffset)
            offset += frameLength
            let frameKey: String?
            do {
                frameKey = try frame.key()
            } catch {
                break
            }
            // Integer keys only come from `box.add`, which StorageService never calls.
            guard let key = frameKey else { continue }
            // A value that won't decrypt or decode is dropped rather than
            // letting an older frame's value for the key stand in for it.
            entries[key] = frame.isAtEnd ? nil : value(decrypting: frame.remaining, aesKey: aesKey)
        }
        return entries
    }

    private static func value(decrypting encrypted: ArraySlice<UInt8>, aesKey: [UInt8]) -> Any? {
        guard let plain = decrypt(encrypted, aesKey: aesKey) else { return nil }
        var reader = Reader(bytes: plain, position: 0, end: plain.count)
        return try? reader.value()
    }

    /// `HiveAesCipher.decrypt`: the first block is the IV.
    private static func decrypt(_ encrypted: ArraySlice<UInt8>, aesKey: [UInt8]) -> [UInt8]? {
        let blockSize = kCCBlockSizeAES128
        guard encrypted.count >= 2 * blockSize, encrypted.count % blockSize == 0 else { return nil }
        let iv = Array(encrypted.prefix(blockSize))
        let cipherText = Array(encrypted.dropFirst(blockSize))
        let capacity = cipherText.count
        var plain = [UInt8](repeating: 0, count: capacity)
        var plainLength = 0
        let status = CCCrypt(
            CCOperation(kCCDecrypt),
            CCAlgorithm(kCCAlgorithmAES),
            CCOptions(kCCOptionPKCS7Padding),
            aesKey, aesKey.count,
            iv,
            cipherText, cipherText.count,
            &plain, capacity,
            &plainLength
        )
        guard status == CCCryptorStatus(kCCSuccess) else { return nil }
        return Array(plain.prefix(plainLength))
    }

    private static func uint32(_ bytes: ArraySlice<UInt8>) -> UInt32 {
        var value: UInt32 = 0
        for (index, byte) in bytes.enumerated() {
            value |= UInt32(byte) << (8 * UInt32(index))
        }
        return value
    }

    /// Hive's `Crc32.compute`: plain CRC-32, chainable through `seed`.
    private static func crc32(_ bytes: some Sequence<UInt8>, seed: UInt32 = 0) -> UInt32 {
        var crc = seed ^ 0xFFFF_FFFF
        for byte in bytes {
            crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }

    private static let crcTable: [UInt32] = (0 ..< 256).map { index -> UInt32 in
        var crc = UInt32(index)
        for _ in 0 ..< 8 {
            crc = crc & 1 == 1 ? 0xEDB8_8320 ^ (crc >> 1) : crc >> 1
        }
        return crc
    }

    private struct Malformed: Error {}

    /// `BinaryReaderImpl`, limited to one frame (or one decrypted value).
    private struct Reader {
        let bytes: [UInt8]
        var position: Int
        let end: Int

        var isAtEnd: Bool { position >= end }
        var remaining: ArraySlice<UInt8> { bytes[position ..< end] }

        mutating func take(_ count: Int) throws -> ArraySlice<UInt8> {
            guard count <= end - position else { throw Malformed() }
            defer { position += count }
            return bytes[position ..< position + count]
        }

        mutating func byte() throws -> UInt8 {
            guard position < end else { throw Malformed() }
            defer { position += 1 }
            return bytes[position]
        }

        mutating func uint32() throws -> Int {
            try Int(FlutterHiveBox.uint32(take(4)))
        }

        mutating func float64() throws -> Double {
            let raw = try take(8)
            var bits: UInt64 = 0
            for (index, byte) in raw.enumerated() {
                bits |= UInt64(byte) << (8 * UInt64(index))
            }
            return Double(bitPattern: bits)
        }

        /// Dart ints are stored as doubles (`readInt` is `readDouble().toInt()`).
        mutating func integer() throws -> Int {
            let raw = try float64()
            guard let value = Int(exactly: raw.rounded(.towardZero)) else { throw Malformed() }
            return value
        }

        mutating func string() throws -> String {
            let raw = try take(uint32())
            guard let string = String(bytes: raw, encoding: .utf8) else { throw Malformed() }
            return string
        }

        /// `readKey` — `nil` for an integer key.
        mutating func key() throws -> String? {
            switch try byte() {
            case 0:
                _ = try take(4)
                return nil
            case 1:
                let raw = try take(Int(byte()))
                guard let key = String(bytes: raw, encoding: .utf8) else { throw Malformed() }
                return key
            default:
                throw Malformed()
            }
        }

        /// `read()` for Hive's built-in type ids (`FrameValueType`).
        mutating func value() throws -> Any {
            let typeID = try byte()
            switch typeID {
            case 0: return NSNull()
            case 1: return try integer()
            case 2: return try float64()
            case 3: return try byte() > 0
            case 4: return try string()
            case 5: return try Data(take(uint32()))
            case 6 ... 10:
                let count = try uint32()
                var items: [Any] = []
                for _ in 0 ..< count {
                    switch typeID {
                    case 6: try items.append(integer())
                    case 7: try items.append(float64())
                    case 8: try items.append(byte() > 0)
                    case 9: try items.append(string())
                    default: try items.append(value())
                    }
                }
                return items
            case 11:
                let count = try uint32()
                var map: [String: Any] = [:]
                for _ in 0 ..< count {
                    let key = try value()
                    let element = try value()
                    map[(key as? String) ?? "\(key)"] = element
                }
                return map
            default:
                // 12 (HiveList) and registered TypeAdapters — nothing
                // StorageService ever writes.
                throw Malformed()
            }
        }
    }
}
