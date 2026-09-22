---
title: Progress
description: Progress bars on cells — from files landing in a pinned folder, from media players, or from a command you write.
---

A cell that has something under way fills up, in whichever idiom the bar is already using:

| | |
|---|---|
| **Icons only** | A bar along the screen-facing edge, where the running dots go and instead of them. An application part-way through a track is obviously running, so the bar says everything the dots would and one thing more. |
| **Icons with labels** | The button fills from the left, the way a Windows taskbar button does, leaving the icon and the name alone. |

Hovering names what it is: "Music — 1:23 of 4:05", "Downloads — Copying big.zip".

Turn it on with *Show Progress*.

Three things can put a bar on a cell.

## Files landing in a pinned folder

Free, automatic, and **needs no permission**. Pin a folder — Downloads, say — and anything being
written into it shows on that cell.

:::note[The bar goes on the folder, not the app doing the writing]
That is not a design preference. macOS tells an observer which file is being written, how far along
it is and what kind of operation it is, but **never which application is doing it**. There is no way
to put a download on Safari's tile.

An application's own Dock progress *is* published as `AXProgressValue` — unlike a
[badge](../badges/) — but it says nothing about which file or which operation, so it would not tell
you what the folder cell already does.
:::

## Media progress

**Music, Spotify and VLC**, if you turn on *Media Progress*. Each one raises its own Automation
prompt the first time it is asked, and a player whose prompt you refuse simply shows no bar.

Asking is the only route left. The interface the system itself uses for this is private and has
needed an entitlement since macOS 15.4; on macOS 26 it loads, resolves every symbol, and then tells
an ordinary application nothing at all. The players' own scripting interfaces are public and exact,
so Eskele asks them — every few seconds, not every frame, working out the seconds in between on its
own.

**Only these three.** IINA, browsers and anything else are not supported and cannot be: a player has
to expose a scripting interface to be asked, and the system-wide Now Playing interface is the private
one that no longer answers.

### If a media bar does not appear

The answer is usually "that player is not running" or "Automation was refused":

```bash
open -n /Applications/Eskele.app --args --diagnose-progress
cat ~/Library/Application\ Support/Eskele/diagnose-progress.txt
```

Run it **while something is playing**, and through `open` rather than from a shell: macOS attributes
an Apple event to the process responsible for it, so a script run from a terminal proves what the
terminal is allowed to do, not what Eskele is.

## A command you supply

For anything else — a build, a render, a backup, a long job in something that is not scriptable:

```
~/Library/Application Support/Eskele/progress.json
```

The file opens with worked examples, and mirrors [`badges.json`](../badges/#badges-of-your-own) key
for key.

| Key | Meaning |
|---|---|
| `bundleID` | An application to draw on… |
| `path` | …or the absolute path of a folder or file already on the bar |
| `command` | Run through `/bin/sh` as you, with a 10-second timeout |
| `interval` | Seconds between runs. 5–3600, default 30 |

**How the number is read**: a value above 1 is a percentage and 0–1 is a fraction, so `1` means
finished. Add a `%` to be explicit.
