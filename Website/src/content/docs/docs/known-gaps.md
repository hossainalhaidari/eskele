---
title: Known gaps
description: What Eskele does not do, and whether that is a decision or a wall in macOS.
---

Each of these is here with its reason, so you can tell a decision from a limit before filing a bug.

## Walls in macOS

**The bar cannot reserve space inside a native full-screen space.** macOS reserves nothing there
except for the menu bar. [Reserved-space mode](../system-dock/#reserve-screen-space) covers maximised
windows; for full-screen the bar can only float over the window or get out of the way.

**Full-screen detection needs Accessibility.** There is no reliable permission-free way to tell a
full-screen space from a window merely sized to fill the screen. Without the permission the setting
behaves as *Always Show*.

**A window on another Space cannot be *found* directly.** Accessibility only exposes the current
Space's windows. Eskele works around it [four ways](../windows/#windows-in-a-full-screen-space), so
the gap is only a window Eskele has never had in view — that one can be counted and shown, but
clicking it can only activate its application, which is all the real Dock manages too.

**A badge set before Eskele launched is missing until it next changes.** Badges are read off the
Dock's own tiles, and Eskele restarts the Dock to hide it; macOS does not re-push a badge to the new
Dock process. A badge that is not a number — a bare dot — has no number to draw. See
[Badges](../badges/).

**A file operation cannot be attributed to the application doing it.** macOS publishes the file, the
fraction and the kind of operation, and nothing that names the publisher — so Eskele shows these on
the destination folder's cell rather than on the application's. See [Progress](../progress/).

**Now Playing cannot be read without asking the player.** The system's own interface for it has needed
a private entitlement since macOS 15.4. Media progress therefore costs an Automation consent per
player, and is off until you ask for it. Only Music, Spotify and VLC expose a scriptable position at
all.

**A bouncing Dock icon cannot be detected.** `requestUserAttention` goes to the Dock privately. Eskele
highlights the dialogs and sheets that usually accompany it, which needs Accessibility, but an
application that only bounces will not light up.

**Safari's tabs do not count towards Safari.** WebKit's content processes are parented to launchd, so
nothing in the process tree connects them. macOS knows the answer and only exposes it privately. See
[Activity](../activity/#safaris-tabs-are-the-exception).

**Counting the Trash without Full Disk Access is an estimate**, derived from the directory's own
metadata. It agrees with Finder on APFS; on a volume laid out differently Eskele reports nothing
rather than guessing.

**There is no Lock Screen.** The `CGSession` binary every recipe names is gone from macOS 26, and the
call that replaced it is private. Sleeping the display is not the same thing and would be a lie.

**Emptying the Trash asks Finder to do it**, and the power actions ask `loginwindow`. No public API
exists for either, so both raise the system Automation prompt on first use.

## Decisions

**Not sandboxed**, so this can never ship on the Mac App Store while it controls the Dock.

**A shortcut another app already uses cannot be detected.** macOS accepts the registration either
way, so a recorded shortcut is checked against macOS's own and Eskele's others, not against other
apps'. See [Recording a shortcut](../gestures/#recording-a-shortcut).

**No custom clock dials.** uBar's timepieces are folders of PNGs described by a plist; a plug-in
format with one implementation is a file layout to maintain rather than a feature. The dial is drawn
from the current appearance's own colours. See [Clock](../clock/#no-custom-dials).

**No blue "restorable" stripe.** uBar has one. Eskele already dims a hidden application and draws one
dash per window, so the state it would report is one the bar shows already.

**Custom icons come from a folder, not a picker.** Pinned folders and files are not listed there
either, because a path is not a filename — Finder's own *Get Info ▸ paste an icon* already overrides
those. See [Appearance](../appearance/#custom-icons).

## Not built yet

**Releases are Apple silicon only, by choice.** `swift build` builds for the Mac it runs on, and
GitHub's macOS runners are Apple silicon. The appcast says so, so an Intel Mac is never offered an
update it cannot run.

**Only the DMG carries a stapled ticket, not the app inside it.** Gatekeeper accepts the app copied
out of it by asking Apple online, which is how it is normally first opened — a Mac that is offline the
first time Eskele opens would refuse it.

**VoiceOver has been built for, not yet listened to.** What the bar tells VoiceOver — each item's
role, name, state and actions, in bar order — is tested, and so is the keyboard reaching the bar.
Nobody has yet heard VoiceOver read the bar. See
[From the keyboard](../gestures/#from-the-keyboard-and-with-voiceover).
