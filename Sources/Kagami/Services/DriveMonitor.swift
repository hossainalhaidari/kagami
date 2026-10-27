import DiskArbitration
import Foundation
import Observation

/// Keeps a live list of drives that can be flashed, using Disk Arbitration
/// appear/disappear notifications.
@MainActor
@Observable
final class DriveMonitor {
    private(set) var drives: [Drive] = []

    @ObservationIgnored private let session: DASession
    @ObservationIgnored private var known: [String: Drive] = [:]

    /// Partition-type GUID used for synthesized APFS containers. Those are
    /// logical disks layered on a physical one and must never be offered.
    private nonisolated static let apfsContainerContent = "EF57347C-0000-11AA-AA11-00306543ECAC"

    init() {
        session = DASessionCreate(kCFAllocatorDefault)!
        let match = [kDADiskDescriptionMediaWholeKey as String: true] as CFDictionary
        let context = Unmanaged.passUnretained(self).toOpaque()

        DARegisterDiskAppearedCallback(session, match, { disk, context in
            DriveMonitor.from(context).refresh(disk)
        }, context)
        DARegisterDiskDescriptionChangedCallback(session, match, nil, { disk, _, context in
            DriveMonitor.from(context).refresh(disk)
        }, context)
        DARegisterDiskDisappearedCallback(session, match, { disk, context in
            DriveMonitor.from(context).remove(disk)
        }, context)

        // Callbacks are delivered on the main queue, so they run on the main actor.
        DASessionSetDispatchQueue(session, .main)
    }

    private nonisolated static func from(_ context: UnsafeMutableRawPointer?) -> DriveMonitor {
        Unmanaged<DriveMonitor>.fromOpaque(context!).takeUnretainedValue()
    }

    private nonisolated func refresh(_ disk: DADisk) {
        let drive = Self.drive(for: disk)
        let bsdName = DADiskGetBSDName(disk).map { String(cString: $0) }
        MainActor.assumeIsolated {
            guard let bsdName else { return }
            known[bsdName] = drive
            publish()
        }
    }

    private nonisolated func remove(_ disk: DADisk) {
        let bsdName = DADiskGetBSDName(disk).map { String(cString: $0) }
        MainActor.assumeIsolated {
            guard let bsdName else { return }
            known[bsdName] = nil
            publish()
        }
    }

    private func publish() {
        drives = known.values.sorted {
            $0.bsdName.compare($1.bsdName, options: .numeric) == .orderedAscending
        }
    }

    /// Returns a `Drive` if the disk is an eligible target, otherwise `nil`.
    nonisolated static func drive(for disk: DADisk) -> Drive? {
        guard let desc = DADiskCopyDescription(disk) as? [String: Any] else { return nil }
        func value<T>(_ key: CFString) -> T? { desc[key as String] as? T }

        guard
            let bsdName: String = value(kDADiskDescriptionMediaBSDNameKey),
            value(kDADiskDescriptionMediaWholeKey) == true,
            value(kDADiskDescriptionMediaWritableKey) == true,
            let size: Int64 = (value(kDADiskDescriptionMediaSizeKey) as NSNumber?)?.int64Value,
            size > 0
        else { return nil }

        // Mounted disk images, RAM disks, etc.
        if value(kDADiskDescriptionDeviceProtocolKey) == "Virtual Interface" { return nil }
        // Synthesized APFS containers.
        if value(kDADiskDescriptionMediaContentKey) == apfsContainerContent { return nil }

        // Internal fixed disks (the Mac's SSD) are never offered. Built-in SD card
        // readers report as internal but with removable media, so those stay.
        let isInternal: Bool = value(kDADiskDescriptionDeviceInternalKey) ?? false
        let isRemovable: Bool = value(kDADiskDescriptionMediaRemovableKey) ?? false
        if isInternal && !isRemovable { return nil }

        let vendor: String = value(kDADiskDescriptionDeviceVendorKey) ?? ""
        let model: String = value(kDADiskDescriptionDeviceModelKey) ?? ""
        let name = [vendor, model]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        return Drive(
            bsdName: bsdName,
            name: name.isEmpty ? bsdName : name,
            size: size,
            isRemovable: isRemovable
        )
    }
}
