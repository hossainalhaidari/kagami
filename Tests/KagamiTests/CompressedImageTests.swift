import XCTest
@testable import Kagami

/// Flashes compressed images onto a RAM disk and checks the drive ends up with
/// exactly the decompressed bytes. Fixtures are made with the stock macOS
/// `gzip`, `bzip2` and `zip` tools; xz uses the Compression framework, plus the
/// `xz` CLI for multi-block files when it's installed.
final class CompressedImageTests: RamDiskTestCase {
    private let size = 5 * 1024 * 1024 + 321

    // MARK: gzip

    func testGzip() throws {
        let original = try makeImage(size: size)
        try sh("gzip -c test.img > test.img.gz")
        let image = tempDir.appendingPathComponent("test.img.gz")

        let info = try ImageSources.inspect(image)
        XCTAssertEqual(info.format, .gzip)
        XCTAssertNil(info.imageSize)
        try assertFlashes(image, producing: Data(contentsOf: original))
    }

    func testGzipWithMultipleMembers() throws {
        let original = try makeImage(size: size)
        try sh("head -c 3000000 test.img | gzip > a.gz && tail -c +3000001 test.img | gzip > b.gz && cat a.gz b.gz > test.img.gz")
        try assertFlashes(tempDir.appendingPathComponent("test.img.gz"), producing: Data(contentsOf: original))
    }

    func testCorruptGzipFails() throws {
        _ = try makeImage(size: size)
        try sh("gzip -c test.img > test.img.gz")
        let image = tempDir.appendingPathComponent("test.img.gz")
        var data = try Data(contentsOf: image)
        data[data.count / 2] ^= 0xFF
        try data.write(to: image)

        let device = try openRamDisk()
        defer { close(device) }
        XCTAssertThrowsError(try ImageWriter.flash(image: image, to: device) { _ in }) { error in
            guard case ImageSourceError.corrupt = error else { return XCTFail("unexpected \(error)") }
        }
    }

    func testImageOfUnknownSizeLargerThanDeviceFails() throws {
        _ = try makeImage(size: Self.ramDiskSize + 1024 * 1024)
        try sh("gzip -c test.img > test.img.gz")

        let device = try openRamDisk()
        defer { close(device) }
        XCTAssertThrowsError(try ImageWriter.flash(image: tempDir.appendingPathComponent("test.img.gz"), to: device) { _ in }) { error in
            guard case ImageWriterError.imageTooLarge(nil, _) = error else { return XCTFail("unexpected \(error)") }
        }
    }

    // MARK: bzip2

    func testBzip2() throws {
        let original = try makeImage(size: size)
        try sh("bzip2 -c test.img > test.img.bz2")
        let image = tempDir.appendingPathComponent("test.img.bz2")
        XCTAssertEqual(try ImageSources.inspect(image).format, .bzip2)
        try assertFlashes(image, producing: Data(contentsOf: original))
    }

    func testBzip2WithMultipleStreams() throws {
        let original = try makeImage(size: size)
        try sh("head -c 3000000 test.img | bzip2 > a.bz2 && tail -c +3000001 test.img | bzip2 > b.bz2 && cat a.bz2 b.bz2 > test.img.bz2")
        try assertFlashes(tempDir.appendingPathComponent("test.img.bz2"), producing: Data(contentsOf: original))
    }

    // MARK: xz

    func testXz() throws {
        let original = makeImageData(size: size)
        let image = tempDir.appendingPathComponent("test.img.xz")
        try (original as NSData).compressed(using: .lzma).write(to: image)

        let info = try ImageSources.inspect(image)
        XCTAssertEqual(info.format, .xz)
        XCTAssertEqual(info.imageSize, Int64(size), "size comes from the xz index")
        try assertFlashes(image, producing: original)
    }

    /// Raspberry Pi OS images are made with multi-threaded xz, which splits the data into blocks.
    func testXzMultiBlockAndConcatenatedStreams() throws {
        let xz = try xzTool()
        let original = try makeImage(size: size)
        try sh("""
            head -c 3000000 test.img | \(xz) -T2 --block-size=1MiB > a.xz && \
            tail -c +3000001 test.img | \(xz) -C sha256 > b.xz && \
            cat a.xz > test.img.xz && printf '\\0\\0\\0\\0' >> test.img.xz && cat b.xz >> test.img.xz
            """)
        let image = tempDir.appendingPathComponent("test.img.xz")
        XCTAssertEqual(try ImageSources.inspect(image).imageSize, Int64(size))
        try assertFlashes(image, producing: Data(contentsOf: original))
    }

    func testTruncatedXzFails() throws {
        let image = tempDir.appendingPathComponent("test.img.xz")
        let compressed = try (makeImageData(size: size) as NSData).compressed(using: .lzma) as Data
        try compressed.prefix(compressed.count / 2).write(to: image)

        let device = try openRamDisk()
        defer { close(device) }
        XCTAssertThrowsError(try ImageWriter.flash(image: image, to: device) { _ in })
    }

    // MARK: ZIP

    func testZipPicksImageAndIgnoresOtherFiles() throws {
        let original = try makeImage(size: size, name: "disk.img")
        try sh("mkdir __MACOSX && echo junk > __MACOSX/._disk.img && echo hello > README.txt && zip -q -r test.zip README.txt disk.img __MACOSX")
        let image = tempDir.appendingPathComponent("test.zip")

        let info = try ImageSources.inspect(image)
        XCTAssertEqual(info.format, .zip)
        XCTAssertEqual(info.entryName, "disk.img")
        XCTAssertEqual(info.imageSize, Int64(size))
        try assertFlashes(image, producing: Data(contentsOf: original))
    }

    func testZipStored() throws {
        let original = try makeImage(size: size)
        try sh("zip -q -0 test.zip test.img")
        try assertFlashes(tempDir.appendingPathComponent("test.zip"), producing: Data(contentsOf: original))
    }

    func testZip64() throws {
        let original = try makeImage(size: size)
        try sh("zip -q -fz test.zip test.img")
        try assertFlashes(tempDir.appendingPathComponent("test.zip"), producing: Data(contentsOf: original))
    }

    /// Info-ZIP switches to ZIP64 records when reading from a pipe.
    func testZipFromPipeUsesZip64() throws {
        let original = try makeImage(size: size)
        try sh("cat test.img | zip -q test.zip -")
        try assertFlashes(tempDir.appendingPathComponent("test.zip"), producing: Data(contentsOf: original))
    }

    /// Finder's "Compress" (ditto) leaves sizes out of the local header and writes a
    /// data descriptor after the data, so only the central directory has them.
    func testFinderStyleZip() throws {
        let original = try makeImage(size: size)
        try shell("/usr/bin/ditto", "-c", "-k", "--sequesterRsrc", "test.img", "test.zip")
        let image = tempDir.appendingPathComponent("test.zip")
        XCTAssertEqual(try ImageSources.inspect(image).imageSize, Int64(size))
        try assertFlashes(image, producing: Data(contentsOf: original))
    }

    func testCorruptZipFailsChecksum() throws {
        _ = try makeImage(size: size)
        try sh("zip -q -0 test.zip test.img")
        let image = tempDir.appendingPathComponent("test.zip")
        var data = try Data(contentsOf: image)
        data[data.count / 2] ^= 0xFF // inside the stored image data
        try data.write(to: image)

        let device = try openRamDisk()
        defer { close(device) }
        XCTAssertThrowsError(try ImageWriter.flash(image: image, to: device) { _ in }) { error in
            guard case ImageSourceError.corrupt = error else { return XCTFail("unexpected \(error)") }
        }
    }

    // MARK: Unsupported

    func testRejectsUnsupportedFormats() throws {
        let sevenZip = tempDir.appendingPathComponent("test.7z")
        try Data([0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C, 0, 4]).write(to: sevenZip)
        let zstd = tempDir.appendingPathComponent("test.img.zst")
        try Data([0x28, 0xB5, 0x2F, 0xFD, 0, 0, 0, 0]).write(to: zstd)
        _ = try makeImage(size: 1024, name: "test.tar")
        try sh("gzip -c test.tar > test.tar.gz")

        for name in ["test.7z", "test.img.zst", "test.tar.gz"] {
            XCTAssertThrowsError(try ImageSources.inspect(tempDir.appendingPathComponent(name)), name) { error in
                guard case ImageSourceError.unsupported = error else { return XCTFail("\(name): unexpected \(error)") }
            }
        }
    }

    private func xzTool() throws -> String {
        for path in ["/opt/homebrew/bin/xz", "/usr/local/bin/xz"] where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        throw XCTSkip("xz command-line tool not installed")
    }
}
