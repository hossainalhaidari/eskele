---
title: Hiding the system Dock
description: What Eskele changes when it suppresses the real Dock, how your settings are backed up, and how to get the Dock back.
---

This is **off by default**.

Turning on *Hide System Dock* rewrites three `com.apple.dock` preferences and restarts the Dock.

## Reserve Screen Space

*Reserve Screen Space* instead parks the Dock *showing* on the bar's edge, at a tile size that makes
its screen-space reservation match the bar exactly, with its launch and attention bounces turned off.
The bar sits on top of it. The effect is that maximised windows stop short of the bar instead of
running underneath it.

The Dock is covered rather than hidden because only a Dock that is showing holds a reservation every
app respects: a hidden one gives its space back the next time an app launches or quits. Two things
follow from it being really there. A translucent bar can let its icons show through faintly. And the
option does nothing while the bar auto-hides, since a bar that slides away would uncover it.

It **does not work inside a native full-screen space** — macOS reserves nothing there except for the
menu bar. Reserved-space mode covers maximised windows; for full-screen, the bar can only float over
the window or [get out of the way](../layout/#in-full-screen). Zoom windows instead of sending them
full-screen if you never want the bar to overlap.

## Your original settings

Your original values are captured to:

```
~/Library/Application Support/Eskele/dock-backup.json
```

…**before anything is written**, and restored when Eskele quits — including on `SIGTERM`, via
`atexit`, and on the next launch if Eskele was `SIGKILL`ed.

*Restore System Dock* on the menu bar item undoes it immediately, without quitting.

:::caution[Restarting the Dock restarts more than the Dock]
Mission Control, Launchpad and Stage Manager all live in the same process, so they restart with it.
:::

## If your Dock is ever left hidden

From the repository:

```bash
make restore-dock
```

Or, with Eskele deleted entirely:

```bash
defaults delete com.apple.dock autohide-delay; defaults write com.apple.dock autohide -bool false; killall Dock
```

## A consequence worth knowing

Because Eskele restarts the Dock, **a badge that was already standing when Eskele launched is gone
from the new Dock's tile** until the application next changes it. This is what any `killall Dock`
does, and nothing can ask an application to re-publish its badge. See [Badges](../badges/).

## Why it can never be sandboxed

An application that controls the Dock cannot be sandboxed, and an application that is not sandboxed
cannot ship on the Mac App Store. That is the trade, and it is not one Eskele can get out of.
