import DiskArbitration
import Foundation

enum DiskOperationError: LocalizedError {
    case diskNotFound(String)
    case dissented(action: String, status: DAReturn, reason: String?)

    var errorDescription: String? {
        switch self {
        case .diskNotFound(let bsdName):
            return "The drive \(bsdName) is no longer connected."
        case let .dissented(action, status, reason):
            let detail = reason ?? String(format: "error 0x%08x", status)
            return "Could not \(action) the drive: \(detail)"
        }
    }
}

/// Async wrappers around the Disk Arbitration unmount / mount / eject calls.
enum DiskOperations {
    /// Unmounts every volume on the whole disk so its raw device can be opened for writing.
    static func unmountAll(_ bsdName: String) async throws {
        try await perform("unmount", bsdName) { disk, callback, context in
            DADiskUnmount(disk, DADiskUnmountOptions(kDADiskUnmountOptionWhole), callback, context)
        }
    }

    /// Asks the system to mount the disk's volumes again (best effort after an aborted flash).
    static func mountAll(_ bsdName: String) async throws {
        try await perform("mount", bsdName) { disk, callback, context in
            DADiskMountWithArguments(disk, nil, DADiskMountOptions(kDADiskMountOptionWhole), callback, context, nil)
        }
    }

    /// Unmounts and ejects the disk so it can be safely removed.
    static func eject(_ bsdName: String) async throws {
        try await unmountAll(bsdName)
        try await perform("eject", bsdName) { disk, callback, context in
            DADiskEject(disk, DADiskEjectOptions(kDADiskEjectOptionDefault), callback, context)
        }
    }

    private typealias Callback = @convention(c) (DADisk, DADissenter?, UnsafeMutableRawPointer?) -> Void

    private final class Completion {
        let continuation: CheckedContinuation<Void, Error>
        let action: String
        init(_ continuation: CheckedContinuation<Void, Error>, action: String) {
            self.continuation = continuation
            self.action = action
        }
    }

    private static func perform(
        _ action: String,
        _ bsdName: String,
        _ start: (DADisk, Callback, UnsafeMutableRawPointer) -> Void
    ) async throws {
        guard let session = DASessionCreate(kCFAllocatorDefault) else {
            throw DiskOperationError.diskNotFound(bsdName)
        }
        let queue = DispatchQueue(label: "Kagami.DiskOperations")
        DASessionSetDispatchQueue(session, queue)
        defer { DASessionSetDispatchQueue(session, nil) }

        guard let disk = DADiskCreateFromBSDName(kCFAllocatorDefault, session, bsdName) else {
            throw DiskOperationError.diskNotFound(bsdName)
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let context = Unmanaged.passRetained(Completion(continuation, action: action)).toOpaque()
            let callback: Callback = { _, dissenter, context in
                let completion = Unmanaged<Completion>.fromOpaque(context!).takeRetainedValue()
                if let dissenter {
                    let status = DADissenterGetStatus(dissenter)
                    let reason = DADissenterGetStatusString(dissenter) as String?
                    completion.continuation.resume(
                        throwing: DiskOperationError.dissented(action: completion.action, status: status, reason: reason))
                } else {
                    completion.continuation.resume()
                }
            }
            start(disk, callback, context)
        }
    }
}
