---
title: Supported images
description: Which files Kagami writes, which ones boot afterwards, and which it turns away.
---

## Formats

Kagami decides the format from the first bytes of the file, not from its name, so a misnamed file
still works.

| Format | What Kagami handles | Size known before writing |
|---|---|---|
| Raw (`.img`, `.iso`, `.raw`, `.bin`) | Written as it is. | Yes |
| gzip (`.gz`) | Several members back to back, as `pigz` and `cat a.gz b.gz` produce. | No |
| xz (`.xz`) | Multi-block files, as multi-threaded `xz` (and Raspberry Pi OS) produce; several streams back to back; every integrity check xz offers. | Yes, from the file's index |
| bzip2 (`.bz2`) | Several streams back to back, as `pbzip2` produces. | No |
| ZIP (`.zip`) | Stored or deflated entries, ZIP64 for big images, and ZIPs made with Finder's *Compress*. Its CRC-32 is checked. | Yes, from the archive's directory |

**In a ZIP**, Kagami writes the largest file with an image-like extension (`.img`, `.iso`, `.raw`,
`.bin`, `.dd`, `.hdd`), or the largest file if none has one. macOS's `__MACOSX` folder and `.DS_Store`
files are ignored, so a README beside the image does not get in the way.

**When the size is not known up front** (gzip, bzip2), the progress bar follows how much of the
compressed file has been read, and an image too big for the drive is only caught when the drive
fills up — with an error, not a silently truncated drive.

Not supported, and refused with a message: **7-Zip** (`.7z`), **Zstandard** (`.zst`) and **tar
archives** (`.tar`, `.tar.gz`, `.tgz`…). Extract the image first and choose that.

## What boots

Kagami makes the drive an exact copy of the image, the way `dd` does. Whether that boots depends on
how the image was made:

- **Raspberry Pi images, and other SD-card images for single-board computers** — yes. They are made
  to be written exactly like this.
- **Almost every Linux and BSD `.iso`** — yes. Ubuntu, Fedora, Debian, Arch, the BSDs and most others
  ship *hybrid* ISOs, which carry a partition table a USB stick can boot from.
- **Windows installer ISOs** — no. They are not hybrid images, so written raw they do not boot, with
  Kagami or with any other tool that writes raw (`dd`, balenaEtcher). They need a tool that builds a
  FAT or NTFS installer drive instead.
- **macOS installers** — no. Apple's `createinstallmedia` makes those.

If an image's download page says to write it with `dd` or Etcher, Kagami is the right tool.
