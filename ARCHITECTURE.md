# Kagami — Architecture

A macOS app that writes disk images to USB drives and SD cards: choose an image, choose a drive,
press **Flash**. It does nothing else.

---

## 1. Goals / Non-goals

**Goals**

1. Drives that boot: a byte-for-byte copy of the image, like `dd`.
2. The common distribution formats without extracting first: raw, gzip, xz, bzip2, ZIP.
3. Proof the copy is right: read the drive back and compare.
4. No way to pick the Mac's own disk by mistake.
5. No privileged helper to install, and no third-party code beyond Sparkle.

**Non-goals**

- Windows installer ISOs. They are not hybrid images and do not boot when written raw — true of
  Etcher and `dd` as well. Making one bootable means building a FAT/NTFS installer, a different tool.
- Formats macOS has no decoder for: 7-Zip, Zstandard, tar archives. They are rejected with a message.
- Mac App Store distribution. Raw disk access is impossible inside the App Sandbox (§7).

---

## 2. A flash, end to end

```
choose image ──► ImageSources.inspect      format, sizes, rejects what can't be written
choose drive ──► DriveMonitor              live list of eligible whole disks
Flash        ──► DiskOperations.unmountAll Disk Arbitration, whole disk
             ──► AuthOpen.open             admin prompt; root-opened fd for /dev/rdiskN
             ──► ImageWriter.flash         decompress → write → flush → read back → compare
             ──► DiskOperations.eject      with retries; macOS may mount the new partitions first
```

`FlashModel` (main actor) runs this as one task and turns it into the UI's states. The blocking
parts — the authorization prompt and the write — run off the main actor in `@concurrent` functions.

---

## 3. Drives (`DriveMonitor`, `DiskOperations`)

The list comes from Disk Arbitration's appeared / disappeared / description-changed callbacks on
whole disks, so drives come and go as they are plugged in. A disk is offered only if it is:

- whole, writable and non-empty,
- not a virtual device (mounted disk images, RAM disks: protocol `Virtual Interface`),
- not a synthesized APFS container (content `EF57347C-0000-11AA-AA11-00306543ECAC`),
- not internal *and* fixed. Built-in SD card readers report as internal but with removable media,
  so they stay; the Mac's SSD never appears.

Before writing, the whole disk is unmounted (`kDADiskUnmountOptionWhole`). Afterwards it is ejected,
retried for a few seconds: closing the device makes macOS re-read the new partition table and
sometimes mount a partition just before the eject arrives.

## 4. Privileged access (`AuthOpen`)

Writing `/dev/rdiskN` needs root. Rather than a privileged helper (`SMAppService` daemons need
installing, approving and versioning), Kagami runs `/usr/libexec/authopen -stdoutpipe -o O_RDWR`,
which shows the system's administrator prompt, opens the device as root, and passes the open file
descriptor back over a UNIX socket as an `SCM_RIGHTS` message. Raspberry Pi Imager does the same.
Nothing privileged outlives the flash.

## 5. Images (`ImageSource`)

The format is decided by magic bytes, not the file name:

| Format | Decoder | Size known up front |
|---|---|---|
| raw | — | yes |
| gzip | zlib (`inflate`, multi-member, as `pigz` writes) | no |
| xz | Compression framework (LZMA/xz), restarted per concatenated stream | yes, from the stream index |
| bzip2 | system libbz2 via `Sources/CBZip2`, multi-stream, as `pbzip2` writes | no |
| ZIP | zlib raw deflate or stored; ZIP64; data descriptors; CRC-32 checked | yes, from the central directory |

A ZIP may hold several files: the largest one with an image extension wins, and macOS metadata
(`__MACOSX/`, `.DS_Store`) is ignored. When the size is unknown, progress follows the compressed
file and an image too big for the drive is caught when the drive fills up.

## 6. Writing and verifying (`ImageWriter`)

- 4 MiB chunks to the raw (`r`) device; only the last chunk may be short, and it is zero-padded to
  the device block size, which raw devices require.
- The image is hashed (SHA-256) as it is written; afterwards the drive cache is flushed
  (`DKIOCSYNCHRONIZECACHE`), the same number of bytes is read back, hashed and compared.
- Cancelling while writing throws, and the drive is reported as partially written. Cancelling while
  verifying — **Skip Verification** — returns `.unverified`: the image is already complete.

## 7. Distribution

- Not sandboxed (authopen, raw devices). Hardened Runtime, no extra entitlements.
- SwiftPM builds a bare executable; `Scripts/build-app.sh` makes the bundle, embeds Sparkle, and signs
  it; `Scripts/package.sh` signs with the Developer ID, notarises, staples and wraps it in a DMG.
- Updates are Sparkle 2, feed on the latest GitHub release, EdDSA-signed. Automatic checks start off.
  `UpdateService` postpones an update's relaunch until a running flash has finished, and quitting
  mid-flash asks first.

## 8. Testing

The tests attach a 16 MiB RAM disk with `hdiutil` (owned by the user, so no prompt) and flash real
images onto its raw device: every format and its variants, corrupt and truncated input, images too
big for the drive, cancellation in both phases, and the `authopen` descriptor-passing path. Nothing in
the suite touches a real drive.

## 9. Repository layout

```
Sources/Kagami/App        KagamiApp (scenes, menu commands, app delegate), AboutPanel
Sources/Kagami/Model      Drive, FlashModel, UpdatePolicy
Sources/Kagami/Services   DriveMonitor, DiskOperations, AuthOpen, ImageSource, ImageWriter, UpdateService
Sources/Kagami/UI         ContentView, SettingsView
Sources/CBZip2            module map exposing the system's bzlib.h
Tests/KagamiTests         RAM-disk tests
Resources                 Info.plist, entitlements, AppIcon.icon and its generated icns/Assets.car
Scripts                   build-app, sign-app, package, update-key, make-icon, rendersvg
Website                   Astro + Starlight site, deployed to GitHub Pages
```
