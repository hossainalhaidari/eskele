---
title: Activity overlay
description: Hold ⇧⌥ and every running application reports its processor and memory use.
---

Hold **<kbd>⇧⌥</kbd>** and every running application reports what it is costing: processor use above,
memory below.

Icons-only cells stack the two figures on a **translucent scrim**, so the icon still shows through —
the question this answers is usually *which* application is eating the battery, which you cannot read
off a covered icon. A labelled button puts the figures where the application's name would be, and
keeps its icon.

Turn it off with *Activity Overlay*.

## Why ⇧⌥

It means nothing else here. <kbd>⇧</kbd>-click quits and <kbd>⌥</kbd>-click hides, but <kbd>⇧⌥</kbd>
together is not a click gesture, so holding it and clicking by accident does nothing. A test asserts
that, and will fail if <kbd>⇧⌥</kbd> ever gains a meaning.

## What it samples, and when

**Nothing is sampled until the keys go down, and everything is forgotten when they come up.**

Processor use needs two readings to subtract, so the first moment shows `—` and the figure appears
about half a second later. Memory is exact immediately.

**No permission is needed**: `proc_pid_rusage` answers for any process you own, and the modifiers are
read directly rather than monitored.

## Helper processes count towards their application

An Electron application does its work in child processes — VS Code has nine — so reading the
application's own process alone would report a fraction of the truth. **Every descendant is added
up.**

### Safari's tabs are the exception

WebKit's content processes are started by launchd and have it as their parent, so nothing in the
process tree connects them to Safari. macOS knows the real answer — that is what a "responsible
process" is — but only exposes it through private API, so **Safari reports its own process alone and
reads lower than Activity Monitor shows.**

:::note[A unit conversion worth knowing about]
Processor time comes back in **mach absolute time units**, not the nanoseconds the header documents.
On Intel those are the same thing; on Apple Silicon the timebase is 125/3, so a saturated core reads
as 2.4% if you take the field at its word.

`ActivityServiceTests` burns a core and insists the number follows, because the wrong version looks
entirely plausible.
:::
