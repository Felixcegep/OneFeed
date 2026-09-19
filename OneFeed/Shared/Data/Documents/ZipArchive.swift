import Foundation
import zlib

enum ZipArchiveError: Error, Equatable {
    case notAZip
    case corrupt
    case unsupported
    case unsafePath
}

/// Minimal ZIP reader for EPUB (store + deflate) and a store-only writer for tests.
nonisolated enum ZipArchive {
    static let maxComment = 65_535
    static let eocdMin = 22
    static let maxEntryBytes = 100 * 1_024 * 1_024

    static func extractAll(from url: URL, to directory: URL) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let size = try handle.seekToEnd()
        guard size >= eocdMin else { throw ZipArchiveError.notAZip }

        let tailLength = min(UInt64(maxComment + eocdMin), size)
        try handle.seek(toOffset: size - tailLength)
        let tail = try handle.read(upToCount: Int(tailLength)) ?? Data()
        guard let eocd = findEOCD(in: tail) else { throw ZipArchiveError.notAZip }
        if eocd.disk != 0 || eocd.cdDisk != 0 || eocd.cdOffset == 0xFFFF_FFFF {
            throw ZipArchiveError.unsupported
        }

        try handle.seek(toOffset: UInt64(eocd.cdOffset))
        var remaining = Int(eocd.cdSize)
        var entries: [CentralEntry] = []
        entries.reserveCapacity(Int(eocd.entries))
        while remaining > 0 {
            let header = try handle.read(upToCount: 46) ?? Data()
            guard header.count == 46, u32(header, 0) == 0x0201_4b50 else { throw ZipArchiveError.corrupt }
            let nameLen = Int(u16(header, 28))
            let extraLen = Int(u16(header, 30))
            let commentLen = Int(u16(header, 32))
            let nameData = try handle.read(upToCount: nameLen) ?? Data()
            _ = try handle.read(upToCount: extraLen + commentLen)
            remaining -= 46 + nameLen + extraLen + commentLen
            entries.append(
                CentralEntry(
                    flags: u16(header, 8),
                    method: u16(header, 10),
                    compressed: Int(u32(header, 20)),
                    uncompressed: Int(u32(header, 24)),
                    localOffset: u32(header, 42),
                    name: decodeName(nameData, flags: u16(header, 8))
                )
            )
        }

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let root = directory.standardizedFileURL

        for entry in entries {
            if entry.name.hasSuffix("/") { continue }
            guard isSafePath(entry.name) else { throw ZipArchiveError.unsafePath }
            if entry.flags & 1 != 0 { throw ZipArchiveError.unsupported }
            if entry.uncompressed > maxEntryBytes || entry.compressed > maxEntryBytes {
                throw ZipArchiveError.unsupported
            }

            try handle.seek(toOffset: UInt64(entry.localOffset))
            let local = try handle.read(upToCount: 30) ?? Data()
            guard local.count == 30, u32(local, 0) == 0x0403_4b50 else { throw ZipArchiveError.corrupt }
            let localName = Int(u16(local, 26))
            let localExtra = Int(u16(local, 28))
            _ = try handle.read(upToCount: localName + localExtra)
            let compressed = try handle.read(upToCount: entry.compressed) ?? Data()
            guard compressed.count == entry.compressed else { throw ZipArchiveError.corrupt }

            let raw: Data
            switch entry.method {
            case 0:
                raw = compressed
            case 8:
                raw = try inflateRaw(compressed, uncompressedSize: entry.uncompressed)
            default:
                throw ZipArchiveError.unsupported
            }

            let dest = root.appending(path: entry.name).standardizedFileURL
            guard dest.path.hasPrefix(root.path) else { throw ZipArchiveError.unsafePath }
            try fileManager.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            try raw.write(to: dest, options: .atomic)
        }
    }

    static func storedArchive(entries: [(name: String, data: Data)]) -> Data {
        var locals = Data()
        var central = Data()
        for entry in entries {
            let name = Data(entry.name.utf8)
            let crc = checksumCRC32(entry.data)
            let size = UInt32(entry.data.count)
            let localOffset = UInt32(locals.count)

            locals.appendUInt32(0x0403_4b50)
            locals.appendUInt16(20)
            locals.appendUInt16(0)
            locals.appendUInt16(0)
            locals.appendUInt16(0)
            locals.appendUInt16(0)
            locals.appendUInt32(crc)
            locals.appendUInt32(size)
            locals.appendUInt32(size)
            locals.appendUInt16(UInt16(name.count))
            locals.appendUInt16(0)
            locals.append(name)
            locals.append(entry.data)

            central.appendUInt32(0x0201_4b50)
            central.appendUInt16(20)
            central.appendUInt16(20)
            central.appendUInt16(0)
            central.appendUInt16(0)
            central.appendUInt16(0)
            central.appendUInt16(0)
            central.appendUInt32(crc)
            central.appendUInt32(size)
            central.appendUInt32(size)
            central.appendUInt16(UInt16(name.count))
            central.appendUInt16(0)
            central.appendUInt16(0)
            central.appendUInt16(0)
            central.appendUInt16(0)
            central.appendUInt32(0)
            central.appendUInt32(localOffset)
            central.append(name)
        }

        var archive = Data()
        archive.append(locals)
        let cdOffset = UInt32(archive.count)
        archive.append(central)
        archive.appendUInt32(0x0605_4b50)
        archive.appendUInt16(0)
        archive.appendUInt16(0)
        archive.appendUInt16(UInt16(entries.count))
        archive.appendUInt16(UInt16(entries.count))
        archive.appendUInt32(UInt32(central.count))
        archive.appendUInt32(cdOffset)
        archive.appendUInt16(0)
        return archive
    }

    private struct EOCD {
        var disk: UInt16
        var cdDisk: UInt16
        var entries: UInt16
        var cdSize: UInt32
        var cdOffset: UInt32
    }

    private struct CentralEntry {
        var flags: UInt16
        var method: UInt16
        var compressed: Int
        var uncompressed: Int
        var localOffset: UInt32
        var name: String
    }

    private static func findEOCD(in tail: Data) -> EOCD? {
        guard tail.count >= eocdMin else { return nil }
        let last = tail.count - eocdMin
        var index = last
        while index >= 0 {
            if u32(tail, index) == 0x0605_4b50 {
                let comment = Int(u16(tail, index + 20))
                if index + eocdMin + comment == tail.count {
                    return EOCD(
                        disk: u16(tail, index + 4),
                        cdDisk: u16(tail, index + 6),
                        entries: u16(tail, index + 10),
                        cdSize: u32(tail, index + 12),
                        cdOffset: u32(tail, index + 16)
                    )
                }
            }
            if index == 0 { break }
            index -= 1
        }
        return nil
    }

    private static func decodeName(_ data: Data, flags: UInt16) -> String {
        if flags & 0x800 != 0, let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }
        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
    }

    private static func isSafePath(_ name: String) -> Bool {
        guard !name.isEmpty, !name.hasPrefix("/") else { return false }
        return !name.split(separator: "/").contains("..")
    }

    private static func inflateRaw(_ input: Data, uncompressedSize: Int) throws -> Data {
        if uncompressedSize == 0 { return Data() }
        var stream = z_stream()
        var output = Data(count: uncompressedSize)
        let status: Int32 = input.withUnsafeBytes { srcBuffer in
            output.withUnsafeMutableBytes { dstBuffer in
                guard let src = srcBuffer.bindMemory(to: Bytef.self).baseAddress,
                      let dst = dstBuffer.bindMemory(to: Bytef.self).baseAddress else {
                    return Z_ERRNO
                }
                stream.next_in = UnsafeMutablePointer(mutating: src)
                stream.avail_in = uInt(input.count)
                stream.next_out = dst
                stream.avail_out = uInt(uncompressedSize)
                let opened = inflateInit2_(
                    &stream,
                    -MAX_WBITS,
                    ZLIB_VERSION,
                    Int32(MemoryLayout<z_stream>.size)
                )
                guard opened == Z_OK else { return opened }
                let result = inflate(&stream, Z_FINISH)
                inflateEnd(&stream)
                return result
            }
        }
        guard status == Z_STREAM_END || status == Z_OK else { throw ZipArchiveError.corrupt }
        return output
    }

    private static func checksumCRC32(_ data: Data) -> UInt32 {
        data.withUnsafeBytes { buffer in
            let bytes = buffer.bindMemory(to: UInt8.self)
            guard let pointer = bytes.baseAddress else { return 0 }
            return UInt32(truncatingIfNeeded: zlib.crc32(0, pointer, uInt(bytes.count)))
        }
    }

    private static func u16(_ data: Data, _ offset: Int) -> UInt16 {
        UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
    }

    private static func u32(_ data: Data, _ offset: Int) -> UInt32 {
        UInt32(data[offset])
            | UInt32(data[offset + 1]) << 8
            | UInt32(data[offset + 2]) << 16
            | UInt32(data[offset + 3]) << 24
    }
}

private extension Data {
    mutating func appendUInt16(_ value: UInt16) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }

    mutating func appendUInt32(_ value: UInt32) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }
}
