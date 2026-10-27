import CryptoKit
import Darwin
import Foundation

struct FlashProgress: Sendable {
    enum Phase: Sendable { case writing, verifying }

    let phase: Phase
    /// Image bytes written (or verified) so far.
    let bytesDone: Int64
    /// 0...1. While writing an image of unknown decompressed size, this is how
    /// much of the compressed file has been consumed.
    let fraction: Double
}

enum FlashOutcome: Sendable, Equatable {
    case verified
    /// Completely written, but the read-back check was skipped.
    case unverified
}

enum ImageWriterError: LocalizedError {
    case emptyImage
    case imageTooLarge(image: Int64?, device: Int64)
    case readFailed(String)
    case writeFailed(offset: Int64, String)
    case verificationFailed

    var errorDescription: String? {
        let format = { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
        switch self {
        case .emptyImage:
            return "The image is empty."
        case let .imageTooLarge(image?, device):
            return "The image (\(format(image))) is larger than the drive (\(format(device)))."
        case let .imageTooLarge(nil, device):
            return "The decompressed image is larger than the drive (\(format(device)))."
        case .readFailed(let reason):
            return "Reading failed: \(reason)"
        case let .writeFailed(offset, reason):
            return "Writing to the drive failed at byte \(offset): \(reason)"
        case .verificationFailed:
            return "Verification failed: the data on the drive does not match the image. The drive may be faulty."
        }
    }
}

/// Copies an image byte-for-byte onto an already opened device descriptor (like
/// `dd`), decompressing on the fly, then reads it back to verify. A raw copy
/// preserves the image's partition table and boot sectors, which is what makes
/// the drive bootable.
///
/// Runs synchronously; call it from a background task. Cancelling the task while
/// writing throws `CancellationError`. Cancelling during verification only skips
/// the rest of it, since the image is already completely on the drive, and
/// returns `.unverified`.
enum ImageWriter {
    static let chunkSize = 4 * 1024 * 1024

    // <sys/disk.h> ioctls (function-like macros aren't imported into Swift).
    private static let DKIOCGETBLOCKSIZE: UInt = 0x4004_6418 // _IOR('d', 24, uint32_t)
    private static let DKIOCGETBLOCKCOUNT: UInt = 0x4008_6419 // _IOR('d', 25, uint64_t)
    private static let DKIOCSYNCHRONIZECACHE: UInt = 0x2000_6416 // _IO('d', 22)

    @discardableResult
    static func flash(
        image: URL,
        to device: Int32,
        verify: Bool = true,
        progress: (FlashProgress) -> Void
    ) throws -> FlashOutcome {
        let source = try ImageSources.open(image)
        let expectedSize = source.info.imageSize

        // Raw devices only accept I/O in whole blocks. Regular files (used in tests) report nothing.
        var blockSize: UInt32 = 512
        if ioctl(device, DKIOCGETBLOCKSIZE, &blockSize) != 0 || blockSize == 0 { blockSize = 512 }
        var blockCount: UInt64 = 0
        var deviceSize: Int64?
        if ioctl(device, DKIOCGETBLOCKCOUNT, &blockCount) == 0, blockCount > 0 {
            deviceSize = Int64(blockCount) * Int64(blockSize)
        }
        if let deviceSize, let expectedSize, expectedSize > deviceSize {
            throw ImageWriterError.imageTooLarge(image: expectedSize, device: deviceSize)
        }

        let buffer = UnsafeMutableRawPointer.allocate(byteCount: chunkSize, alignment: Int(getpagesize()))
        defer { buffer.deallocate() }

        // --- Write ---
        var hasher = SHA256()
        var written: Int64 = 0
        progress(FlashProgress(phase: .writing, bytesDone: 0, fraction: 0))
        while true {
            let length = try fill(buffer, count: chunkSize, from: source)
            guard length > 0 else { break }
            // Checked after reading so a cancel that lands once everything is written doesn't count as partial.
            try Task.checkCancellation()
            hasher.update(bufferPointer: UnsafeRawBufferPointer(start: buffer, count: length))

            // Pad the final partial block with zeros.
            let padded = roundUp(length, to: Int(blockSize))
            if padded > length { (buffer + length).initializeMemory(as: UInt8.self, repeating: 0, count: padded - length) }
            if let deviceSize, written + Int64(padded) > deviceSize {
                throw ImageWriterError.imageTooLarge(image: expectedSize, device: deviceSize)
            }

            try writeFully(device, from: buffer, count: padded, at: written)
            written += Int64(length)
            let fraction = expectedSize.map { Double(written) / Double(max($0, 1)) } ?? source.inputFraction
            progress(FlashProgress(phase: .writing, bytesDone: written, fraction: min(fraction, 1)))
            if length < chunkSize { break }
        }
        guard written > 0 else { throw ImageWriterError.emptyImage }
        if let expectedSize, written != expectedSize {
            throw ImageSourceError.corrupt("expected \(expectedSize) bytes after decompression but got \(written).")
        }
        progress(FlashProgress(phase: .writing, bytesDone: written, fraction: 1))
        _ = ioctl(device, DKIOCSYNCHRONIZECACHE)
        fsync(device)

        guard verify else { return .unverified }

        // --- Verify: read the drive back and compare checksums ---
        var verifier = SHA256()
        var verified: Int64 = 0
        progress(FlashProgress(phase: .verifying, bytesDone: 0, fraction: 0))
        while verified < written {
            if Task.isCancelled { return .unverified }
            let length = min(chunkSize, Int(written - verified))
            try readFully(device, into: buffer, count: roundUp(length, to: Int(blockSize)), at: verified)
            verifier.update(bufferPointer: UnsafeRawBufferPointer(start: buffer, count: length))
            verified += Int64(length)
            progress(FlashProgress(phase: .verifying, bytesDone: verified, fraction: Double(verified) / Double(written)))
        }
        guard verifier.finalize() == hasher.finalize() else { throw ImageWriterError.verificationFailed }
        return .verified
    }

    /// Decoders may return short reads; only the very last chunk may be partial,
    /// otherwise later writes would land at offsets that aren't block aligned.
    private static func fill(_ buffer: UnsafeMutableRawPointer, count: Int, from source: any ImageSource) throws -> Int {
        var done = 0
        while done < count {
            let n = try source.read(into: buffer + done, count: count - done)
            if n == 0 { break }
            done += n
        }
        return done
    }

    private static func readFully(_ fd: Int32, into buffer: UnsafeMutableRawPointer, count: Int, at offset: Int64) throws {
        var done = 0
        while done < count {
            let n = pread(fd, buffer + done, count - done, off_t(offset) + off_t(done))
            if n < 0 {
                if errno == EINTR { continue }
                throw ImageWriterError.readFailed(errnoString())
            }
            if n == 0 { throw ImageWriterError.readFailed("unexpected end of device") }
            done += n
        }
    }

    private static func writeFully(_ fd: Int32, from buffer: UnsafeMutableRawPointer, count: Int, at offset: Int64) throws {
        var done = 0
        while done < count {
            let n = pwrite(fd, buffer + done, count - done, off_t(offset) + off_t(done))
            if n < 0 {
                if errno == EINTR { continue }
                throw ImageWriterError.writeFailed(offset: offset + Int64(done), errnoString())
            }
            done += n
        }
    }

    private static func roundUp(_ value: Int, to multiple: Int) -> Int {
        (value + multiple - 1) / multiple * multiple
    }

    private static func errnoString() -> String { String(cString: strerror(errno)) }
}
