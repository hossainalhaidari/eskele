# Changelog

Everything notable that changed in the app. The website and its documentation are not the app, so
they are not here; what a release changed about Eskele itself is.

Each version's section below is what the release workflow publishes: it becomes the GitHub release's
description and the release notes Eskele shows in its own update window, so it is written for
someone deciding whether to install it.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- On the application you are using, the **window you are on** gets a long, bright running dash and
  its other windows shrink to dots, so an application with three windows shows which of the three
  you are on. Applications in the background keep their even row of dashes.

## [0.1.1] - 2026-09-23

### Changed

- Eskele now points at its own home, `eskele.app`: the **Website** link in the About panel, and the
  address `--diagnose` prints beside a permissions warning.

## [0.1.0] - 2026-09-22

The first release.

### Added

- A bar along the **left, bottom or right** screen edge, one menu-bar thickness, in two scales and up
  to five rows — columns, on a side bar. It either fits its icons or spans the edge, with icon-only
  or labelled items.
- **Three designs** — Dock, Classic and Unity — each a click, and a Custom tile that keeps whatever
  you changed afterwards, so trying another one is not losing yours.
- **Hiding the system Dock** while Eskele runs: the Dock's own preferences are backed up first and
  put back when Eskele quits, `make restore-dock` recovers even with the app deleted, and reserved
  screen space stops maximised windows short of the bar.
- **Running applications** with one dash per window, window lists and titles from Accessibility, and
  clicks that launch, activate, cycle windows or hide — plus a button per window in full-width mode.
- **Pinned applications, files and folders**: drag to reorder, drag off to unpin, drop files on an app
  to open them with it, folder stacks that list their contents, a Trash that takes drops and asks
  before emptying, and an *Add to Eskele* item in Finder's Services menu.
- **The Apps Menu**, a searchable launcher over your favourites, every application by category, or
  the recent ones, with Sleep, Log Out, Restart and Shut Down, and a gear into Settings.
- **What a cell can tell you**: badges from the Dock's own tiles and from commands of your own,
  progress bars for file operations and for anything else you can script, an activity overlay for
  processor and memory while a modifier is held, and a highlight for an app asking for attention.
- **A clock** with a choice of faces, **custom icons and names** per item, and **multi-display**
  support with a bar per screen.
- **Auto-hide** with a global reveal key, a choice of what the bar does inside a full-screen space,
  hot keys for the first nine slots, keyboard access with ⌃⌥⇥, and VoiceOver labels, values and
  actions on every cell.
- **A settings window** of five panes, with export, import and reset, launch at login, and a
  first-run choice of how Eskele should treat the Dock.
- **Opt-in updates**: Eskele never checks until you ask it to, and checks nothing about you when it
  does. Every update is verified against a key built into the copy you are running.
- **English throughout, translatable everywhere**: every string is in a catalogue the test suite
  checks against the source, so a second language is a directory away.

[Unreleased]: https://github.com/hossainalhaidari/eskele/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/hossainalhaidari/eskele/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/hossainalhaidari/eskele/releases/tag/v0.1.0
