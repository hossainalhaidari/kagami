import Foundation

/// A whole, physical disk that is safe to offer as a flash target.
struct Drive: Identifiable, Hashable, Sendable {
    /// BSD name of the whole disk, e.g. `disk4`.
    let bsdName: String
    let name: String
    let size: Int64
    let isRemovable: Bool

    var id: String { bsdName }

    /// Character ("raw") device: unbuffered and much faster than `/dev/diskN`.
    var rawDevicePath: String { "/dev/r\(bsdName)" }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}
