import Compression
import Foundation

/// 只读/写肥喵备份所需的 ZIP 子集：store 写入，store + deflate 读取。
/// Android 的 Archive 包使用这两种压缩方式；不引入第三方库，避免备份功能
/// 因 SwiftPM 网络或包版本变化而无法编译。
enum ZipArchiveError: LocalizedError {
    case invalidArchive
    case unsupportedArchive
    case unsafePath
    case checksumMismatch

    var errorDescription: String? {
        switch self {
        case .invalidArchive: return "备份 ZIP 结构损坏。"
        case .unsupportedArchive: return "备份 ZIP 使用了暂不支持的压缩方式。"
        case .unsafePath: return "备份包含不安全的文件路径。"
        case .checksumMismatch: return "备份文件校验失败，未导入任何数据。"
        }
    }
}

enum ZipArchive {
    struct Entry: Equatable {
        let path: String
        let data: Data

        init(path: String, data: Data) throws {
            guard ZipArchive.isSafePath(path) else { throw ZipArchiveError.unsafePath }
            self.path = path
            self.data = data
        }
    }

    static func encode(_ entries: [Entry]) throws -> Data {
        var seen = Set<String>()
        guard entries.allSatisfy({ seen.insert($0.path).inserted }) else {
            throw ZipArchiveError.invalidArchive
        }

        var output = Data()
        var centralDirectory = Data()
        for entry in entries {
            guard output.count <= Int(UInt32.max), entry.data.count <= Int(UInt32.max) else {
                throw ZipArchiveError.unsupportedArchive
            }
            let name = Data(entry.path.utf8)
            guard name.count <= Int(UInt16.max) else {
                throw ZipArchiveError.unsupportedArchive
            }
            let offset = UInt32(output.count)
            appendUInt32(0x04034b50, to: &output)
            appendUInt16(20, to: &output) // version needed
            appendUInt16(0, to: &output) // flags
            appendUInt16(0, to: &output) // store
            appendUInt16(0, to: &output) // time
            appendUInt16(0, to: &output) // date
            appendUInt32(crc32(entry.data), to: &output)
            appendUInt32(UInt32(entry.data.count), to: &output)
            appendUInt32(UInt32(entry.data.count), to: &output)
            appendUInt16(UInt16(name.count), to: &output)
            appendUInt16(0, to: &output)
            output.append(name)
            output.append(entry.data)

            appendUInt32(0x02014b50, to: &centralDirectory)
            appendUInt16(20, to: &centralDirectory) // made by
            appendUInt16(20, to: &centralDirectory) // version needed
            appendUInt16(0, to: &centralDirectory)
            appendUInt16(0, to: &centralDirectory)
            appendUInt16(0, to: &centralDirectory)
            appendUInt16(0, to: &centralDirectory)
            appendUInt32(crc32(entry.data), to: &centralDirectory)
            appendUInt32(UInt32(entry.data.count), to: &centralDirectory)
            appendUInt32(UInt32(entry.data.count), to: &centralDirectory)
            appendUInt16(UInt16(name.count), to: &centralDirectory)
            appendUInt16(0, to: &centralDirectory) // extra
            appendUInt16(0, to: &centralDirectory) // comment
            appendUInt16(0, to: &centralDirectory) // disk
            appendUInt16(0, to: &centralDirectory) // internal attributes
            appendUInt32(0, to: &centralDirectory) // external attributes
            appendUInt32(offset, to: &centralDirectory)
            centralDirectory.append(name)
        }

        guard output.count <= Int(UInt32.max), centralDirectory.count <= Int(UInt32.max),
              seen.count <= Int(UInt16.max) else {
            throw ZipArchiveError.unsupportedArchive
        }
        let directoryOffset = UInt32(output.count)
        output.append(centralDirectory)
        appendUInt32(0x06054b50, to: &output)
        appendUInt16(0, to: &output)
        appendUInt16(0, to: &output)
        appendUInt16(UInt16(seen.count), to: &output)
        appendUInt16(UInt16(seen.count), to: &output)
        appendUInt32(UInt32(centralDirectory.count), to: &output)
        appendUInt32(directoryOffset, to: &output)
        appendUInt16(0, to: &output)
        return output
    }

    static func decode(_ data: Data) throws -> [Entry] {
        guard data.count >= 22 else { throw ZipArchiveError.invalidArchive }
        let minimumOffset = max(0, data.count - 65_557)
        let endOffset = data.count - 22
        var eocdOffset: Int?
        for offset in stride(from: endOffset, through: minimumOffset, by: -1) {
            if readUInt32(data, at: offset) == 0x06054b50 {
                eocdOffset = offset
                break
            }
        }
        guard let eocdOffset else { throw ZipArchiveError.invalidArchive }
        let disk = readUInt16(data, at: eocdOffset + 4)
        let directoryDisk = readUInt16(data, at: eocdOffset + 6)
        let entryCount = Int(readUInt16(data, at: eocdOffset + 10))
        let directorySize = Int(readUInt32(data, at: eocdOffset + 12))
        let directoryOffset = Int(readUInt32(data, at: eocdOffset + 16))
        guard disk == 0, directoryDisk == 0, entryCount == Int(readUInt16(data, at: eocdOffset + 8)),
               directoryOffset >= 0, directorySize >= 0,
               directoryOffset + directorySize <= eocdOffset else {
            throw ZipArchiveError.unsupportedArchive
        }

        var entries: [Entry] = []
        var cursor = directoryOffset
        let directoryEnd = directoryOffset + directorySize
        var seen = Set<String>()
        for _ in 0..<entryCount {
            guard cursor + 46 <= directoryEnd, readUInt32(data, at: cursor) == 0x02014b50 else {
                throw ZipArchiveError.invalidArchive
            }
            let flags = readUInt16(data, at: cursor + 8)
            let method = readUInt16(data, at: cursor + 10)
            let expectedCRC = readUInt32(data, at: cursor + 16)
            let compressedSize = Int(readUInt32(data, at: cursor + 20))
            let uncompressedSize = Int(readUInt32(data, at: cursor + 24))
            let nameLength = Int(readUInt16(data, at: cursor + 28))
            let extraLength = Int(readUInt16(data, at: cursor + 30))
            let commentLength = Int(readUInt16(data, at: cursor + 32))
            let localOffset = Int(readUInt32(data, at: cursor + 42))
            let nameStart = cursor + 46
            guard nameStart + nameLength + extraLength + commentLength <= directoryEnd else {
                throw ZipArchiveError.invalidArchive
            }
            let nameData = data.subdata(in: nameStart..<(nameStart + nameLength))
            guard let path = String(data: nameData, encoding: .utf8), isSafePath(path),
                  seen.insert(path).inserted else {
                throw ZipArchiveError.unsafePath
            }
            cursor = nameStart + nameLength + extraLength + commentLength
            if path.hasSuffix("/") { continue }
            guard flags & 0x0001 == 0,
                  localOffset + 30 <= data.count,
                  readUInt32(data, at: localOffset) == 0x04034b50 else {
                throw ZipArchiveError.invalidArchive
            }
            let localNameLength = Int(readUInt16(data, at: localOffset + 26))
            let localExtraLength = Int(readUInt16(data, at: localOffset + 28))
            let payloadStart = localOffset + 30 + localNameLength + localExtraLength
            guard compressedSize >= 0, payloadStart >= 0,
                  payloadStart + compressedSize <= directoryOffset else {
                throw ZipArchiveError.invalidArchive
            }
            let compressed = data.subdata(in: payloadStart..<(payloadStart + compressedSize))
            let content: Data
            switch method {
            case 0:
                content = compressed
            case 8:
                content = try inflateRaw(compressed, expectedSize: uncompressedSize)
            default:
                throw ZipArchiveError.unsupportedArchive
            }
            guard content.count == uncompressedSize, crc32(content) == expectedCRC else {
                throw ZipArchiveError.checksumMismatch
            }
            entries.append(try Entry(path: path, data: content))
        }
        return entries
    }

    static func isSafePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.contains("\\"), !path.hasPrefix("/") else { return false }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        return !components.isEmpty && components.allSatisfy { !$0.isEmpty && $0 != ".." && $0 != "." }
    }

    private static func inflateRaw(_ data: Data, expectedSize: Int) throws -> Data {
        guard expectedSize >= 0 else { throw ZipArchiveError.invalidArchive }

        // Apple's COMPRESSION_ZLIB decoder accepts the raw DEFLATE stream used by
        // ZIP entries (RFC 1951); ZIP does not store a zlib header or Adler-32
        // trailer around each entry.
        var output = Data(repeating: 0, count: max(expectedSize, 1))
        let outputCount = output.count
        let decoded: Int? = output.withUnsafeMutableBytes { destination in
            guard let destinationBase = destination.bindMemory(to: UInt8.self).baseAddress else {
                return nil
            }
            return data.withUnsafeBytes { source in
                guard let sourceBase = source.bindMemory(to: UInt8.self).baseAddress else {
                    return nil
                }
                return Int(compression_decode_buffer(
                    destinationBase,
                    outputCount,
                    sourceBase,
                    data.count,
                    nil,
                    COMPRESSION_ZLIB
                ))
            }
        }
        guard decoded == expectedSize else { throw ZipArchiveError.invalidArchive }
        if expectedSize == 0 { return Data() }
        output.removeLast(output.count - expectedSize)
        return output
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffffffff
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc & 1) == 1 ? (crc >> 1) ^ 0xedb88320 : crc >> 1
            }
        }
        return crc ^ 0xffffffff
    }

    private static func readUInt16(_ data: Data, at offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset]) |
            (UInt32(data[offset + 1]) << 8) |
            (UInt32(data[offset + 2]) << 16) |
            (UInt32(data[offset + 3]) << 24)
    }

    private static func appendUInt16(_ value: UInt16, to data: inout Data) {
        data.append(UInt8(value & 0xff))
        data.append(UInt8((value >> 8) & 0xff))
    }

    private static func appendUInt32(_ value: UInt32, to data: inout Data) {
        data.append(UInt8(value & 0xff))
        data.append(UInt8((value >> 8) & 0xff))
        data.append(UInt8((value >> 16) & 0xff))
        data.append(UInt8((value >> 24) & 0xff))
    }
}
