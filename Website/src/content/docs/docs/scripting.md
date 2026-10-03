---
title: Scripting
description: Drive the bar from Shortcuts, Raycast, Alfred or a shell script, with eskele:// URLs and Shortcuts actions.
---

Two routes, one set of commands: **`eskele://` URLs**, which anything that can open a link can send,
and **Shortcuts actions**, which also reach Spotlight and Siri. Both run the same code, so they
cannot come to mean different things.

## URLs

| URL | Effect |
|---|---|
| `eskele://edge/left` | Move the bar to the `left`, `bottom` or `right` edge |
| `eskele://autohide/on` | Auto-hide `on`, `off`, or `toggle` — which is what `eskele://autohide` alone does |
| `eskele://design/classic` | Apply the `dock`, `classic`, `unity` or `custom` design |
| `eskele://reveal` | Show or hide an auto-hiding bar, as the reveal shortcut does |
| `eskele://apps-menu` | Open the Apps Menu, or close it |
| `eskele://focus` | Move the keyboard to the bar, as <kbd>⌃⌥⇥</kbd> does |
| `eskele://settings` | Open Settings |
| `eskele://pin?path=~/Downloads` | Pin a file, folder or application by path |
| `eskele://pin?app=com.apple.Safari` | Pin an application by its bundle identifier, wherever it is installed |
| `eskele://unpin?app=com.apple.Safari` | Unpin, by `path` or `app` |

From a shell:

```bash
open eskele://edge/right
```

`pin` and `unpin` take several items at once — `eskele://pin?app=com.apple.mail&path=~/Projects` —
and a path must be absolute or start with `~`, since a URL carries no folder to be relative to.
Spaces in a path are written `%20`.

**Your keyboard stays where it was.** macOS brings Eskele forward to hand it a URL; once the command
has run, the app you were in gets the front back. Only `apps-menu`, `focus` and `settings`, which are
for the keyboard, keep it — and give it back when you close them.

**A URL Eskele does not understand does nothing.** It is noted in the system log rather than shown,
since the sender is usually a script with nobody watching.

### What a URL cannot do

Any web page can open an `eskele://` link. Your browser asks first, but a person clicking *Allow* may
not read the link — so nothing a URL can do quits an application, empties the Trash, sleeps the Mac
or touches the [system Dock](../system-dock/). The worst a hostile link can do is move the bar or
pin something, and both are one click from undone.

## Shortcuts

Eskele's actions are under **Eskele** in the Shortcuts app's action list:

| Action | Takes |
|---|---|
| **Move the Bar** | An edge |
| **Set Auto-Hide** | On, Off or Toggle |
| **Apply Design** | Dock, Classic, Unity or Custom |
| **Show or Hide the Bar** | — |
| **Open the Apps Menu** | — |
| **Move Focus to the Bar** | — |

They run with Eskele in the background, so nothing comes forward that you did not ask for. There is
no action for pinning: a file Shortcuts hands over can be a copy in a temporary folder rather than
the file itself. Use **Open URLs** with an `eskele://pin` URL instead, which names the real thing.

:::note[Building Eskele yourself]
Shortcuts learns an app's actions from metadata that Xcode's tools write into the app.
`make run` writes it when Xcode is installed; with only the Command Line Tools it warns and the
actions are missing, while everything else, URLs included, works.
:::
