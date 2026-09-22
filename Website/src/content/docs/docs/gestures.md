---
title: Clicks and shortcuts
description: The modifier grammar, drag and drop, the Finder service, and every global key.
---

## Clicking

| Gesture | Effect |
|---|---|
| **Click** | Launch or activate. Clicking the application you are already in hides it. |
| **⌘-click** | Show in Finder |
| **⌥-click** | Hide the application, or bring it back |
| **⌥⌘-click** | Show this application and hide every other one |
| **⇧-click** | Quit the application — or, on a window button, close that window |
| **⇧⌘-click** | Force-quit the application and start it again |
| **Middle-click** | The same as ⇧-click |
| **⌃-click** | The context menu, as everywhere else in macOS |

The combinations are uBar's, so the muscle memory carries across.

**A gesture that means nothing on the cell under the pointer does nothing.** ⇧-clicking a folder will
not open it, and ⌘-clicking the Apps Menu has nowhere to go. Only ⌘-click reaches a folder, a file or
the Trash.

### Clicking a running application

Clicking an application you are already in **steps to its next window** rather than hiding it, when
it has more than one.

Clicking a running application that has **no windows open** — or whose windows are all minimised,
which on macOS still leaves the application running — opens one, the way the real Dock does. It asks
LaunchServices to open the application rather than merely activating it, which is what carries the
reopen event.

## Dragging

| | |
|---|---|
| **Drag** | Reorder |
| **Drag off the bar** | Unpin |
| **Drag an app in from Finder** | Pin it |
| **⌘ while dragging** | Move-only: the item cannot be dropped off the bar by accident |
| **Drop files on an app** | Open them with it |
| **Drop files on the Trash** | Trash them |

**Everything in the bar reorders, in both item styles.** Pinned items keep their order on disk.
Running applications that are not pinned get a position for the session — drop one among the other
running applications and it stays there; drop it into the pinned run and it gets pinned, which is
what that gesture means. Window buttons reorder within their own application, and move the whole
application when dragged clear of it.

Hold **⌘ while dragging** for move-only. That matters when you are rearranging a full-width bar and
the pointer keeps leaving it. A press that never became a drag is just a click, so ⌘-drag and
⌘-click never collide.

## From the Finder

Finder's **Services** menu has an **Add to Eskele** item: right-click any application, folder or file
and it is pinned, without needing the bar visible or on the same screen. It takes several items at
once, and says so rather than silently doing nothing when they are all pinned already.

## Global keys

| Key | Effect | Default |
|---|---|---|
| **⌃Esc** | Open or close the [Apps Menu](../apps-menu/) from anywhere — or a key you record | On |
| **⌃⌥⇥** | [Move focus to the bar](#from-the-keyboard-and-with-voiceover), for the arrow keys and VoiceOver — or a key you record | On |
| **⌃⌥D** | Show or hide an auto-hiding bar — or a key you record | Off |
| **⌃⌥1…0** | Activate the first ten items on the bar — or ⌃⌘, ⌃⇧, ⌃⌥⌘ | Off |
| **⇧⌥** *(held)* | The [activity overlay](../activity/) | On |
| **⌃⌥** *(held)* | Number the first ten items — whichever chord the slot keys use | — |

### Slot hot keys

<kbd>⌃⌥1</kbd> is the first item on the bar and <kbd>⌃⌥0</kbd> the tenth. The Apps Menu and any
separators are **not counted**, so the numbers mean the same thing whether or not you have those
turned on.

They are **off by default**: ten global combinations are far likelier to collide with something you
already have bound than one is.

**Hold ⌃⌥ and the bar tells you which is which.** Each of those ten cells takes a small numbered chip
on the icon's inward bottom corner, diagonally opposite the badge so the two never collide. It is a
corner rather than the middle of the icon because the question you are asking is "which number is
Safari?" — a chip big enough to read comfortably is also big enough to hide the icon that makes the
number worth knowing.

The hint needs no permission: the modifiers are read directly rather than monitored, since watching
key events would need Accessibility and the hot keys themselves do not.

If <kbd>⌃⌥</kbd> and a number is already yours, *Settings ▸ Behaviour ▸ Keyboard ▸ Keys* moves the ten
to <kbd>⌃⌘</kbd>, <kbd>⌃⇧</kbd> or <kbd>⌃⌥⌘</kbd>, and the numbers then appear while *that* chord is
held. Every choice includes <kbd>⌃</kbd>: you hold the chord while looking at the bar, often with the
pointer on it, and <kbd>⌃</kbd>-click is only ever the context menu. <kbd>⌥⌘</kbd> was the obvious
other candidate, and <kbd>⌥⌘</kbd>-click is Show Only This.

### From the keyboard, and with VoiceOver

<kbd>⌃⌥⇥</kbd> moves focus to the bar — what macOS's own <kbd>⌃F3</kbd>, *Move focus to the Dock*,
does for the Dock that Eskele hides. It is on by default, under *Settings ▸ Behaviour ▸ Keyboard*.

| Key | Effect |
|---|---|
| <kbd>←</kbd> <kbd>→</kbd> (<kbd>↑</kbd> <kbd>↓</kbd> on a side bar), <kbd>⇥</kbd> <kbd>⇧⇥</kbd> | Move along the bar. Separators are skipped; the Apps Menu is not |
| <kbd>⌘←</kbd> <kbd>⌘→</kbd>, <kbd>Home</kbd>, <kbd>End</kbd> | The first or last item |
| <kbd>Return</kbd> or <kbd>Space</kbd> | The same as clicking it |
| <kbd>⌘Return</kbd>, <kbd>⌥Return</kbd>, <kbd>⇧Return</kbd>… | The same as ⌘-, ⌥- or ⇧-clicking it |
| The arrow pointing into the screen, or <kbd>⌃Return</kbd> | Its context menu |
| Typing a name | Jumps to the item it starts with |
| <kbd>Esc</kbd>, or <kbd>⌃⌥⇥</kbd> again | Back to the app you were in |

Focus starts on the app you were in, and the item it is on gets a ring and its hover label. Opening
something hands the keyboard to it; quitting or hiding something leaves it on the bar. While the bar
has focus Eskele is the active app, as it is while the Apps Menu is open.

**VoiceOver reads the bar as a list and each item as a button** — its name, then what the bar draws
about it: "Safari, running, active, 3 windows, badge 2". A folder and the Apps Menu are menu buttons.
VoiceOver's press and context-menu commands work on every item, and its actions for an item include
every modifier-click, among them Show Only This and the force relaunch, which are on no menu.

To use <kbd>⌃F3</kbd> itself, turn off *Move focus to the Dock* under *System Settings ▸ Keyboard ▸
Keyboard Shortcuts ▸ Keyboard*, then record it here.

### Recording a shortcut

The reveal key, the move-focus key and the Apps Menu's *Custom Shortcut* take any combination you
record: click the button beside them and press the keys. While it listens Eskele's own shortcuts are switched off, so
you can press the one already assigned to record it again. Escape, or a click anywhere else, leaves
things as they were.

Some combinations are refused as you press them, with the reason under the button, and it keeps
listening for another try:

- **Without <kbd>⌃</kbd> or <kbd>⌘</kbd>** it is a key you type with — <kbd>⌥E</kbd> is how an é is
  typed on half the world's keyboards.
- **<kbd>⌘</kbd> alone, or <kbd>⌘⇧</kbd>**, is the front app's own menu shortcut.
- **<kbd>⌃</kbd> and a single letter** moves the cursor in every text field.
- **One of macOS's own shortcuts** that is switched on — <kbd>⌘Space</kbd>, <kbd>⌃Space</kbd>, the
  screenshot keys. Turn it off under *System Settings ▸ Keyboard ▸ Keyboard Shortcuts* first.
- **One of Eskele's other shortcuts.**

Function keys are always accepted.

What cannot be checked is **another app's** shortcut: macOS accepts a combination whether or not
another app already holds it, and nothing lists what other apps have registered. If a shortcut you
recorded does nothing, another app has it — record a different one.

## The menu bar item

Everything is on it:

| Control | Effect |
|---|---|
| Settings… | The full preferences window |
| Hide Menu Bar Icon | Take Eskele out of the menu bar; the Apps Menu's gear is then the way back |
| Position | Left, Bottom or Right edge |
| Size & Style | Scale, rows, span, alignment, and Icons Only vs Icons with Labels |
| Displays | All displays, only their own windows, or just the one with the menu bar |
| Order | As Arranged, By Name or By Launch Time |
| Window Previews | A thumbnail of the window in the hover label |
| Auto-hide the Bar | Slide it away until the pointer reaches the edge |
| Reveal Hot Key | ⌃⌥D shows or hides the bar from anywhere |
| Slot Hot Keys | ⌃⌥1…0 activate the first ten items |
| Activity Overlay | Hold ⇧⌥ to read each app's processor and memory use |
| Apps Menu | Show the launcher button, what it lists, and the key that opens it |
| In Full Screen | Always show, reveal on hover, or hide |
| Show Running Apps | Include running applications that are not pinned |
| Show Trash | Trash cell on or off |
| Show Clock | A clock at the far end of the bar |
| Show Badges | Number badges on the cells that have one |
| Rename | Right-click any cell: give it the name you want, or reset it |
| Show Progress | A progress bar across a cell that has something under way |
| Media Progress | Ask Music, Spotify and VLC where they are in the track |
| Highlight Attention | Glow a cell when its app puts a dialog up behind your back |
| Group Pinned Apps | Keep not-running pins together at the leading end, in labelled mode |
| Add Separator | Insert a divider, then drag it where you want it |
| Hide System Dock | Suppress the real Dock |
| Reserve Screen Space | Make maximised windows stop short of the bar |
| Restore System Dock | Undo that, immediately |

### Hiding the menu bar icon

*General ▸ Show the menu bar icon* takes Eskele out of the menu bar for people who keep theirs
uncluttered. The Apps Menu's gear then becomes the way into Settings, so **the two cannot both be
turned off**: whichever one is left is locked on until you bring the other back. Editing
`settings.json` past that check just puts the icon back on the next launch.
