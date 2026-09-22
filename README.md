<p align="center">
  <img src="Website/src/assets/mark.svg" width="128" height="128" alt="Eskele app icon">
</p>

<h1 align="center">Eskele</h1>

<p align="center">
  A minimal macOS dock for the left, bottom or right edge — that hides the system Dock while it runs.
</p>

<p align="center">
  <a href="https://hossainalhaidari.github.io/eskele/">Website</a> ·
  <a href="https://hossainalhaidari.github.io/eskele/docs/">Documentation</a> ·
  <a href="https://github.com/hossainalhaidari/eskele/releases">Download</a>
</p>

## Install

Download the latest DMG from the [releases page](https://github.com/hossainalhaidari/eskele/releases),
or build it yourself:

```bash
make run    # build, bundle and launch Eskele.app
make test   # run the test suite
```

Eskele has no Dock tile or window of its own — look for its icon in the menu bar. Everything else,
from permissions to troubleshooting, is in the [documentation](https://hossainalhaidari.github.io/eskele/docs/).
The design and the reasoning behind it are in [ARCHITECTURE.md](ARCHITECTURE.md).

If your system Dock is ever left hidden:

```bash
make restore-dock
```

Or, with Eskele deleted entirely:

```bash
defaults delete com.apple.dock autohide-delay; defaults write com.apple.dock autohide -bool false; killall Dock
```

## License

Eskele is released under the [MIT License](LICENSE).

**Eskele is provided "as is", without warranty of any kind**, express or implied, including but not
limited to the warranties of merchantability, fitness for a particular purpose and non-infringement.
In no event shall the authors be liable for any claim, damages or other liability arising from, out
of or in connection with the software or its use. See [Transparency](https://hossainalhaidari.github.io/eskele/docs/transparency/)
for how the project was built.
