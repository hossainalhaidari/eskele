---
title: Troubleshooting
description: The diagnostics Eskele can run on itself, and the problems that come up most.
---

## The one rule for every diagnostic

**Run them through `open`, never from a shell.**

macOS attributes a permission to whatever launched the process, so running the binary from a terminal
measures what *Terminal* is allowed to do. Every diagnostic below writes its report into
`~/Library/Application Support/Eskele/`.

```bash
open -n /Applications/Eskele.app --args --diagnose
cat ~/Library/Application\ Support/Eskele/diagnose.txt
```

| Flag | Reports |
|---|---|
| `--diagnose` | How the app is signed, and the live status of each permission |
| `--diagnose-windows` | What Accessibility says about every running app: windows, subroles, which are full-screen, which are on another Space and how they were reached, which are dialogs, which apps would be flagged as needing attention, which displays are in a full-screen space |
| `--diagnose-badges` | Every Dock tile, the raw `AXStatusLabel` on each, the bundle ID it resolved to, and which cells a command is overriding |
| `--diagnose-progress` | What each media player answered, and whether Automation was refused |

All four are **read-only**. `--diagnose-windows` changes nothing about the applications it inspects.

*Settings ▸ General* shows the same permission status as `--diagnose`, without the terminal.

---

## I cannot find the app after launching it

Eskele has **no Dock tile and no menu of its own**. Look for its icon in the **system menu bar**.

If you turned off *Show the menu bar icon*, the way back in is the **gear in the Apps Menu**, which
is locked on precisely so this cannot happen.

## A permission I granted stopped working

Almost always a signing-identity change. macOS remembers a code signature, not "this app", and an
ad-hoc signature's identity is a hash of the binary — so every rebuild looks like a new application
while still appearing ticked in System Settings.

Remove Eskele from *System Settings ▸ Privacy & Security ▸ Accessibility* and add it back. The full
explanation is in [Permissions](../permissions/#if-a-permission-you-granted-stops-working).

Also check you granted the copy you actually run: a grant against `.build/…/Eskele.app` does not
follow the copy in `/Applications`.

## My Dock is hidden and Eskele is gone

```bash
make restore-dock
```

Or, with Eskele deleted entirely:

```bash
defaults delete com.apple.dock autohide-delay; defaults write com.apple.dock autohide -bool false; killall Dock
```

## A badge is missing

Run `--diagnose-badges`. The two expected cases:

- **A badge that was already standing when Eskele launched** is gone from the new Dock's tile, because
  Eskele restarts the Dock to hide it. It comes back when the application next changes it.
- **A badge that is not a number** — the plain dot a few applications use — has no number to draw.

See [Badges](../badges/).

## A progress bar is missing

Run `--diagnose-progress` **while something is playing**. The answer is usually "that player is not
running" or "Automation was refused".

Only Music, Spotify and VLC can be asked; nothing else exposes a scriptable position. See
[Progress](../progress/#media-progress).

## Window buttons are wrong, or full screen behaves oddly

Run `--diagnose-windows`. That is the one to reach for when a window button, the full-screen
behaviour, or the attention glow is not doing what you expect.

The usual cause is missing Accessibility, which makes every application show a single dash and one
button. The second most usual is a window in a full-screen Space that Eskele has **never had in
view** — it can be counted and shown, but clicking it can only activate its application.

## The bar overlaps a full-screen window

*Reserve Screen Space* covers maximised windows only. macOS reserves nothing inside a native
full-screen space except the menu bar.

Set *In Full Screen* to *Reveal on hover* or *Hide*, or zoom windows instead of sending them
full-screen. See [Layout](../layout/#in-full-screen).

## A hot key does nothing

Most likely **another app has it**. macOS accepts a shortcut whether or not another app already
uses the same keys, so Eskele cannot warn you about that one — it checks only against macOS's own
shortcuts and its own others, and says so under the button when one of those clashes. Record a
different shortcut, or move the slot keys to another chord. See
[Recording a shortcut](../gestures/#recording-a-shortcut).

The reveal and slot hot keys are **off by default**, and the reveal key only exists while auto-hide
is on. The Apps Menu key can be set to *Off*. Check *Settings ▸ Behaviour*.

If you chose **Tap right ⌘**, it needs Accessibility, and it only counts when right <kbd>⌘</kbd> goes
down alone, nothing happens while it is down, and it comes back up within 0.4 seconds.

## The labels are invisible against my custom colour

Set *Appearance* to Light or Dark to match the colour you picked. Leaving it on system while choosing
a dark custom colour on a light system is how you get black on black. See
[Appearance](../appearance/#material-and-custom-colour).

## The Trash count looks wrong

Without Full Disk Access it is **inferred from directory metadata** — `~/.Trash` cannot be listed
otherwise. It agrees with Finder on APFS; on a volume laid out differently Eskele reports nothing
rather than guessing.

Grant Full Disk Access for an exact count and instant updates instead of a two-second poll.
