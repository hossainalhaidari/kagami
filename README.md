<p align="center">
  <img src="Website/src/assets/mark.svg" width="128" height="128" alt="Kagami app icon">
</p>

<h1 align="center">Kagami</h1>

<p align="center">
  Flash disk images to USB drives and SD cards on macOS — bootable, verified, nothing else.
</p>

<p align="center">
  <sub><em>Kagami</em> — 鏡 — is Japanese for mirror: the drive becomes an exact reflection of the image.</sub>
</p>

<p align="center">
  <a href="https://hossain.al/kagami/">Website</a> ·
  <a href="https://hossain.al/kagami/docs/">Documentation</a> ·
  <a href="https://github.com/hossainalhaidari/kagami/releases">Download</a>
</p>

## Install

Download the latest DMG from the [releases page](https://github.com/hossainalhaidari/kagami/releases),
or install it with Homebrew:

```bash
brew install --cask hossainalhaidari/tap/kagami
```

or build it yourself:

```bash
make run    # build, bundle and launch Kagami.app
make test   # run the test suite (it writes to a throwaway RAM disk, never a real drive)
```

Choose an image, choose a drive, press **Flash**. Raw `.img` and `.iso` files work, and so do
`.gz`, `.xz`, `.bz2` and `.zip` images, decompressed on the fly. Everything else, from supported
images to troubleshooting, is in the [documentation](https://hossain.al/kagami/docs/).
How it works inside is in [ARCHITECTURE.md](ARCHITECTURE.md).

## License

Kagami is released under the [MIT License](LICENSE).

**Kagami is provided "as is", without warranty of any kind**, express or implied, including but not
limited to the warranties of merchantability, fitness for a particular purpose and non-infringement.
In no event shall the authors be liable for any claim, damages or other liability arising from, out
of or in connection with the software or its use. Flashing erases the chosen drive completely; check
which drive you picked. See [Transparency](https://hossain.al/kagami/docs/transparency/)
for how the project was built.
