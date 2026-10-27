import XCTest
@testable import Kagami

/// Base class that attaches a 16 MiB RAM disk with `hdiutil` for each test.
/// RAM disks belong to the current user, so no administrator prompt is needed
/// and no real drive is ever touched.
class RamDiskTestCase: XCTestCase {
    static let ramDiskSize = 16 * 1024 * 1024

    var ramDisk: String! // e.g. "disk30"
    var tempDir: URL!
    var rawDevicePath: String { "/dev/r\(ramDisk!)" }

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let output = try shell("/usr/bin/hdiutil", "attach", "-nomount", "ram://\(Self.ramDiskSize / 512)")
        ramDisk = output.split(separator: " ").first.map { String($0).replacingOccurrences(of: "/dev/", with: "") }
        XCTAssertNotNil(ramDisk)
        try shell("/bin/chmod", "u+w", rawDevicePath)
    }

    override func tearDownWithError() throws {
        if let ramDisk { _ = try? shell("/usr/bin/hdiutil", "detach", "/dev/\(ramDisk)", "-force") }
        try? FileManager.default.removeItem(at: tempDir)
    }

    /// Disk-image-like content: runs of pseudo-random data separated by zeroed regions.
    func makeImageData(size: Int, seed: UInt64 = 1) -> Data {
        var bytes = [UInt8](repeating: 0, count: size)
        var state = seed &* 0x9E37_79B9_7F4A_7C15
        for i in bytes.indices where (i / 65_536) % 3 != 2 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            bytes[i] = UInt8(truncatingIfNeeded: state >> 33)
        }
        return Data(bytes)
    }

    func makeImage(size: Int, name: String = "test.img") throws -> URL {
        let url = tempDir.appendingPathComponent(name)
        try makeImageData(size: size).write(to: url)
        return url
    }

    func openRamDisk() throws -> Int32 {
        let fd = open(rawDevicePath, O_RDWR)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno)!) }
        return fd
    }

    func readDevice(count: Int) throws -> Data {
        let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: rawDevicePath))
        defer { try? handle.close() }
        let rounded = (count + 511) / 512 * 512
        return try handle.read(upToCount: rounded) ?? Data()
    }

    /// Flashes `image` onto the RAM disk and asserts the drive now starts with `expected`.
    func assertFlashes(_ image: URL, producing expected: Data, file: StaticString = #filePath, line: UInt = #line) throws {
        let device = try openRamDisk()
        defer { close(device) }
        var last: FlashProgress?
        try ImageWriter.flash(image: image, to: device) { last = $0 }
        XCTAssertEqual(last?.phase, .verifying, file: file, line: line)
        XCTAssertEqual(last?.fraction, 1, file: file, line: line)
        XCTAssertEqual(try readDevice(count: expected.count).prefix(expected.count), expected, file: file, line: line)
    }

    @discardableResult
    func shell(_ args: String...) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: args[0])
        process.arguments = Array(args.dropFirst())
        process.currentDirectoryURL = tempDir
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "shell", code: Int(process.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: "\(args.joined(separator: " ")) failed"])
        }
        return String(decoding: data, as: UTF8.self)
    }

    /// Runs a shell pipeline inside the temp directory (for redirections and `cat`).
    func sh(_ script: String) throws {
        try shell("/bin/sh", "-c", script)
    }
}
