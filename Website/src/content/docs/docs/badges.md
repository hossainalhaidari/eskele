---
title: Badges
description: Real Dock badges read off the Dock's own tiles, and how to supply your own from a command.
---

**Real badges, read from the Dock.** Mail's unread count, Messages, App Store updates — whatever
macOS is already drawing on a Dock tile is drawn on the corresponding cell of the bar, within about
two seconds, with nothing to configure.

Turn them off with *Show Badges*.

## How that works

No public API hands one application another application's badge. But the Dock is an ordinary
application, and its tiles are ordinary Accessibility elements: each carries an `AXStatusLabel`
holding exactly the string the Dock is drawing.

That is the same [Accessibility](../permissions/) permission the window counts already ask for — no
Screen Recording, no Full Disk Access. Badge changes come with no notification, so the tiles are
polled; a full sweep of every tile measures under two milliseconds.

## Two things it will not show

**A badge that is not a number.** The plain dot a few applications use has no number to draw, and is
treated as no badge.

**A count that was already standing when Eskele launched.** A badge lives in the Dock process, and
Eskele restarts the Dock in order to hide it — so a count that was up before Eskele started is gone
from the new Dock's tile until the application next changes it. For mail, that is the next message.
This is what any `killall Dock` does, and nothing can ask an application to re-publish its badge.

## The Trash

The Trash badges itself with the number of items it holds.

Without Full Disk Access that count is **inferred from the directory's own metadata** — `~/.Trash`
cannot be listed otherwise. It agrees with Finder on APFS; on a volume laid out differently Eskele
reports nothing rather than guessing. Grant Full Disk Access for an exact count and instant updates
instead of a two-second poll.

## Badges of your own

A number the Dock does not carry — one an application never badges, or one you want counted
differently — comes from a command you name:

```
~/Library/Application Support/Eskele/badges.json
```

That file is created on first run, empty, with worked examples inside it:

```json
{
  "sources": [
    {
      "bundleID": "com.apple.mail",
      "command": "osascript -e 'tell application \"Mail\" to get unread count of inbox'",
      "interval": 30
    }
  ]
}
```

| Key | Meaning |
|---|---|
| `bundleID` | The application to badge. Use `"trash"` to override the Trash's own count. |
| `command` | Run through `/bin/sh` as you, with a 10-second timeout. |
| `interval` | Seconds between runs. 5–3600, default 30. |

**The first number in the command's output becomes the badge.** No output, a failure, or a zero means
no badge, and the application's real Dock badge is drawn instead.

**A command that does answer wins its cell**, so it overrides the real badge as well as supplying one.
The example above counts the unified inbox, which is not always what Mail itself badges.

Nothing runs until you put something in the file.

## Where badges are drawn

On the icon's top corner in both **Icons Only** and **Icons with Labels**, and repeated in the
tooltip — at Small scale the capsule is only about 12pt tall.

They sit diagonally opposite the [⌃⌥ slot-number chip](../gestures/#slot-hot-keys), so the two never
collide.

## If a badge does not appear

Ask the application what the Dock told it — through `open` rather than from a shell, because macOS
attributes Accessibility to whatever launched the process:

```bash
open -n /Applications/Eskele.app --args --diagnose-badges
cat ~/Library/Application\ Support/Eskele/diagnose-badges.txt
```

It prints every Dock tile, the raw `AXStatusLabel` on each, the bundle ID it resolved to, and which
cells a command is overriding.
