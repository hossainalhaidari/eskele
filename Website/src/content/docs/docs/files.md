---
title: Files and configuration
description: Where Eskele keeps its settings, layout, badge and progress commands, custom icons, and Dock backup.
---

Everything Eskele writes lives in one directory:

```
~/Library/Application Support/Eskele/
  settings.json      edge, displays, toggles
  layout.json        pinned items (bookmark + bundle ID)
  badges.json        the commands behind any badge the Dock does not carry
  progress.json      commands that put a progress bar on a cell
  Icons/             images that replace a cell's icon, named after the cell
  dock-backup.json   your Dock preferences as they were before Eskele touched them
```

Plus the diagnostics, written on demand:

```
  diagnose.txt           --diagnose
  diagnose-windows.txt   --diagnose-windows
  diagnose-badges.txt    --diagnose-badges
  diagnose-progress.txt  --diagnose-progress
```

## settings.json

Every toggle, edge, scale and choice. It is hand-editable, though *Settings* is easier and it is
rewritten whenever you change something there.

One value cannot be edited past its check: turning off **both** the menu bar icon and the Apps Menu
would leave no way back into Settings, so whichever one is left is locked on. Editing the file past
that just puts the icon back on the next launch.

### Exporting, importing and restoring defaults

*Settings ▸ General ▸ Transfer and Reset* does the three things you would otherwise do to this file by
hand:

- **Export Settings…** saves a copy — the same bytes as `settings.json` — anywhere you choose.
- **Import Settings…** reads one back, from this Mac or another. A file with a bad value loses just
  that value, and a file that is not settings at all — `layout.json`, say — is refused rather than
  read as a set of defaults.
- **Restore Defaults…** asks first, then puts every setting back to how a new installation has it.

Importing and restoring defaults both leave the [System Dock](../system-dock/) choices as they are on
this Mac, and neither touches the other files here: pinned items and their names, custom icons, badge
and progress sources. A reset keeps your Custom design under its tile, so the layout you had is one
click away.

## layout.json

The pinned items, in order, each as a security-scoped bookmark plus a bundle identifier. The
bookmark is what lets a pinned file survive being moved.

This file's order is read as an instruction only under *Order ▸ As Arranged*. Under the other two it
is a tie-break, so equal items never swap places between rebuilds. See
[Order](../displays/#order).

## badges.json and progress.json

Both are created on first run, empty, with worked examples inside them. They mirror each other key
for key. See [Badges](../badges/#badges-of-your-own) and
[Progress](../progress/#a-command-you-supply).

Commands in both run through `/bin/sh` as you, with a 10-second timeout, no more often than
`interval` seconds. **Nothing runs until you put something in the file.**

## Icons/

Images that replace a cell's icon, named after the cell — `com.apple.Safari.png`, `trash.png`,
`apps-menu.png`. The folder is watched, so a change shows up straight away. See
[Appearance](../appearance/#custom-icons).

## dock-backup.json

Your `com.apple.dock` preferences as they were before Eskele touched them. Written before anything is
changed and read back when Eskele quits — including after a crash, on the next launch. See
[Hiding the system Dock](../system-dock/).
