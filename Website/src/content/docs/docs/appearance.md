---
title: Appearance
description: Light and dark, material and custom colour, custom icons, and renaming cells.
---

## Light and dark

*Appearance* pins the bar to **Light** or **Dark** instead of following the system — a light menu bar
with a dark strip beneath it, or the reverse.

It is an `NSAppearance` on the panel, so the material, the labels, the icons and the hover label all
move together. That matters for the next section: **setting a colour and leaving the text to the
system is how you get black on black.**

## Material and custom colour

*Material ▸ Custom Colour* replaces the blur with a flat colour and an opacity of your choosing.

The two are exclusive on purpose. A colour drawn *over* a material is neither one nor the other: pick
80% black and you would get 80% black over a blur of the desktop, which is darker than you asked for
and moves when the wallpaper does.

*Appearance* still decides whether the labels are drawn light or dark, so **set it to match the
colour you picked**.

## Custom icons

Icons come from a folder, not a picker. Open *Settings ▸ Behaviour ▸ Custom Icons Folder…* and drop an
image in, named after the cell it replaces:

```
com.apple.Safari.png      an app, by its bundle identifier
trash.png                 the Trash
apps-menu.png             the Apps Menu button
```

- Capitals do not matter.
- PNG, ICNS, TIFF, JPEG, HEIC, PDF and SVG all work. A key with more than one file takes the first of
  those in that order.
- The folder is watched, so changes show up straight away, and deleting a file puts the real icon
  back.
- A file that is not a readable image is ignored rather than leaving a blank cell, so a stray note in
  the folder does no harm.

To find an application's identifier:

```bash
osascript -e 'id of app "Safari"'
```

Pinned folders and files are **not** listed there, because a path is not a filename. They do not need
to be: Finder's own *Get Info ▸ paste an icon* already overrides those, and the bar draws what Finder
reports.

## Renaming a cell

Right-click any cell and choose *Rename*. It changes the label on the bar and the hover title, and it
is stored with the item, so it survives a restart. Empty the field to go back to the real name, or
use *Reset Name*.

Two details:

- **Renaming an application that is not pinned pins it**, in the place it already occupies. A name
  that disappeared when the app quit would not be worth typing.
- **Window buttons have no Rename.** The name belongs to the application, and those cells are showing
  a window's title.

## Padding

*Settings ▸ Appearance* controls the padding around and between cells. It is independent of the
[designs](../layout/#designs) — picking one leaves your padding as you had it.
