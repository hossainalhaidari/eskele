# Changelog

Everything notable that changed in the app. The website and its documentation are not the app, so
they are not here; what a release changed about Eskele itself is.

Each version's section below is what the release workflow publishes: it becomes the GitHub release's
description and the release notes Eskele shows in its own update window, so it is written for
someone deciding whether to install it.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Spring-loading**: hold a dragged file over a running application and it comes forward, or over
  a folder and it opens in Finder, so you can carry on and drop the file into a message you are
  writing or a folder further down. It waits as long as the system's own spring-loading delay,
  under *Accessibility ▸ Pointer Control*, and stays off if you have switched that off.
- **Sort By** in a folder's context menu lists its stack by name, date added, date modified, date
  created or kind. Downloads starts out newest first, as in the system Dock; every other folder
  keeps sorting by name until you choose otherwise.
- **Scroll on an application** to step through its windows: up for the next, down for the one
  before. One swipe on a trackpad is one window, however far it goes. An application in the
  background comes forward first, on the window it was on. Turn it off under *Behaviour ▸
  Displays*.
- **Export Layout** and **Import Layout**, under *General ▸ Transfer and Reset*, take what you have
  pinned to another Mac, with the names and stack orders you gave it. Applications are found by what
  they are and folders in your home folder by where they sit in it, so a different user name is no
  obstacle. Anything that is not on the new Mac is left out, and you are told what.

## [0.2.0] - 2026-10-02

### Added

- **Mark only apps with open windows**, in the Contents settings, leaves the running indicator off
  applications that are hidden or have closed every window — Finder, or Mail left running in the
  background — so the marks on the bar are the applications you actually have open. Off by default.
- **Force Quit** in an application's context menu: hold ⌥ while the menu is open and Quit becomes
  Force Quit, as in the system Dock. For an application that has stopped responding, Force Quit
  takes Quit's place without the key. A window's menu does the same with Quit and Force Quit.
- **Hide Others**, behind ⌥ on Hide, brings the application forward and hides every other one.
- **Relaunch**, under Options, quits an application and opens it again — handy after an update or a
  setting it only reads at launch. It asks the application to quit, so unsaved work still gets its
  sheet. Hold ⌥ for Force Quit and Relaunch.

## [0.1.2] - 2026-09-28

### Changed

- On the application you are using, the **window you are on** gets a long, bright running dash and
  its other windows shrink to dots, so an application with three windows shows which of the three
  you are on. Applications in the background keep their even row of dashes.
- The **hover label appears the moment the pointer reaches a cell**, as the system Dock's does. With
  Reserve Screen Space on, the Dock parked under the bar used to name whichever of its own icons
  was underneath first, so for a moment the label could read Finder over Visual Studio Code. The
  window preview still waits until the pointer rests.

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

[Unreleased]: https://github.com/hossainalhaidari/eskele/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/hossainalhaidari/eskele/compare/v0.1.2...v0.2.0
[0.1.2]: https://github.com/hossainalhaidari/eskele/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/hossainalhaidari/eskele/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/hossainalhaidari/eskele/releases/tag/v0.1.0
