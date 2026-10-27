---
title: Troubleshooting
description: A drive that does not appear, an unmount that fails, a verification that does not match.
---

## The drive does not appear

- **Is it a disk image or the Mac's own drive?** Those are never listed — see [Safety](../safety/).
- **A card reader with no card**, or a card that has not been read yet, has no size and is not
  listed. Take the card out and put it back.
- **Some USB hubs and adapters** present the card reader before the card. Wait a few seconds after
  inserting; the list updates by itself.
- Check that the drive appears in *Disk Utility*. If it does not appear there either, macOS cannot
  see it at all — try another port or cable.

## “Could not unmount the drive”

Something is using a file on the drive: a Finder window showing it, a document open from it, Spotlight
indexing it, a backup. Close what is using it and press **Flash** again. *Disk Utility* can show
which volume refuses to unmount.

## The administrator prompt did not appear

It can open behind another window — look for it in Mission Control. Pressing *Cancel* there leaves
the drive untouched and mounts its volumes again.

## “Verification failed”

The drive does not hold what was written. Usually the **drive or card is failing**, or it is a
counterfeit that reports more space than it has — cheap high-capacity cards often do. Try another
drive. If two good drives both fail with the same image, download the image again.

## “The image is damaged”

The compressed file is corrupt or incomplete — its own checksum does not match, or it ends before the
image does. Download it again; most download pages publish a checksum to compare with.

## “The image is larger than the drive”

The image really is bigger. For gzip and bzip2 images Kagami only finds out once the drive is full,
because those formats do not record the size; the drive is then only partly written.

## “The disk you attached was not readable by this computer”

Expected after flashing most Linux images: macOS cannot read their file systems. The drive is fine.
Choose **Ignore** or **Eject** — not **Initialize…**, which erases it.

## The drive was not ejected

Kagami tries for a few seconds; if something mounted it again meanwhile, it says so. Eject it in
Finder before pulling it out.

## It flashed, but does not boot

Check [What boots](../images/#what-boots): Windows installer ISOs never boot when written raw. For
everything else, check that the computer is set to boot from USB, and that the image is meant for
that machine — an `arm64` image will not boot a PC, nor an `amd64` one a Raspberry Pi.
