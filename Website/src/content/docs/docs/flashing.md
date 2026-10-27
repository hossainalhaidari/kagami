---
title: Flashing a drive
description: The three steps, what each part of the window means, and what happens when you stop half-way.
---

## 1. Choose an image

Press **Choose…**, or drop the file anywhere on the window. Under its name Kagami shows what it
found: just the size for a raw image, or the format and both sizes for a compressed one —
`xz · 1.1 GB → 5.7 GB`. For a ZIP it also names the image it found inside.

A file Kagami cannot write is refused right there, with the reason: a 7-Zip or Zstandard archive, a
`.tar`, an empty file. [Supported images](../images/) has the full list.

## 2. Choose a drive

Plug in a USB drive or put a card in the reader; it appears in the list within a second, named by its
maker and model, with its size and its BSD name (`disk4`). Only drives Kagami may erase are ever
listed — see [Safety](../safety/).

If the image is bigger than the drive, **Flash** stays off and Kagami says why.

## 3. Flash

Press **Flash** and confirm. Then, in order:

1. **Unmounting** — every volume on the drive is unmounted.
2. **Waiting for administrator authorization** — macOS asks for an administrator's password. This
   is the system's own prompt; Kagami never sees the password. Cancel it and nothing has been
   written, and the drive's volumes are mounted again.
3. **Writing** — the progress bar, the speed and the time left.
4. **Verifying** — the drive is read back and compared with the image.
5. **Ejecting** — when it is done, the drive is ejected and can be pulled out.

**Flash complete** means the drive matches the image byte for byte.

## Stopping early

| You press… | While… | The drive |
|---|---|---|
| **Cancel** | writing | Only partly written. It will not boot; flash it again. |
| **Skip Verification** | verifying | Completely written, just not checked. Kagami ejects it and says *Written, not verified*. |

**Closing the window** while a flash runs only hides it: the flash carries on, and clicking Kagami in
the Dock brings the window back. **Quitting** asks first, and says what quitting would leave behind.

## After flashing a Linux image

macOS cannot read the file systems most Linux images use, so the moment the drive is plugged back in
it may say *The disk you attached was not readable by this computer.* That is expected — the drive is
fine. Choose **Ignore** or **Eject**, never **Initialize…**, which would erase it.
