import CBZip2
import Compression
import Darwin
import Foundation
import zlib

enum ImageFormat: String, Sendable {
    case raw, gzip, xz, bzip2, zip

    var displayName: String {
        switch self {
        case .raw: return "Raw image"
        case .gzip: return "gzip"
        case .xz: return "xz"
        case .bzip2: return "bzip2"
        case .zip: return "ZIP"
        }
    }
}

struct ImageInfo: Sendable {
    let format: ImageFormat
    /// Size of the file on disk.
    let fileSize: Int64
    /// Size of the image once decompressed, when known up front. gzip and bzip2
    /// don't record it reliably, so for those it's only known after writing.
    let imageSize: Int64?
    /// Name of the image inside a ZIP archive.
    let entryName: String?
}

enum ImageSourceError: LocalizedError {
    case unreadable(String)
    case unsupported(String)
    case corrupt(String)

    var errorDescription: String? {
        switch self {
        case .unreadable(let reason): return "Could not read the image: \(reason)"
        case .unsupported(let reason): return reason
        case .corrupt(let reason): return "The image is damaged: \(reason)"
        }
    }
}

/// A sequential stream of the image's raw bytes, decompressing on the fly when needed.
protocol ImageSource: AnyObject {
    var info: ImageInfo { get }
    /// How much of the file on disk has been consumed (0...1). Drives the progress
    /// bar when the decompressed size isn't known.
    var inputFraction: Double { get }
    /// Reads up to `count` bytes. Returns 0 once the image has been read completely.
    func read(into buffer: UnsafeMutableRawPointer, count: Int) throws -> Int
}

enum ImageSources {
    /// Detects the format from the file's magic bytes and opens a matching source.
    static func open(_ url: URL) throws -> any ImageSource {
        let file = try InputFile(url)
        let magic = try file.read(at: 0, count: 8)
        func starts(with bytes: [UInt8]) -> Bool { magic.starts(with: bytes) }

        if starts(with: [0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C]) {
            throw ImageSourceError.unsupported("7-Zip archives aren't supported. Extract the image first.")
        }
        if starts(with: [0x28, 0xB5, 0x2F, 0xFD]) {
            throw ImageSourceError.unsupported("Zstandard (.zst) images aren't supported. Extract the image first.")
        }

        let source: any ImageSource
        var innerName = url.deletingPathExtension().lastPathComponent
        if starts(with: [0x1F, 0x8B]) {
            let info = ImageInfo(format: .gzip, fileSize: file.size, imageSize: nil, entryName: nil)
            source = try InflateSource(file: file, info: info, windowBits: 15 + 16, multiMember: true)
        } else if starts(with: XzSource.magic) {
            let info = ImageInfo(format: .xz, fileSize: file.size, imageSize: XzIndex.uncompressedSize(of: file), entryName: nil)
            source = try XzSource(file: file, info: info)
        } else if starts(with: Array("BZh".utf8)) {
            let info = ImageInfo(format: .bzip2, fileSize: file.size, imageSize: nil, entryName: nil)
            source = try Bzip2Source(file: file, info: info)
        } else if starts(with: [0x50, 0x4B, 0x03, 0x04]) || starts(with: [0x50, 0x4B, 0x05, 0x06]) {
            let entry = try ZipArchive.imageEntry(in: file)
            innerName = entry.name
            source = try ZipArchive.open(entry, in: file)
        } else {
            innerName = url.lastPathComponent
            source = RawSource(file: file)
        }

        let lowered = innerName.lowercased()
        let tarExtensions = ["tgz", "tbz", "tbz2", "txz"]
        if lowered.hasSuffix(".tar") || tarExtensions.contains(url.pathExtension.lowercased()) {
            throw ImageSourceError.unsupported("tar archives aren't supported. Extract the image first.")
        }
        return source
    }

    /// Format and sizes, without decompressing anything.
    static func inspect(_ url: URL) throws -> ImageInfo {
        try open(url).info
    }
}

// MARK: - Input

/// Sequential reader over a file, or over a byte range of it (a ZIP entry).
final class InputFile {
    let size: Int64
    private let fd: Int32
    private var start: Int64 = 0
    private var end: Int64
    private(set) var position: Int64 = 0

    init(_ url: URL) throws {
        fd = Darwin.open(url.path, O_RDONLY)
        guard fd >= 0 else { throw ImageSourceError.unreadable(String(cString: strerror(errno))) }
        var info = stat()
        guard fstat(fd, &info) == 0 else {
            close(fd)
            throw ImageSourceError.unreadable(String(cString: strerror(errno)))
        }
        guard (info.st_mode & S_IFMT) == S_IFREG else {
            close(fd)
            throw ImageSourceError.unreadable("not a regular file")
        }
        size = Int64(info.st_size)
        end = size
        _ = fcntl(fd, F_RDAHEAD, 1)
    }

    deinit { close(fd) }

    func limit(to range: Range<Int64>) {
        start = range.lowerBound
        end = range.upperBound
        position = start
    }

    var fraction: Double { end > start ? Double(position - start) / Double(end - start) : 1 }

    /// Sequential read within the current range; returns 0 at its end.
    func read(into buffer: UnsafeMutableRawPointer, count: Int) throws -> Int {
        let wanted = Int(min(Int64(count), end - position))
        guard wanted > 0 else { return 0 }
        while true {
            let n = pread(fd, buffer, wanted, off_t(position))
            if n < 0 {
                if errno == EINTR { continue }
                throw ImageSourceError.unreadable(String(cString: strerror(errno)))
            }
            position += Int64(n)
            return n
        }
    }

    /// Random-access read for headers; may return fewer bytes near the end of the file.
    func read(at offset: Int64, count: Int) throws -> [UInt8] {
        guard offset >= 0, offset < size, count > 0 else { return [] }
        var bytes = [UInt8](repeating: 0, count: Int(min(Int64(count), size - offset)))
        var done = 0
        while done < bytes.count {
            let n = bytes.withUnsafeMutableBytes { pread(fd, $0.baseAddress! + done, $0.count - done, off_t(offset) + off_t(done)) }
            if n < 0 {
                if errno == EINTR { continue }
                throw ImageSourceError.unreadable(String(cString: strerror(errno)))
            }
            if n == 0 { break }
            done += n
        }
        return Array(bytes.prefix(done))
    }
}

/// Fixed buffer that decoders refill from an `InputFile` once they've consumed it.
private final class InputBuffer {
    static let capacity = 1 << 20
    let pointer = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
    deinit { pointer.deallocate() }

    func fill(from file: InputFile) throws -> Int {
        try file.read(into: pointer, count: Self.capacity)
    }
}

private let truncated = ImageSourceError.corrupt("the compressed file ends unexpectedly.")

// MARK: - Raw

final class RawSource: ImageSource {
    let info: ImageInfo
    private let file: InputFile

    init(file: InputFile, info: ImageInfo? = nil) {
        self.file = file
        self.info = info ?? ImageInfo(format: .raw, fileSize: file.size, imageSize: file.size, entryName: nil)
    }

    var inputFraction: Double { file.fraction }

    func read(into buffer: UnsafeMutableRawPointer, count: Int) throws -> Int {
        try file.read(into: buffer, count: count)
    }
}

// MARK: - gzip / deflate (zlib)

final class InflateSource: ImageSource {
    let info: ImageInfo
    private let file: InputFile
    private let input = InputBuffer()
    private var stream = z_stream()
    private let multiMember: Bool
    private var finished = false

    /// `windowBits`: 15 + 16 for gzip, -15 for the raw deflate data inside ZIP files.
    init(file: InputFile, info: ImageInfo, windowBits: Int32, multiMember: Bool) throws {
        self.file = file
        self.info = info
        self.multiMember = multiMember
        guard inflateInit2_(&stream, windowBits, zlibVersion(), Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            throw ImageSourceError.unreadable("could not initialize zlib")
        }
    }

    deinit { inflateEnd(&stream) }

    var inputFraction: Double { file.fraction }

    func read(into buffer: UnsafeMutableRawPointer, count: Int) throws -> Int {
        guard !finished, count > 0 else { return 0 }
        stream.next_out = buffer.assumingMemoryBound(to: Bytef.self)
        stream.avail_out = uInt(count)

        while stream.avail_out > 0 && !finished {
            if stream.avail_in == 0 {
                guard try refill() else { throw truncated }
            }
            switch inflate(&stream, Z_NO_FLUSH) {
            case Z_OK, Z_BUF_ERROR:
                continue
            case Z_STREAM_END:
                if try !startNextMember() { finished = true }
            default:
                throw ImageSourceError.corrupt(stream.msg.map { String(cString: $0) } ?? "invalid compressed data.")
            }
        }
        return count - Int(stream.avail_out)
    }

    private func refill() throws -> Bool {
        let n = try input.fill(from: file)
        stream.next_in = input.pointer
        stream.avail_in = uInt(n)
        return n > 0
    }

    /// Files made by `pigz` or `cat a.gz b.gz` contain several gzip members back to back.
    private func startNextMember() throws -> Bool {
        guard multiMember else { return false }
        if stream.avail_in == 0, try !refill() { return false }
        guard stream.avail_in >= 2, stream.next_in[0] == 0x1F, stream.next_in[1] == 0x8B else { return false }
        inflateReset(&stream)
        return true
    }
}

// MARK: - bzip2 (libbz2)

final class Bzip2Source: ImageSource {
    let info: ImageInfo
    private let file: InputFile
    private let input = InputBuffer()
    private var stream = bz_stream()
    private var finished = false

    init(file: InputFile, info: ImageInfo) throws {
        self.file = file
        self.info = info
        guard BZ2_bzDecompressInit(&stream, 0, 0) == BZ_OK else {
            throw ImageSourceError.unreadable("could not initialize bzip2")
        }
    }

    deinit { BZ2_bzDecompressEnd(&stream) }

    var inputFraction: Double { file.fraction }

    func read(into buffer: UnsafeMutableRawPointer, count: Int) throws -> Int {
        guard !finished, count > 0 else { return 0 }
        stream.next_out = buffer.assumingMemoryBound(to: CChar.self)
        stream.avail_out = UInt32(count)

        while stream.avail_out > 0 && !finished {
            if stream.avail_in == 0 {
                guard try refill() else { throw truncated }
            }
            switch BZ2_bzDecompress(&stream) {
            case BZ_OK:
                continue
            case BZ_STREAM_END:
                if try !startNextStream() { finished = true }
            default:
                throw ImageSourceError.corrupt("invalid bzip2 data.")
            }
        }
        return count - Int(stream.avail_out)
    }

    private func refill() throws -> Bool {
        let n = try input.fill(from: file)
        stream.next_in = UnsafeMutableRawPointer(input.pointer).assumingMemoryBound(to: CChar.self)
        stream.avail_in = UInt32(n)
        return n > 0
    }

    /// `pbzip2` writes one bzip2 stream per block, concatenated.
    private func startNextStream() throws -> Bool {
        if stream.avail_in == 0, try !refill() { return false }
        guard stream.avail_in >= 3,
              UInt8(bitPattern: stream.next_in[0]) == 0x42, // "BZh"
              UInt8(bitPattern: stream.next_in[1]) == 0x5A,
              UInt8(bitPattern: stream.next_in[2]) == 0x68
        else { return false }

        let (nextIn, availIn) = (stream.next_in, stream.avail_in)
        let (nextOut, availOut) = (stream.next_out, stream.avail_out)
        BZ2_bzDecompressEnd(&stream)
        stream = bz_stream()
        guard BZ2_bzDecompressInit(&stream, 0, 0) == BZ_OK else {
            throw ImageSourceError.unreadable("could not initialize bzip2")
        }
        (stream.next_in, stream.avail_in) = (nextIn, availIn)
        (stream.next_out, stream.avail_out) = (nextOut, availOut)
        return true
    }
}

// MARK: - xz (Compression framework)

final class XzSource: ImageSource {
    static let magic: [UInt8] = [0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00]

    let info: ImageInfo
    private let file: InputFile
    private let input = InputBuffer()
    private let stream = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
    private var inputEnded = false
    private var finished = false

    init(file: InputFile, info: ImageInfo) throws {
        self.file = file
        self.info = info
        guard compression_stream_init(stream, COMPRESSION_STREAM_DECODE, COMPRESSION_LZMA) == COMPRESSION_STATUS_OK else {
            stream.deallocate()
            throw ImageSourceError.unreadable("could not initialize the xz decoder")
        }
        stream.pointee.src_size = 0
    }

    deinit {
        compression_stream_destroy(stream)
        stream.deallocate()
    }

    var inputFraction: Double { file.fraction }

    func read(into buffer: UnsafeMutableRawPointer, count: Int) throws -> Int {
        guard !finished, count > 0 else { return 0 }
        stream.pointee.dst_ptr = buffer.assumingMemoryBound(to: UInt8.self)
        stream.pointee.dst_size = count

        while stream.pointee.dst_size > 0 && !finished {
            if stream.pointee.src_size == 0 && !inputEnded { try refill() }
            let before = (stream.pointee.src_size, stream.pointee.dst_size)
            let flags = inputEnded ? Int32(COMPRESSION_STREAM_FINALIZE.rawValue) : 0

            switch compression_stream_process(stream, flags) {
            case COMPRESSION_STATUS_OK:
                // Out of input with nothing produced: the file was cut short.
                if inputEnded && before == (stream.pointee.src_size, stream.pointee.dst_size) { throw truncated }
            case COMPRESSION_STATUS_END:
                if try !startNextStream() { finished = true }
            default:
                throw inputEnded && stream.pointee.src_size == 0 ? truncated : ImageSourceError.corrupt("invalid xz data.")
            }
        }
        return count - stream.pointee.dst_size
    }

    private func refill() throws {
        let n = try input.fill(from: file)
        stream.pointee.src_ptr = UnsafePointer(input.pointer)
        stream.pointee.src_size = n
        if n == 0 { inputEnded = true }
    }

    /// Concatenated .xz files hold several streams, optionally separated by zero padding.
    private func startNextStream() throws -> Bool {
        while true {
            if stream.pointee.src_size == 0 {
                guard !inputEnded else { return false }
                try refill()
                continue
            }
            guard stream.pointee.src_ptr.pointee == 0 else { break }
            stream.pointee.src_ptr += 1
            stream.pointee.src_size -= 1
        }
        let available = UnsafeBufferPointer(start: stream.pointee.src_ptr, count: min(6, stream.pointee.src_size))
        guard Array(available) == Self.magic else { return false }

        let (srcPtr, srcSize) = (stream.pointee.src_ptr, stream.pointee.src_size)
        let (dstPtr, dstSize) = (stream.pointee.dst_ptr, stream.pointee.dst_size)
        compression_stream_destroy(stream)
        guard compression_stream_init(stream, COMPRESSION_STREAM_DECODE, COMPRESSION_LZMA) == COMPRESSION_STATUS_OK else {
            throw ImageSourceError.unreadable("could not initialize the xz decoder")
        }
        (stream.pointee.src_ptr, stream.pointee.src_size) = (srcPtr, srcSize)
        (stream.pointee.dst_ptr, stream.pointee.dst_size) = (dstPtr, dstSize)
        return true
    }
}

/// Reads the decompressed size from the index at the end of each xz stream.
enum XzIndex {
    static func uncompressedSize(of file: InputFile) -> Int64? {
        var end = file.size
        var total: Int64 = 0
        while end > 0 {
            // Skip stream padding (zero bytes, multiples of four).
            while end >= 4, (try? file.read(at: end - 4, count: 4)) == [0, 0, 0, 0] { end -= 4 }
            guard end >= 24,
                  let footer = try? file.read(at: end - 12, count: 12), footer.count == 12,
                  footer[10] == 0x59, footer[11] == 0x5A // "YZ"
            else { return nil }

            let indexSize = (Int64(footer.le32(at: 4)) + 1) * 4
            let indexStart = end - 12 - indexSize
            guard indexStart >= 12, indexSize < 64 * 1024 * 1024,
                  let index = try? file.read(at: indexStart, count: Int(indexSize)), index.first == 0
            else { return nil }

            var cursor = 1
            guard let records = index.varint(at: &cursor) else { return nil }
            var blocksSize: Int64 = 0
            for _ in 0..<records {
                guard let unpadded = index.varint(at: &cursor), let uncompressed = index.varint(at: &cursor) else { return nil }
                blocksSize += (Int64(unpadded) + 3) & ~3
                total += Int64(uncompressed)
            }
            // Walk back over this stream: header + blocks + index + footer.
            end = indexStart - blocksSize - 12
            guard end >= 0 else { return nil }
        }
        return total
    }
}

// MARK: - ZIP

enum ZipArchive {
    struct Entry {
        let name: String
        let flags: UInt16
        let method: UInt16
        let crc: UInt32
        let compressedSize: Int64
        let uncompressedSize: Int64
        let localHeaderOffset: Int64
    }

    private static let imageExtensions: Set<String> = ["img", "iso", "raw", "bin", "dd", "hdd"]

    /// Picks the image inside the archive: the largest file with an image-like
    /// extension, otherwise the largest file. macOS metadata is ignored.
    static func imageEntry(in file: InputFile) throws -> Entry {
        let entries = try centralDirectory(of: file).filter {
            !$0.name.hasSuffix("/") && !$0.name.hasPrefix("__MACOSX/") && !$0.name.hasSuffix(".DS_Store")
        }
        let images = entries.filter { imageExtensions.contains(($0.name as NSString).pathExtension.lowercased()) }
        guard let entry = (images.isEmpty ? entries : images).max(by: { $0.uncompressedSize < $1.uncompressedSize }) else {
            throw ImageSourceError.unsupported("The ZIP archive doesn't contain any files.")
        }
        return entry
    }

    static func open(_ entry: Entry, in file: InputFile) throws -> any ImageSource {
        if entry.flags & 1 != 0 {
            throw ImageSourceError.unsupported("Encrypted ZIP archives aren't supported.")
        }
        let local = try file.read(at: entry.localHeaderOffset, count: 30)
        guard local.count == 30, local.le32(at: 0) == 0x0403_4B50 else {
            throw ImageSourceError.corrupt("invalid ZIP entry header.")
        }
        let dataStart = entry.localHeaderOffset + 30 + Int64(local.le16(at: 26)) + Int64(local.le16(at: 28))
        guard dataStart + entry.compressedSize <= file.size else { throw truncated }
        file.limit(to: dataStart..<(dataStart + entry.compressedSize))

        let info = ImageInfo(format: .zip, fileSize: file.size, imageSize: entry.uncompressedSize, entryName: entry.name)
        let source: any ImageSource
        switch entry.method {
        case 0: source = RawSource(file: file, info: info)
        case 8: source = try InflateSource(file: file, info: info, windowBits: -15, multiMember: false)
        default:
            throw ImageSourceError.unsupported("This ZIP archive uses a compression method that isn't supported (\(entry.method)).")
        }
        return CRCCheckedSource(source, expected: entry.crc)
    }

    private static func centralDirectory(of file: InputFile) throws -> [Entry] {
        // End of central directory record: 22 bytes plus an optional comment of up to 64 KiB.
        let tailStart = max(0, file.size - 22 - 65_535)
        let tail = try file.read(at: tailStart, count: Int(file.size - tailStart))
        guard let eocd = stride(from: tail.count - 22, through: 0, by: -1).first(where: { tail.le32(at: $0) == 0x0605_4B50 }) else {
            throw ImageSourceError.corrupt("the ZIP archive's directory is missing.")
        }
        var count = Int64(tail.le16(at: eocd + 10))
        var directorySize = Int64(tail.le32(at: eocd + 12))
        var directoryOffset = Int64(tail.le32(at: eocd + 16))

        // ZIP64: the real values live in a separate record, found via a locator just before the EOCD.
        if count == 0xFFFF || directorySize == 0xFFFF_FFFF || directoryOffset == 0xFFFF_FFFF {
            let locatorOffset = tailStart + Int64(eocd) - 20
            let locator = try file.read(at: locatorOffset, count: 20)
            guard locator.count == 20, locator.le32(at: 0) == 0x0706_4B50 else {
                throw ImageSourceError.corrupt("the ZIP64 directory locator is missing.")
            }
            let record = try file.read(at: Int64(locator.le64(at: 8)), count: 56)
            guard record.count == 56, record.le32(at: 0) == 0x0606_4B50 else {
                throw ImageSourceError.corrupt("the ZIP64 directory record is missing.")
            }
            count = Int64(record.le64(at: 32))
            directorySize = Int64(record.le64(at: 40))
            directoryOffset = Int64(record.le64(at: 48))
        }
        guard directorySize < 64 * 1024 * 1024 else { throw ImageSourceError.corrupt("the ZIP directory is too large.") }

        let directory = try file.read(at: directoryOffset, count: Int(directorySize))
        var entries: [Entry] = []
        var cursor = 0
        for _ in 0..<count {
            guard cursor + 46 <= directory.count, directory.le32(at: cursor) == 0x0201_4B50 else {
                throw ImageSourceError.corrupt("invalid ZIP directory entry.")
            }
            let nameLength = Int(directory.le16(at: cursor + 28))
            let extraLength = Int(directory.le16(at: cursor + 30))
            let commentLength = Int(directory.le16(at: cursor + 32))
            let nameStart = cursor + 46
            guard nameStart + nameLength + extraLength <= directory.count else {
                throw ImageSourceError.corrupt("invalid ZIP directory entry.")
            }
            let name = String(decoding: directory[nameStart..<(nameStart + nameLength)], as: UTF8.self)

            var compressed = Int64(directory.le32(at: cursor + 20))
            var uncompressed = Int64(directory.le32(at: cursor + 24))
            var offset = Int64(directory.le32(at: cursor + 42))

            // ZIP64 extra field: only the fields saturated at 0xFFFFFFFF are present, in this order.
            var extra = nameStart + nameLength
            let extraEnd = extra + extraLength
            while extra + 4 <= extraEnd {
                let id = directory.le16(at: extra)
                let size = Int(directory.le16(at: extra + 2))
                if id == 0x0001 {
                    var field = extra + 4
                    if uncompressed == 0xFFFF_FFFF, field + 8 <= extraEnd { uncompressed = Int64(directory.le64(at: field)); field += 8 }
                    if compressed == 0xFFFF_FFFF, field + 8 <= extraEnd { compressed = Int64(directory.le64(at: field)); field += 8 }
                    if offset == 0xFFFF_FFFF, field + 8 <= extraEnd { offset = Int64(directory.le64(at: field)) }
                }
                extra += 4 + size
            }

            entries.append(Entry(
                name: name,
                flags: directory.le16(at: cursor + 8),
                method: directory.le16(at: cursor + 10),
                crc: directory.le32(at: cursor + 16),
                compressedSize: compressed,
                uncompressedSize: uncompressed,
                localHeaderOffset: offset
            ))
            cursor = extraEnd + commentLength
        }
        return entries
    }
}

/// Checks a ZIP entry's CRC-32 once it has been read to the end.
private final class CRCCheckedSource: ImageSource {
    private let base: any ImageSource
    private let expected: UInt32
    private var crc = crc32(0, nil, 0)

    init(_ base: any ImageSource, expected: UInt32) {
        self.base = base
        self.expected = expected
    }

    var info: ImageInfo { base.info }
    var inputFraction: Double { base.inputFraction }

    func read(into buffer: UnsafeMutableRawPointer, count: Int) throws -> Int {
        let n = try base.read(into: buffer, count: count)
        if n > 0 {
            crc = crc32(crc, buffer.assumingMemoryBound(to: Bytef.self), uInt(n))
        } else if UInt32(truncatingIfNeeded: crc) != expected {
            throw ImageSourceError.corrupt("checksum mismatch in the ZIP archive.")
        }
        return n
    }
}

// MARK: - Little-endian helpers

private extension Array where Element == UInt8 {
    func le16(at i: Int) -> UInt16 { UInt16(self[i]) | UInt16(self[i + 1]) << 8 }
    func le32(at i: Int) -> UInt32 { (0..<4).reduce(0) { $0 | UInt32(self[i + $1]) << (8 * $1) } }
    func le64(at i: Int) -> UInt64 { (0..<8).reduce(0) { $0 | UInt64(self[i + $1]) << (8 * $1) } }

    /// xz multibyte integer: 7 bits per byte, least significant first.
    func varint(at cursor: inout Int) -> UInt64? {
        var value: UInt64 = 0
        for shift in stride(from: 0, to: 63, by: 7) {
            guard cursor < count else { return nil }
            let byte = self[cursor]
            cursor += 1
            value |= UInt64(byte & 0x7F) << UInt64(shift)
            if byte & 0x80 == 0 { return value }
        }
        return nil
    }
}
