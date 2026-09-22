---
title: The Apps Menu
description: The launcher at the leading end of the bar — its lists, its search, its keyboard shortcut, and the System Settings panes and power actions it also reaches.
---

The **Apps Menu** is the launcher at the leading end of the bar. Click it for a list of:

| | |
|---|---|
| **Favourites** | The applications pinned to the bar |
| **All Apps** | Everything in your Applications folders, grouped by category |
| **Recent Apps** | What you have used most recently, tracked from first launch |

It opens correctly whichever edge the bar is on. Right-click the button to switch lists or hide it.

## Searching

The search field is focused the moment the launcher opens, so you can type without reaching for the
mouse.

- Matches are **ranked**.
- **Initials work** — `vsc` finds Visual Studio Code.
- <kbd>↑</kbd> and <kbd>↓</kbd> move through the results.
- <kbd>Return</kbd> launches.
- <kbd>Escape</kbd> clears the search, and then closes.

The gear to the right of the field opens Settings.

## Opening it from anywhere

**<kbd>⌃Esc</kbd> opens it from anywhere**, which is the Windows key's job: press it and start
typing. Press it again to close. It is on out of the box.

*Settings ▸ Behaviour ▸ Apps Menu ▸ Shortcut* offers three, one you record, or none:

| | |
|---|---|
| **⌃Esc** | The default. macOS does not use it, and on Windows it is the Start-menu shortcut, so it already means this. Escape has no text-input role, so it shadows nothing. |
| **⌥Space** | What most launchers use, so it is the one you may already reach for. It does take over the non-breaking space that ⌥Space types into a text field. |
| **Tap right ⌘** | The closest thing to a real Windows key: a lone modifier macOS assigns nothing, tapped and released on its own. Needs [Accessibility](../permissions/#why-the-right--tap-is-the-one-shortcut-that-costs-a-permission). |
| **Custom Shortcut** | Any combination you record, for when the others are taken. See [Recording a shortcut](../gestures/#recording-a-shortcut). |

macOS leaves less room here than it looks. <kbd>⌃Space</kbd> and <kbd>⌃⌥Space</kbd> are input-source
switching, <kbd>⌘Space</kbd> is Spotlight and <kbd>⌥⌘Space</kbd> is Finder search — all on by
default. The two combinations above are what is left.

A right-⌘ tap only counts if right <kbd>⌘</kbd> goes down alone, nothing happens while it is down,
and it comes back up within 0.4 seconds. So right-⌘S, right-⌘-click and a held <kbd>⌘</kbd> all leave
the launcher shut.

## More than applications

*Include System Items* — on by default — adds two sections after the applications in **All Apps**:

| Section | What it holds |
|---|---|
| **System Settings** | Every pane System Settings shows, opened straight to it |
| **Folders** | Home, Desktop, Documents, Downloads, Pictures, Music, Movies, iCloud Drive, Applications, Utilities |

They are appended to the applications rather than given a list of their own, so **a single search
reaches all of it**: type `displ` for Displays, `downl` for Downloads, `restart` to restart. Browsing
is unaffected — both sort after every application category, so the list still opens on apps.

### How the panes are found

The panes are **enumerated, not hard-coded**. `/System/Library/ExtensionKit/Extensions` is where
System Settings keeps them, and each declares the extension point and a bundle identifier that
`x-apple.systempreferences:` opens.

Names come from each bundle's *localised* dictionary, which is what makes them read "Wi‑Fi", "Desktop
& Dock" and "Touch ID & Password" rather than "WiFiSettings" and "DesktopSettings". The handful with
no localised name fall back to the sidebar label declared in the bundle, which is why Battery is not
listed as "PowerPreferences".

The older `/System/Library/PreferencePanes` route looks like the obvious one and is not: on macOS 26
most of those bundles are empty stubs with no `Info.plist` at all, which yields names like
"DesktopScreenEffectsPref" and entries for hardware nobody has had in a decade.

Two of Apple's own flags do the filtering, so there is no list of exceptions to go stale: a pane must
declare `allowsXAppleSystemPreferencesURLScheme`, and one whose every representation is marked hidden
is left out.

:::note[A pane whose visibility depends on a predicate cannot be filtered]
`device.cddvd == YES` is evaluated by System Settings against live device state, and nothing else can
evaluate it — so CDs & DVDs and Classroom appear on machines that would not show them. Opening one is
harmless; guessing at the predicates would not be.
:::

## Power actions

**Sleep, Log Out, Restart and Shut Down are a permanent row of buttons** above *Open Applications
Folder*, rather than four more rows at the bottom of a list you would have to scroll to reach.

They are icon-only and evenly spread, and each names itself in a tooltip — a power symbol and a
restart symbol are not worth guessing between. Typing still finds them, so `restart` reaches Restart
whether or not you were looking at the buttons.

**Sleep is at the left-hand end and Shut Down at the right**, furthest from it: a list you drive by
typing is exactly where a mistyped <kbd>Return</kbd> lands one row off.

**Log Out, Restart and Shut Down each ask first**, in a dialog that names which of the three is about
to happen — three alerts reading "Are you sure?" would be three ways to shut the machine down by
mistake. <kbd>Return</kbd> is the action and <kbd>Escape</kbd> is Cancel. Sleep does not ask, because
it is undone by moving the mouse.

They are Apple events to `loginwindow` — there is no Cocoa API for any of them and the shell
equivalents need root — so the first use raises the Automation prompt, exactly as emptying the Trash
does.

:::caution[There is no Lock Screen]
The `CGSession` binary every recipe names is gone from macOS 26, and the call that replaced it is
private. Sleeping the display is not the same thing and would be a lie.
:::
