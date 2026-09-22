---
title: Windows
description: Window indicators, per-window buttons, windows in another Space, hover previews, status stripes, and the attention glow.
---

Everything on this page needs **Accessibility**, except where it says otherwise. Without it, every
running application shows a single dash and one button.

## Indicators

Applications with several windows show **one dash per window, up to four**.

Hovering a button names the window it is showing — the page title rather than the application's name
again — or the application's name when nothing is open.

## The window list

Right-click a running application to list its windows. Minimised ones are indented, and each offers:

| | |
|---|---|
| **Close** | Presses the window's own close button, so an unsaved document still gets to put its sheet up |
| **Minimise / Restore** | As you would expect |
| **Quit** | The whole application |

Close is disabled for a window on another Space that was reached through a menu item, because a menu
item has no close button to press.

## A button per window

In full-width labelled mode each window gets **its own button, titled with the window's own title** —
so a Safari button reads the page name rather than "Safari".

Turn it off with *Separate Windows* in the *Size & Style* menu to go back to one button per
application.

Window buttons reorder within their own application, and move the whole application when dragged
clear of it.

## Windows in a full-screen Space

These are a special case, because macOS's Accessibility API only exposes the windows of the Space you
are currently on. Eskele reaches them **four ways, best first**:

1. An application's **focused or main window** comes back from Accessibility even when it is
   elsewhere.
2. The handle of any **full-screen window Eskele has already seen** stays usable after the window
   leaves its Space.
3. The application's own **Window menu** lists windows Accessibility will not, with their real
   titles, and pressing that item crosses the Space. This is the one that works from a cold start.
4. Anything still unaccounted for is **counted through the window server** and shown as a button
   named after the application.

Only that last case is approximate.

:::note[A window on another Space cannot be *found* directly]
The gap is only a window Eskele has never had in view. That one can be counted and shown, but
clicking it can only activate its application — which is all the real Dock manages too.
:::

## Freshness

Window changes are picked up from **Accessibility notifications rather than polling**, so opening,
closing or renaming a window updates the bar in roughly 200 ms.

## Window previews

*Window Previews* puts a **live thumbnail above the hover label** — the window itself for a window
button, and the application's focused window for an application cell, which is the same window the
label already names.

This is the **only feature in Eskele that costs Screen Recording**, which is why it is off by default.
Without the permission it does nothing at all and the label stays exactly what it has always been:
the window's title, in text. Nothing else in the app changes, and no other feature starts needing it.

Three details:

- The capture is asked for only **after the hover delay has elapsed**, so sweeping along a full-width
  bar never captures anything.
- The text appears the moment the delay is up and the **thumbnail fills in behind it**, so the label
  stays as quick as it was. A capture stands in for the live window for two seconds, which makes
  re-hovering the same cell instant.
- **Off-screen windows are captured too.** A minimised window, or one on another Space, is exactly the
  case where a picture tells you something the bar cannot.

It uses ScreenCaptureKit rather than the older `CGWindowListCreateImage`, which is deprecated and,
since Sonoma, hands back a placeholder for windows it will not give you.

## Applications that are starting or stuck

Two states get diagonal hatching across the cell, in both item styles:

| | |
|---|---|
| **Starting** | Neutral stripes, from the moment the application appears until it finishes launching |
| **Not responding** | Red stripes |

The hatching is drawn over the icon but **under the label**, so an application's name and window
title stay readable — they are information, and trading them away to report a status the icon can
carry is a poor exchange. Hovering says which it is in words, because a stripe colour is a convention
you have to have learned.

**Starting costs no permission.** The application appears on the bar at `willLaunch` rather than
`didLaunch`, and `isFinishedLaunching` is what clears it. An application that never reports finishing
gives up its stripes after 20 seconds rather than wearing them forever.

**Not responding needs Accessibility.** An AX read is a synchronous message to the application's own
event loop, so an application that does not answer within the messaging timeout is one that is not
pumping it — which is what "not responding" means. It takes **two missed reads in a row** to be
believed: one is not evidence, because a machine under load can starve a healthy application of a
120 ms window, and a tile that flickered at every hiccup is one nobody would trust.

Without the permission every read fails for a reason that says nothing about the application, so
nothing is ever flagged.

uBar has a third stripe, *restorable*, in blue. It has no counterpart here — Eskele already dims a
hidden application and draws one dash per window, so the state it would report is one the bar shows
already.

## Applications that need attention

A bouncing Dock icon is private to the Dock process; nothing can observe it.

What Eskele *can* see, given Accessibility, is the thing bouncing usually accompanies — an
application putting a **dialog or a sheet** in front of you while you were working somewhere else.
Those cells glow amber until you visit the application. Turn it off with *Highlight Attention*.

An application that only bounces, without putting anything up, will not light up.

## Diagnosing

When a window button, the full-screen behaviour, or the attention glow is not doing what you expect:

```bash
open -n /Applications/Eskele.app --args --diagnose-windows
cat ~/Library/Application\ Support/Eskele/diagnose-windows.txt
```

It reports what Accessibility says about every running application: its windows, their subroles,
which are full-screen, which are on another Space and how they were reached, which are dialogs, which
applications would be flagged as needing attention, and which displays the bar currently considers to
be in a full-screen space.

It is **read-only** — it changes nothing about the applications it inspects. Run it through `open`
rather than from a shell, or you will measure your terminal's permissions instead of Eskele's.
