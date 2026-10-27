# Changelog

Everything notable that changed in the app. The website and its documentation are not the app, so
they are not here; what a release changed about Kagami itself is.

Each version's section below is what the release workflow publishes: it becomes the GitHub release's
description and the release notes Kagami shows in its own update window, so it is written for
someone deciding whether to install it.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-10-27

The first release.

### Added

- **Flash an image in three steps.** Choose an image (or drop it on the window), choose a drive,
  press **Flash**. Kagami asks before erasing the drive, shows progress with speed and time left,
  and ejects the drive when it is done.
- **Bootable drives.** The image is copied byte for byte, partition table and boot sectors included,
  so Raspberry Pi images and almost every Linux and BSD `.iso` boot from the drive.
- **Compressed images, no extracting.** `.gz`, `.xz`, `.bz2` and `.zip` images are decompressed
  while they are written — including Raspberry Pi OS's multi-block `.xz` files, ZIP64 archives and
  ZIPs made with Finder's Compress.
- **Verification.** After writing, Kagami reads the drive back and compares it with the image. A
  damaged download or a failing drive is reported instead of leaving a drive that silently will not
  boot. **Skip Verification** ends the check early when you are in a hurry.
- **Only drives you can safely erase.** USB drives and SD cards are listed; the Mac's own disk, disk
  images and APFS containers never are.
- **Updates**, off until you turn them on: *Settings ▸ Updates* chooses between installing
  automatically, asking first, or only checking when you choose *Check for Updates…*. An update never
  restarts Kagami in the middle of a flash.

[Unreleased]: https://github.com/hossainalhaidari/kagami/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/hossainalhaidari/kagami/releases/tag/v0.1.0
