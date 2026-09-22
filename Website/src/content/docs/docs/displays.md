---
title: Displays and order
description: The three multi-display modes, and how the applications are sorted along the bar.
---

## Displays

Three choices, on the menu bar item under *Displays*:

| | |
|---|---|
| **All Displays** | The same bar on every one. The default. |
| **Each Display's Own Windows** | A bar on every display, but each lists only the applications with a window on that display. |
| **Main Display Only** | A bar on the display with the menu bar, and nowhere else. |

In the middle mode, your **pinned shortcuts, the Apps Menu, the Trash and the clock stay on every
bar** — a shortcut is not *on* a display the way a window is, and a second bar without a launcher on
it would be a worse bar. So does anything with no window open.

That mode needs Accessibility: without it Eskele cannot see which windows an application has, let
alone where they are, so every display shows the same bar — which is what *All Displays* does anyway.
It also asks each window where it is, which is one more Accessibility call per window, so Eskele only
makes that call in this mode and only when there is more than one display to tell apart.

## Order

*Order* decides how the applications run along the bar.

| | |
|---|---|
| **As Arranged** | The default, and the only one that reads `layout.json`'s order as an instruction. |
| **By Name** | Sorted the way the Finder sorts, so `App 10` follows `App 9` rather than `App 1`. |
| **By Launch Time** | Oldest first, which makes the bar a history of the session. |

The two automatic orders use the stored order as a **tie-break**, so equal items never swap places
between rebuilds. Applications that are not running have no launch time, so under *By Launch Time*
they keep their stored order and follow the ones that do.

### Two things change while the order is not yours

**Separators are hidden.** A divider earns its place by sitting between two things you put on either
side of it, and once the machine is choosing the order it is a line between two arbitrary neighbours.
They stay in `layout.json` and come back with *As Arranged*.

**Dragging an item switches the order back to As Arranged.** Arranging something by hand is a
statement that you want it arranged by hand; without that, the drop would be saved and then
immediately sorted away, which looks like the bar refusing to move.

Only the applications are affected. Pinned folders and files keep their place after them, and the
Trash keeps its end.
