---
title: Layout and designs
description: Edges, scale, rows, span, alignment, item style, and the three one-click designs Eskele ships with.
---

Everything on this page is on the menu bar item, under *Position* and *Size & Style*, and in
*Settings ▸ Bar*.

## Designs

The top of *Settings ▸ Appearance* has three one-click starting points, drawn as miniatures:

| Design | Shape |
|---|---|
| **Dock** | Big, on the bottom edge, only as wide as its icons, centred. The default. |
| **Classic** | A full-width taskbar across the bottom at Small scale, labelled buttons from the left. |
| **Unity** | A full-height column of big icons down the left edge, from the top. |

Each sets position, scale, span, item style and alignment together, and turns on the Trash and the
Apps Menu. Everything else — padding, material, auto-hide, badges — is left as you had it, so a
design is a **starting point rather than a reset**.

Change one of the settings a design owns and none of the three shows as selected any more, because
the bar is no longer one of them.

## Position

Left, bottom or right. On a left or right bar the rows become columns; nothing else changes.

## Scale

| | |
|---|---|
| **Small** | 32pt. |
| **Big** | 48pt, half again as thick, for larger targets. The default. |

## Rows

The bar stacks up to five rows, and the items spread across them. The point is a full-width taskbar
with thirty windows on it: one row narrows the buttons, then drops their labels, and then simply runs
out; a second row keeps the names readable. It works on a bar that hugs its icons too, where two rows
make a compact block half as long and twice as tall.

Two behaviours are worth knowing:

- **The bar is always as many rows thick as you asked for**, whether or not the items need them all,
  and the items spread evenly across them rather than filling the first and leaving the rest empty. A
  bar that grew a row when an app opened would resize under your pointer — and with [Reserve Screen
  Space](../system-dock/#reserve-screen-space) on, it would re-park the system Dock every time.
- **When there is more than will fit**, every row is squeezed alike, rather than the first staying
  comfortable and the last taking the crush.

## Span and alignment

*Fit to icons* makes the bar only as long as its contents; *Full width* stretches it edge to edge.
Alignment decides where the items sit inside it — leading, centred or trailing.

In full-width mode the Trash moves to the far end of the bar — right when horizontal, bottom when
vertical — instead of sitting beside the applications.

## Item style

### Icons Only

The dock idiom. Running applications carry dots underneath — one per window, up to four — and
[progress](../progress/) replaces those dots with a bar along the screen-facing edge.

### Icons with Labels

The taskbar idiom: each running application becomes a button showing its name.

In full-width mode every button is the same width — 140pt by default, 210pt on a Big bar, adjustable
in Settings — and long names are truncated with an ellipsis. When the bar hugs its icons instead,
buttons size to their text up to that same width.

As the bar fills up the buttons narrow **together, equally**, and when there is no room left for text
they collapse back to plain icons.

Horizontal bars only. A side bar is one icon wide, with nowhere to put a label.

### Separate Windows

In full-width labelled mode each window gets **its own button, titled with the window's own title** —
so a Safari button reads the page name rather than "Safari". Turn it off with *Separate Windows* in
the *Size & Style* menu to go back to one button per application. See [Windows](../windows/).

### Group Pinned Apps

A pinned application that is **not running** is a shortcut rather than a task, so in labelled mode
those are lifted out of the run of buttons into a compact tray at the leading end, with a divider
after it. Launch one and it joins the buttons like anything else.

Turn it off with *Group Pinned Apps* if you would rather they stayed where you put them. Icons-only
mode is unaffected — there, a launcher and a task look the same anyway.

## Separators

*Add Separator* inserts a divider; drag it where you want it. Separators are hidden while the
[order](../displays/#order) is not *As Arranged*, because a divider earns its place by sitting
between two things you put on either side of it. They stay in `layout.json` and come back with *As
Arranged*.

## Auto-hide

*Auto-hide the Bar* slides it away until the pointer reaches the edge. Turn on *Reveal with a
shortcut* and <kbd>⌃⌥D</kbd> — or a key you [record](../gestures/#recording-a-shortcut) — shows or
hides it from anywhere.

## In full screen

Three choices for what happens when the frontmost window is in a native full-screen space:

| | |
|---|---|
| **Always show** | The bar floats over the full-screen window. |
| **Reveal on hover** | It slides away until the pointer reaches the edge. |
| **Hide** | It stays away. |

This needs Accessibility — there is no reliable permission-free way to tell a full-screen space from
a window merely sized to fill the screen. Without it the setting behaves as *Always show*.

The bar **cannot reserve space inside a full-screen space**; macOS reserves nothing there except for
the menu bar. Zoom windows instead of sending them full-screen if you never want the bar to overlap.
