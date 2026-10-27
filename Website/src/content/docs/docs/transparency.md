---
title: Transparency
description: How Kagami was made, and the terms it comes with.
---

## How Kagami was built

**Kagami's code was written with the help of AI.** Much of the Swift source, the tests, the build
scripts and this documentation was drafted with an AI coding assistant, then directed, reviewed and
shaped by a person.

**The test suite flashes real images onto a RAM disk.** Every supported format and its variants,
damaged and truncated files, images too big for the drive, cancelling, and the administrator-prompt
path are all exercised by writing to an actual block device and reading it back — just not a USB
stick. Flashing real drives is done by hand.

That is said here so you can weigh it for yourself. The full source is
[on GitHub](https://github.com/hossainalhaidari/kagami), and anything that looks wrong is welcome as
an [issue](https://github.com/hossainalhaidari/kagami/issues).

## Provided as is

Kagami is free, open-source software, provided **"as is", without warranty of any kind**, express or
implied, including but not limited to the warranties of merchantability, fitness for a particular
purpose and non-infringement. There is no promise that it works, keeps working, or suits any purpose.

In no event shall the authors or copyright holders be liable for any claim, damages or other
liability — including loss of data — whether in an action of contract, tort or otherwise, arising
from, out of or in connection with the software or its use. Flashing erases the chosen drive
completely. You use it at your own risk.

These terms are those of the [MIT License](https://github.com/hossainalhaidari/kagami/blob/main/LICENSE)
Kagami is released under; where this page and the licence differ, the licence applies.
