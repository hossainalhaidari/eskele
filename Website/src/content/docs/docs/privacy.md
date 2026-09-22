---
title: Privacy
description: Eskele has zero telemetry. What stays on your Mac, the one time it goes online, and exactly what that request carries.
---

**Eskele has zero telemetry.** It collects nothing about you or how you use it, and sends nothing
anywhere. There are no analytics, no crash reports, no usage statistics, no identifiers and no
"anonymous" counts. There is no Eskele server for any of it to go to.

This is not a setting you have to find and switch off. The telemetry code isn't hidden or turned
off by default; it was never written.

## What Eskele does not do

- **No analytics or tracking library.** The only third-party code in the app is
  [Sparkle](https://sparkle-project.org), the updater described below.
- **No crash reporter.** When something goes wrong, Eskele writes a line to your Mac's own log, which
  you can read in Console, and nowhere else.
- **No identifier.** Nothing that could tell your Mac from anyone else's is created, stored or sent.
- **No account, no sign-in, no licence check, no cloud sync.**
- **No diagnostics upload.** `--diagnose` and its siblings write plain text files on your Mac. You
  read them yourself, and share them only if you choose to.

## What stays on your Mac

Everything Eskele keeps — settings, pinned items, badge and progress commands, custom icons and the
Dock backup — lives in `~/Library/Application Support/Eskele/` (see
[Files and configuration](../files/)), and the update choice lives in Eskele's own defaults. Export
Settings writes a file where you tell it to, and nowhere else.

Everything Eskele sees while it runs — which apps are open, window titles, processor and memory use,
[window previews](../windows/#window-previews), the track playing in Music, Spotify or VLC — is used
to draw the bar and never leaves your Mac. The [permissions](../permissions/) it asks for exist to
read that on your Mac, not to send it anywhere.

## The one time it goes online

Eskele connects to the internet for one thing only: to look for an [update](../install/#updates).

**Out of the box, it does that only when you ask** — **Check Now** in *Settings ▸ General*, or
**Check for Updates…** in the menu-bar menu. Choose *Install Automatically* or *Ask Before
Installing* and it looks once a day instead.

A check downloads a single file, the release feed (`appcast.xml`), from Eskele's GitHub releases.
If you take an update, it then downloads that update from the same place. Here is everything those
requests carry:

| | |
|---|---|
| **Your Eskele version** | **Not sent.** The request calls itself `Sparkle`, the same on every copy. Your Mac compares its own version with the feed. |
| **Your language** | **Not sent.** The request asks for any language (`*`) rather than passing on your preferred ones, which macOS would otherwise add to every request. |
| **Your Mac** — macOS version, model, processor, memory | **Not sent.** Sparkle can attach an "anonymous system profile" to each check. It is off in Eskele, and Eskele allows it no fields, so it would send nothing even if it were switched on. |
| **An identifier** | **None exists** to send. |
| **Your IP address** | **Seen by GitHub**, as it is by any server you connect to. It is the one thing a request cannot leave out. |

Every copy of Eskele sends the same request, so apart from your IP address nothing in it could tell
your copy from anyone else's. GitHub counts how many times each release file is downloaded, so the
feed's count goes up by one with every check anyone makes. That total is all the project ever gets
to see.

:::tip[Never online at all]
Leave updates on **Only When I Check**, which is the default, and don't press Check Now. Eskele then
never opens a network connection. A copy you [build from source](../install/) has no update feed at
all, so it never goes online whatever you choose.
:::

## Things you add yourself

[Badge](../badges/#badges-of-your-own) and [progress](../progress/#a-command-you-supply) commands
you write run as you, through `/bin/sh`. They reach the network only if you write them to, and
Eskele sends nothing through them.

## Don't take our word for it

Eskele is [open source](https://github.com/hossainalhaidari/eskele), so every claim on this page can
be checked:

- **The dependencies.** `Package.swift` lists one: Sparkle. `UpdateService.swift` is the only file
  that uses it.
- **The update settings.** `Resources/Info.plist` turns scheduled checks and the system profile off,
  and a test fails if either is ever turned back on.
- **A running copy.** Ask macOS which network connections Eskele has open:

  ```bash
  lsof -nP -i -a -p "$(pgrep -x Eskele)"
  ```

  With the default settings this prints nothing, because Eskele has none open. A firewall such as
  [LuLu](https://objective-see.org/products/lulu.html) or Little Snitch shows the same thing live.

## This website

These pages are plain static files hosted on GitHub Pages. They have no analytics, no cookies and no
third-party scripts or fonts, and the search runs entirely in your browser. GitHub, which hosts the
site, sees visitors' IP addresses as any web host does.
