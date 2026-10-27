import DiskArbitration
import XCTest
@testable import Kagami

/// Exercises the real write/verify path for raw images against a RAM disk.
final class ImageWriterTests: RamDiskTestCase {
    func testWritesImageByteForByteAndVerifies() throws {
        // Deliberately not a multiple of the block size or the chunk size.
        let image = try makeImage(size: 5 * 1024 * 1024 + 123)
        let device = try openRamDisk()
        defer { close(device) }

        var phases: [FlashProgress.Phase] = []
        var last: FlashProgress?
        try ImageWriter.flash(image: image, to: device) { progress in
            if phases.last != progress.phase { phases.append(progress.phase) }
            last = progress
        }

        XCTAssertEqual(phases, [.writing, .verifying])
        XCTAssertEqual(last?.fraction, 1)

        let expected = try Data(contentsOf: image)
        let written = try readDevice(count: expected.count + 512)
        XCTAssertEqual(written.prefix(expected.count), expected)
        // The tail of the last block is zero padded.
        XCTAssertTrue(written[expected.count..<(expected.count + 512 - 123)].allSatisfy { $0 == 0 })
    }

    func testRejectsImageLargerThanDevice() throws {
        let image = try makeImage(size: 17 * 1024 * 1024)
        let device = try openRamDisk()
        defer { close(device) }

        XCTAssertThrowsError(try ImageWriter.flash(image: image, to: device) { _ in }) { error in
            guard case ImageWriterError.imageTooLarge = error else { return XCTFail("unexpected \(error)") }
        }
    }

    func testStopsWhenCancelled() async throws {
        let image = try makeImage(size: 8 * 1024 * 1024)
        let device = try openRamDisk()
        defer { close(device) }

        let task = Task {
            while !Task.isCancelled { await Task.yield() }
            try ImageWriter.flash(image: image, to: device) { _ in }
        }
        task.cancel()
        do {
            try await task.value
            XCTFail("expected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }

    /// "Skip Verification" cancels the task once verifying has started: the writer
    /// stops reading back but the drive already holds the complete image.
    func testCancellingDuringVerificationSkipsIt() async throws {
        let size = 3 * ImageWriter.chunkSize + 77
        let image = try makeImage(size: size)
        let device = try openRamDisk()
        defer { close(device) }

        let task = Task { () throws -> (FlashOutcome, Int64) in
            var verifiedBytes: Int64 = 0
            let outcome = try ImageWriter.flash(image: image, to: device) { progress in
                guard progress.phase == .verifying else { return }
                verifiedBytes = progress.bytesDone
                withUnsafeCurrentTask { $0?.cancel() }
            }
            return (outcome, verifiedBytes)
        }
        let (outcome, verifiedBytes) = try await task.value

        XCTAssertEqual(outcome, .unverified)
        XCTAssertLessThan(verifiedBytes, Int64(size), "verification should have stopped early")
        XCTAssertEqual(try readDevice(count: size).prefix(size), try Data(contentsOf: image))
    }

    func testCancellingDuringWritingStillAborts() async throws {
        let image = try makeImage(size: 3 * ImageWriter.chunkSize)
        let device = try openRamDisk()
        defer { close(device) }

        let task = Task {
            try ImageWriter.flash(image: image, to: device) { progress in
                if progress.phase == .writing, progress.bytesDone > 0 { withUnsafeCurrentTask { $0?.cancel() } }
            }
        }
        do {
            _ = try await task.value
            XCTFail("expected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }

    func testCompleteFlashReportsVerified() throws {
        let image = try makeImage(size: 1024 * 1024)
        let device = try openRamDisk()
        defer { close(device) }
        XCTAssertEqual(try ImageWriter.flash(image: image, to: device) { _ in }, .verified)
    }

    /// The RAM disk belongs to the current user, so authopen hands the descriptor
    /// back without a prompt. This covers the fd-passing path used for real drives.
    func testAuthOpenPassesBackWritableDescriptor() throws {
        let image = try makeImage(size: 1024 * 1024)
        let device = try AuthOpen.open(rawDevicePath)
        defer { close(device) }

        try ImageWriter.flash(image: image, to: device) { _ in }
        XCTAssertEqual(try readDevice(count: 1024 * 1024), try Data(contentsOf: image))
    }

    func testDriveFilterExcludesVirtualAndInternalDisks() throws {
        let session = try XCTUnwrap(DASessionCreate(kCFAllocatorDefault))
        let ram = try XCTUnwrap(DADiskCreateFromBSDName(kCFAllocatorDefault, session, ramDisk))
        XCTAssertNil(DriveMonitor.drive(for: ram), "disk images must never be offered")

        // The Mac's own startup SSD.
        let boot = try XCTUnwrap(DADiskCreateFromBSDName(kCFAllocatorDefault, session, "disk0"))
        XCTAssertNil(DriveMonitor.drive(for: boot), "the internal disk must never be offered")
    }
}
