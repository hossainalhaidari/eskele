---
title: Permissions
description: What each macOS permission buys in Eskele, how to check what it actually has, and why a granted permission sometimes stops working.
---

**Nothing in the core bar needs a permission.** The bar itself, pinned applications, folder stacks,
launching, reordering, the Trash cell, auto-hide, the reveal and slot hot keys, the activity overlay,
folder progress, the clock and hiding the system Dock all work with nothing granted.

Four optional groups of features ask for something.

## What costs what

| Permission | What it buys |
|---|---|
| **Accessibility** | Window lists and counts, per-window buttons, full-screen detection, per-window indicators, "not responding", [real Dock badges](../badges/), per-display window filtering, the attention glow, and the right-<kbd>⌘</kbd> tap if you choose it as the Apps Menu key |
| **Screen Recording** | [Window previews](../windows/#window-previews) on hover. The only feature that asks for it, and it is off by default |
| **Automation → Finder** | Emptying the Trash. No public API exists |
| **Automation → loginwindow** | Sleep, Log Out, Restart and Shut Down. No public API exists, and the shell equivalents need root |
| **Automation → each player** | [Media progress](../progress/#media-progress) for Music, Spotify and VLC — one prompt per player, the first time each is asked |
| **Full Disk Access** *(optional)* | An exact Trash count with instant updates, instead of an estimate from directory metadata refreshed every two seconds |

Without a permission, the feature that needs it simply does nothing — it does not fail loudly and it
does not degrade anything else. Without Accessibility every running app shows a single dash and one
button, which is where the bar started.

## Checking what Eskele actually has

*Settings ▸ General* shows the live status of each permission.

From the command line, run the diagnostic **through `open`**, not from a shell:

```bash
open -n /Applications/Eskele.app --args --diagnose
cat ~/Library/Application\ Support/Eskele/diagnose.txt
```

:::caution[A permission check run from a terminal reports your terminal's permissions]
macOS attributes a permission to whatever launched the process. Running the binary directly from a
shell makes the check report what *Terminal* is allowed to do, so `--diagnose` from a prompt can say
"NOT granted" about a permission Eskele definitely has. Always go through `open`.
:::

## If a permission you granted stops working

macOS does not remember "this app" — it remembers a **code signature**.

An **ad-hoc** signature's identity is a hash of the binary, so every rebuild looks like a brand new
application and your grants stop applying, while still appearing ticked in System Settings.
`Scripts/build-app.sh` therefore signs with a Developer ID or Apple Development certificate when it
finds one, and warns when it has to fall back to ad-hoc.

If you have changed signing identity — including the first build after a certificate became
available — **remove Eskele from System Settings ▸ Privacy & Security ▸ Accessibility and add it back**.
The old entry refers to the old identity.

**Grant to the copy you actually run.** If you plan to use the build in `/Applications`, install it
there first and then grant. A grant made against the copy in `.build` does not follow it.

## Why the right-⌘ tap is the one shortcut that costs a permission

The Apps Menu offers three keys. <kbd>⌃Esc</kbd> and <kbd>⌥Space</kbd> are key *combinations*, which
Carbon registers globally without asking for anything.

A bare modifier is not a combination — there is no key press to register, only a flag going up and
coming down — and seeing that from outside the frontmost app needs Accessibility.

Polling the modifiers, the trick the <kbd>⇧⌥</kbd> [activity overlay](../activity/) uses to stay
permission-free, cannot work here: it would see <kbd>⌘</kbd> appear and disappear during
right-<kbd>⌘</kbd>S exactly as it does during a tap, because the S is invisible without the same
permission. Settings says as much beside the choice when the permission is missing.

## Everything else that needs no permission

Worth stating plainly, because these are the features that usually do cost something elsewhere:

- **"Starting" stripes.** The tile appears at `willLaunch` rather than `didLaunch`, and
  `isFinishedLaunching` is what clears it.
- **The <kbd>⇧⌥</kbd> activity overlay.** `proc_pid_rusage` answers for any process you own, and the
  modifiers are read directly rather than monitored.
- **The <kbd>⌃⌥</kbd> slot-number hint.** Same reason — the modifiers are read, not watched.
- **Folder progress.** macOS publishes file-operation progress to any observer.
- **Hiding the system Dock.** It is three `com.apple.dock` preferences and a restart of the Dock.
