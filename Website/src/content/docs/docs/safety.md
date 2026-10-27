---
title: Safety
description: Which drives Kagami will erase, which it never shows, and how it gets permission to write.
---

Flashing erases a drive completely. Kagami is built so that the drive it erases is the one you meant.

## Which drives are listed

A drive appears in the list only if it is all of these:

- a **whole, physical disk** that is writable and has media in it,
- **not a disk image or a RAM disk** — anything mounted from a file is left out,
- **not an APFS container** — the logical disks macOS builds on top of a physical one,
- **not your Mac's own drive.** Internal disks are left out — except a built-in SD card reader, whose
  cards are removable and so do appear.

That still includes every external disk you plug in, an external backup drive among them. **Check
the size and the name** in the list, and the confirmation that follows, before you press Flash.

## Before anything is written

- **You confirm.** Every flash asks *Erase “…” (32 GB, disk4)?* first.
- **macOS asks for a password.** Writing to a disk needs an administrator. Kagami asks macOS's own
  `authopen` to open that one disk; it shows the system's prompt, and Kagami never sees the
  password. The permission is for that disk, for that one flash.
- **Nothing is installed.** There is no helper tool and no background service — nothing stays
  behind with elevated rights once the flash is over.

## While writing

- The drive is **unmounted** first, so nothing else is using it while it is written.
- **Quitting asks first**, and an update never restarts Kagami in the middle of a flash.
- After writing, the drive is **read back and compared** with the image, unless you skip it.

## What Kagami cannot protect you from

Choosing the wrong external drive. If two drives of the same size are plugged in, unplug the one you
want to keep before flashing.
