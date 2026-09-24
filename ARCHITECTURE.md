# Eskele — Architecture & Feasibility Plan

A minimal macOS dock replacement: a slim bar in two fixed sizes, showing each app's own icon scaled
to fit, dockable to the **left**, **bottom**, or **right** edge, that suppresses the
built-in Dock while it runs.

- **Status:** planning. No code yet.
- **Host toolchain (verified 2026-08-31):** macOS 26.6 (Tahoe), Xcode 26.6, Swift 6.3.3, arm64.

---

## 1. Goals / Non-goals

**Goals**

1. A borderless bar whose thickness equals the system menu bar's, on any screen edge except top,
   either hugging its icons or spanning the whole edge like the menu bar itself.
2. Each app's stock icon, rendered crisply at the bar's small size — no recolouring, no tinting.
3. Pinned (bookmarked) apps + running apps + running indicators.
4. Trash item: live empty/full state, drop-to-trash, empty-trash action.
5. Suppress the real Dock while Eskele runs; restore it reliably on quit, crash, or logout.
6. Persisted layout, drag-reorder.

**Non-goals (v1)**

- Replacing Mission Control / Launchpad / Stage Manager (all still owned by the `Dock` process).
- Window thumbnails / Exposé previews.
- Mac App Store distribution (see §9 — the Dock-suppression feature is incompatible with sandboxing).

---

## 2. Feasibility summary

| # | Feature | Verdict | Mechanism / caveat |
|---|---|---|---|
| 1 | Two fixed bar sizes | **Yes** | Small 32pt, Big 48pt, the same on every display; see §5.1. It once matched the menu bar, which needed measuring per display and was dropped. |
| 2 | Left / bottom / right placement | **Yes** | Borderless `NSPanel` positioned on the screen edge; no OS constraint. |
| 3 | App icons at bar size | **Yes** | `NSWorkspace.icon(forFile:)` → retina-correct downscale. The only real work is picking the right `.icns` representation so small icons stay crisp. See §5.3. |
| 4 | Bookmark / pin apps | **Yes** | URL bookmark data + bundle ID, drag-and-drop from Finder. |
| 5 | Running-app indicators | **Yes** | `NSWorkspace.runningApplications` + launch/terminate/activate notifications. |
| 6 | Trash icon, full/empty state | **Yes — needed rework** | `~/.Trash` is TCC-protected: both `contentsOfDirectory` and `open(O_EVTONLY)` fail without Full Disk Access, and the failed listing read as "empty". Counted from the directory's own `stat` instead, and polled. See §5.7. |
| 7 | Drop files onto Trash | **Yes** | `FileManager.trashItem(at:)` (records Finder "Put Back"). |
| 8 | Empty Trash | **Yes, needs permission** | No public API — AppleScript to Finder, requires Automation consent (one prompt). |
| 9 | Hide the real Dock | **Yes, with caveats** | `com.apple.dock` prefs (`autohide` + huge `autohide-delay`) + `killall Dock`, plus our panel occluding the reveal strip. Requires an **unsandboxed** app and a robust restore path. See §5.5. |
| 10 | **Reserve screen space** (windows not overlapping the bar) | **Yes — solved, second attempt** | No API does it directly, but a *showing* system Dock reserves space every app respects. Park one on the bar's edge, sized to match, underneath the bar. The first version hid it, which held only until the Dock next re-laid out. See §5.6. |
| 11 | Dock badges (unread counts) from other apps | **Yes — solved** | No API hands one app another's badge, but the Dock is an ordinary application and its tiles carry `AXStatusLabel`, which holds the string the Dock is drawing. Accessibility only. Verified against a test app and against Mail receiving a live message. Configurable per-app commands remain, for what the Dock does not carry. See §5.17. |
| 12 | Minimized-window list / per-window menu | **Yes, needs permission** | Accessibility (AX) API; requires the user to grant Accessibility. Optional module. |
| 13 | Drop a file onto an app icon to open it | **Yes** | `NSWorkspace.open(_:withApplicationAt:)`. |
| 14 | Stacks (folder → grid popover, e.g. Downloads) | **Yes** | Ordinary directory enumeration + a popover panel. |
| 15 | Auto-hide + hover reveal for our own bar | **Yes, no permissions** | 1pt edge "trigger" window with tracking area — avoids needing a global event monitor. |
| 16 | Launch at login | **Yes** | `SMAppService.mainApp.register()`. |
| 17 | Full-width / full-height bar | **Yes** | Span the screen edge instead of hugging the icons, with the icon run anchored leading / centre / trailing. See §5.2. |
| 18 | Our own auto-hide | **Yes, no permissions** | 2pt edge trigger window with a tracking area; polling only while the bar is out. See §5.10. |
| 19 | Global reveal hot key | **Yes, no permissions** | Carbon `RegisterEventHotKey`. The AppKit equivalent needs Accessibility; this does not. The Apps Menu gets its own key on the same mechanism — see §5.15. |
| 20 | Stacks (folder → contents) | **Yes** | Lazily-populated `NSMenu`, which is what the Dock's own list view is. See §5.11. |
| 21 | Preferences window | **Yes** | SwiftUI, hosted in an `NSWindow` the agent activates explicitly. |
| 22 | Show / hide the bar in full screen | **Yes, needs Accessibility** | Three behaviours: always show, reveal on hover, hide. Detecting a full-screen space has no permission-free route — see §5.13. |
| 23 | **Reserve space inside a full-screen space** | **No** | Measured: the Dock's reservation does not exist in a full-screen space, and the only edge that reserves there is the top, owned by the menu bar. §5.13. |
| 24 | Taskbar-style labelled buttons | **Yes** | Running apps grow into labelled buttons that share the bar and collapse back to icons under pressure. Horizontal bars only. See §5.14. |
| 25 | Small / Big scale | **Yes** | Big is 1.5x Small — 48pt with 40pt icons. Every derived measurement scales together through `BarMetrics`. See §5.1. |
| 26 | Apps Menu (launcher) | **Yes** | A Start-button-style panel: search field, categorised All Apps, working on any edge. See §5.15. |
| 27 | Per-window indicators | **Yes, needs Accessibility** | One dash per window, capped at four, with click-to-cycle. Falls back to a single dash without the permission. See §5.16. |
| 28 | Window titles on buttons | **Yes, needs Accessibility** | `kAXTitleAttribute` gives the live title — Safari's button reads the page name. See §5.16. |
| 29 | One button per window | **Yes, needs Accessibility** | The Windows "never combine" behaviour, in full-width labelled mode. See §5.16. |
| 30 | Highlight an app that needs attention | **Partly, needs Accessibility** | `requestUserAttention` — the bouncing icon — is delivered privately to the Dock and is unobservable, same channel as row 11. What *is* visible is the modal that usually accompanies it: an `AXDialog`/`AXSystemDialog` window, or `kAXSheetCreatedNotification`. See §5.18. |
| 31 | Number badges | **Yes, the real ones** | Read off the Dock's own tiles, with commands as the catch-all. See row 11 and §5.17. |
| 32 | Pinned apps as a separate group | **Yes** | In labelled mode a pinned app that is not running is a shortcut, not a task, and is hoisted into a compact tray at the leading end. See §5.19. |
| 33 | Reorder anything, in either style | **Yes** | Pinned items rewrite the stored layout; running apps and window buttons get in-memory orders. ⌘-drag means "move, never remove". See §5.19. |
| 34 | Full-screen windows in the window list | **Yes, needs Accessibility** | They frequently report an empty `AXTitle`, which the old title-only filter dropped. Filtered on subrole instead. See §5.16. |

**Bottom line:** everything you asked for is achievable. Both limitations this plan originally
conceded turned out to be solvable — windows not avoiding the bar (§5.6), and other apps' Dock
badges (row 11, §5.17). Nothing on the list is out of reach.

---

## 3. Tech stack

- **Swift 6.3**, strict concurrency on. Actor-isolated services, `@MainActor` UI.
- **AppKit** for the window layer (`NSPanel`, levels, spaces, drag & drop) — SwiftUI cannot express
  non-activating borderless panels or window levels.
- **SwiftUI** inside the panel via `NSHostingView` for the item strip and preferences window.
- **Deployment target: macOS 15.0.** (Drop to 14.0 only if needed; nothing in the plan requires 26.)
- **One third-party runtime dependency: Sparkle**, for auto-update outside the App Store (§5.28).
  Nothing else.
- Build: an Xcode project for the app target, with the testable cores as **local SwiftPM packages** so
  the dock-prefs and trash logic can be unit-tested headlessly.

---

## 4. Process shape

Single agent process, `LSUIElement = true` (`NSApp.setActivationPolicy(.accessory)`): no Dock tile of
its own, no menu bar of its own, never steals focus. A `NSStatusItem` in the menu bar is the only
always-available affordance (Preferences, Restore Dock, Quit) — important as a rescue hatch while the
system Dock is suppressed.

```
Eskele.app (agent)
├─ AppDelegate ────────── lifecycle, crash/exit hooks, status item
├─ ScreenCoordinator ──── one BarWindowController per screen, reacts to screen changes
├─ DockModel (@Observable) ─ ordered items = pinned ∪ running ∪ separators ∪ trash
├─ Services
│   ├─ RunningAppsService ── NSWorkspace observation
│   ├─ AccessoryAppsService ─ menu-bar apps that currently have a window
│   ├─ IconService ───────── fetch → size for backing scale → cache
│   ├─ TrashService ──────── FSEvents watch, trashItem, empty via Finder
│   ├─ SystemDockService ─── suppress / restore the real Dock
│   ├─ PersistenceService ── layout + settings JSON
│   └─ WindowService (opt) ─ AX window list / minimize / restore
└─ UI
    ├─ BarView (SwiftUI) ─── orientation-aware item strip
    ├─ ItemView ──────────── icon, indicator, hover, context menu
    └─ PreferencesScene ──── settings window
```

**Local packages:** `DockPrefsKit`, `TrashKit` — pure Swift, no AppKit window deps where
avoidable, fully unit-tested. Everything else lives in the app target.

---

## 5. Design detail

### 5.1 Bar geometry — two fixed sizes

**Two scales, neither measured.** `small` is 32pt, giving 27pt icons against the real Dock's 42pt.
`big` is 1.5x that: a 48pt bar with 40pt icons, near enough the Dock's own default, i.e. the
platform's idea of a comfortable target. A user nudge of −6 to +12pt sits on top of either, and the
result is clamped to `[18, 96]`. `Settings.rowThickness` is the whole rule, a pure function of the
settings and the same on every display; extra rows stack it again. Icon box = `thickness - padding -
outerInset`; the asymmetry is the indicator margin (§5.14).

**It used to follow the menu bar.** Small was once measured per screen to match the menu bar exactly
— `safeAreaInsets.top` on a notched display, the `frame`/`visibleFrame` gap elsewhere, the menu-bar
screen's value mirrored to displays that report neither — and Big was 1.5x the result. It was
dropped: matching the menu bar was never what made the bar good, it made Small a different size on
every display, and only a notched built-in display ever exercised the measurement (spike S3, §6).
The fixed values are what that measurement gave on the notched display it was built on, so nothing
changed there. (`NSStatusBar.system.thickness` was never the answer anyway: it has been pinned at
22pt for years against a drawn menu bar of 32pt.)

**Everything scales together, in one place.** The multiplier touches padding, the indicator margin
and weight, item spacing, end padding, separator length, label type, button width caps and corner
radius — eight or so constants. `BarMetrics` derives all of them once per layout pass from
`(thickness, settings)`. Scattering `* multiplier` through the drawing code is how one gets missed
and Big ends up looking like Small with gaps around it; a test pins the icon-to-bar ratio equal
across both scales for exactly that reason. Label type is the one thing deliberately not scaled
linearly — it is capped at 14pt, past which a taskbar label starts to shout.

For **left/right** orientation the same number becomes the bar's *width*; icons stack vertically and
the strip scrolls (clipped, no visible scrollbar) when it overflows.

### 5.2 The bar window

```swift
let panel = NSPanel(contentRect: .zero,
                    styleMask: [.borderless, .nonactivatingPanel],
                    backing: .buffered, defer: false)
panel.isFloatingPanel      = true
panel.hidesOnDeactivate    = false
panel.isMovable            = false
panel.ignoresMouseEvents   = false
panel.backgroundColor      = .clear
panel.isOpaque             = false
panel.hasShadow            = false
panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 1)  // 21
panel.collectionBehavior   = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
```

Verified level constants on this OS: `dockWindow = 20`, `mainMenuWindow = 24`, `statusWindow = 25`,
`floatingWindow = 3`. Level **21** puts us above the real Dock (so we occlude its reveal strip even if
prefs manipulation is defeated) while staying below menus and the menu bar.

- **Background:** `NSVisualEffectView` with `.menu` or `.headerView` material, `.behindWindow` blending,
  `.active` state — this is what makes it read as "part of the menu bar" rather than a floating widget.
  Offer an opaque and a fully transparent variant.
- **Non-activating** is essential: clicking an item must not deactivate the user's frontmost app before
  we activate the target.
- **Placement** is computed by `BarFrameSolver`, a pure function, because it is fiddly in exactly the
  way that hides bugs: three edges, two span modes, bottom-left screen coordinates, and one region at
  the top of the display that is not ours. A full-height bar on the left or right must stop at
  `screen.frame.maxY - menuBarInset`, and a hugging vertical bar must centre in the region *below*
  the menu bar rather than on the display — otherwise it creeps upward as items are added. Shipped
  once without that and a full-height bar sat underneath the menu bar; there are now eight tests on
  the geometry alone. `ScreenMetrics.menuBarInset(for:)` reports the space the menu bar takes on one
  screen, 0 when it has none — the one thing the bar still measures about the menu bar, and only to
  keep out of its way.
- **Span:** two modes. `hugContents` sizes the bar to its icons and centres it on the edge — a
  floating slab with rounded inward corners. `fullSpan` stretches it across the entire edge, so it
  reads as a second menu bar; corners square off automatically (a full-width bar with rounded ends
  looks like a mistake), and the icon run is anchored leading, centre or trailing along the bar's own
  axis. On a vertical bar "leading" means the top.
- **Trailing group.** In `fullSpan` the Trash detaches from the run and anchors to the far end —
  right on a horizontal bar, bottom on a vertical one — the way a taskbar's tray does. There is no
  gap to spread across when the bar hugs its icons, so it only applies to full width. The leading
  run is then laid out in the space *minus* the trailing group, which is what stops a trailing
  alignment or an over-long run from colliding with the Trash; the cost is that a centred run sits
  half a Trash-width left of true centre, which is not perceptible at these sizes.

  This is why cell positions are resolved into an explicit `cellOrigins` array during layout rather
  than being re-derived by accumulation in three places. The drop-index calculation in particular
  must walk the real origins: a file dropped into the empty middle of a full-width bar means "at the
  end of the run", not "past the Trash".
- **Multi-display:** one controller per `NSScreen` by default; settings for *all screens* / *main screen* /
  *screen with the mouse*. Screens are matched by `NSScreenNumber` (display ID), not array index, so
  layouts survive replug.

### 5.3 Icon rendering

We use each app's own icon, unmodified — no monochrome conversion, no tinting. `NSWorkspace` hands it
over in one call:

```swift
let icon = NSWorkspace.shared.icon(forFile: appURL.path)   // NSImage, multi-representation
```

The only real engineering here is making a 1024px `.icns` look crisp at ~26pt. Three rules:

1. **Work in pixels, not points.** Target = `iconBox * screen.backingScaleFactor` (26pt × 2 = 52px).
   The bar must re-render when a window moves between a Retina and a non-Retina display.
2. **Pick the right representation.** `.icns` bundles reps at 16/32/128/256/512/1024px. Select the
   smallest rep ≥ target (128px for a 52px target) and downscale it with `.high` interpolation.
   Never upscale the 32px rep — that is the classic blurry-dock-icon bug.
3. **Rasterize once.** Flatten to an `NSImage` of exactly the target pixel size and cache that;
   SwiftUI's `Image(nsImage:)` then blits it without resampling every frame.

`icon(forFile:)` is the same call Finder makes, so custom folder icons, document icons, alias arrows
and quarantine badges all come through for free. Folders and files in stacks use the same path;
`NSWorkspace.shared.icon(for: UTType)` covers types with no file on disk.

**Caching:** an `NSCache` keyed by `bundleID + pixelSize + bundle mtime`. The mtime component means an
app update invalidates its own entry with no explicit invalidation logic. No disk cache — Icon
Services is already fast and keeps its own; a cold miss is a few milliseconds.

**Legibility:** full-colour icons on a translucent bar over a bright wallpaper can wash out. Ship a
material/opacity setting (§5.2) and a subtle 1px separator line on the screen-facing edge, so the bar
always reads as a distinct surface rather than floating glyphs.

**Optional, v2:** a per-item custom image override for the handful of apps with genuinely ugly icons.
Cheap to add, not needed for v1.

### 5.4 Item model

```swift
enum DockItem {
    case app(AppItem)          // pinned and/or running
    case folder(FolderItem)    // stack, e.g. ~/Downloads
    case file(FileItem)
    case separator
    case trash
}
```

Ordering rule (mirrors the real Dock, keeps it predictable): `[pinned…] | [running-but-not-pinned…] | [stacks/files…] | [trash]`, separators user-placeable. Pinned items persist by **URL bookmark data +
bundle identifier**; bookmark resolves the app after a move, bundle ID is the fallback lookup via
`NSWorkspace.urlForApplication(withBundleIdentifier:)`.

Interactions:
- Click → launch (`openApplication(at:configuration:)`) or activate (`NSRunningApplication.activate()`).
- Right-click → Options (Keep in Dock, Open at Login, Show in Finder), Quit, window list (if AX granted).
- Drag from Finder onto the bar → pin, with an insertion caret.
- Drag within the bar → reorder; drag far off the bar → unpin with the poof.
- Drop a file onto an app → open with it. Onto Trash → trash it.
- Running indicator: a 3pt dot on the edge-facing side, matching menu bar label colour.

#### The URL a cell launches — measured

`NSRunningApplication.bundleURL` is the bundle a process was *started from*, and that is not always
something LaunchServices will *launch*. Steam is the reference case: `/Applications/Steam.app` is a
bootstrapper, and the client it updates and then runs lives at

    ~/Library/Application Support/Steam/Steam.AppBundle/Steam

a genuine `APPL` bundle carrying `com.valvesoftware.steam` — with **no `.app` extension**. Measured on
macOS 27:

| URL | `isApplicationKey` | `urlForApplication(toOpen:)` |
|---|---|---|
| `/Applications/Steam.app` | `true` | `Steam.app` |
| `…/Steam.AppBundle/Steam` | `false` | **`Finder.app`** |

So macOS treats the running bundle as a document, and a document that is a directory belongs to
Finder. `openApplication(at:)` on it returns `com.apple.finder` **with `error == nil`** — a silent
misfire, which is why the error log in `DockModel.open(_:)` never fired and the bug read as "Steam
opens its folder". Pinning the cell compounded it: `PersistedItem.make(for:)` classifies by the
`.app` extension, so the entry was stored as a **folder** and the mistake outlived the session.

`ApplicationURL` is the rule that fixes it: keep the running bundle when macOS agrees it is an
application, otherwise resolve the same bundle identifier through
`urlForApplication(withBundleIdentifier:)` — which is the `/Applications` copy the user believes they
are clicking — and fall back to the original URL when nothing is installed under that identifier, so
an app that only ever exists in this shape is no worse off. The common case is short-circuited on
`pathExtension == "app"`, because `rebuild()` walks every running app on every workspace change.

Only the *URL* is rewritten. `bundleID` still comes from the process, and running state, window
lists, Quit and Hide all key off it, so none of them notice.

### 5.5 Suppressing the system Dock

There is no supported "hide the Dock globally" API. `NSApplication.presentationOptions`'s `.hideDock`
only applies while *your* app is frontmost, which is useless for an agent that never activates. The
approach that actually works, in layers:

1. **Preferences + restart** — the canonical trick:
   ```
   com.apple.dock  autohide              = true
   com.apple.dock  autohide-delay        = 1000      (seconds; effectively "never reveal")
   com.apple.dock  autohide-time-modifier = 0
   killall Dock
   ```
   Write via `CFPreferencesSetAppValue` + `CFPreferencesAppSynchronize` (not by shelling out to
   `defaults`, which races with `cfprefsd`).

   **Measured correction (macOS 26.6, 2026-08-31):** hiding the Dock appeared *not* to return its
   strip to `NSScreen.visibleFrame` — the reservation seemed to freeze at whatever the Dock last
   published while visible. **Corrected again (macOS 27, 2026-09-15):** it freezes only until the
   hidden Dock next re-lays out, which the next app to launch or quit brings about. §5.6 has the
   measurement and what replaced it.
2. **Occlusion** — our panel sits at window level 21, above `kCGDockWindowLevel` (20), so even if a
   future OS ignores `autohide-delay`, the Dock cannot draw over us on the edge we occupy.
3. **Watchdog** — observe `com.apple.dock` preference changes (`kCFPreferencesAnyApplication`
   distributed notification) and Dock relaunches; re-apply if something (System Settings, another
   utility, a macOS update) reverts them, unless the user changed it deliberately.

**Restore is the part that must not fail.** Snapshot the user's original values *before* the first
write, into `~/Library/Application Support/Eskele/dock-backup.json`, then restore on:
- normal `applicationWillTerminate`,
- `SIGTERM`/`SIGINT`/`SIGHUP` handlers and an `atexit` hook,
- **next launch**, if the backup file exists and is marked "not cleanly restored" (covers `SIGKILL` and
  panics — the only case a hook cannot catch),
- an explicit "Restore system Dock" menu item in the status item, and the same button in the
  preferences window — which stays reachable even with the status item hidden (§5.12),
- a `--restore-dock` CLI flag documented in the README, so a user can recover with the app deleted.

Caveats to document for the user: `killall Dock` momentarily restarts Mission Control / Stage Manager /
Launchpad (they are all the `Dock` process); full-screen spaces are unaffected; the Dock's own
keyboard shortcut ⌥⌘D will still toggle `autohide` and is caught by the watchdog.

### 5.6 Reserving screen space

The real Dock shrinks `NSScreen.visibleFrame` so "zoomed" windows stop short of it, and no public API
lets a third-party app do the same. So we do not need the API — we need the Dock to hold the space on
our behalf: parked on the bar's edge, sized to match, and covered by the bar.

**How a reservation travels.** The Dock publishes a rect to the window server
(`SLSSetDockRectWithReason`), and each app's AppKit derives `visibleFrame` from that rect together
with the Dock's *orientation*, which it reads separately. The window server passes each publication
on to running apps as a screen-parameters change, and they cache it. Measured on macOS 27, with a
long-running AppKit app zooming a window every two seconds while the Dock was provoked:

1. **A hidden Dock publishes a zero-height rect whenever it re-lays out** — and it re-lays out when a
   tile appears or disappears, i.e. when any app that is not pinned launches or quits.
2. **A restarted hidden Dock publishes nothing until then**, so the rect left by the previous,
   visible instance lingers. That was the "freeze" the first version of this mode was built on
   (§5.5): real, and gone the first time the user opened something. It is why maximising worked
   only sometimes.
3. **Only the Dock's publications reach running apps.** Any process may call
   `SLSSetDockRectWithReason`, and the window server accepts it — a freshly launched process sees
   the new rect — but no reason code makes it broadcast, and re-asserting within 5ms of the Dock's
   own zero-height publication still loses: running apps have already cached the Dock's version.

Reading orientation apart from the rect is what made the old failure so odd. A left-shaped rect
published under a bottom orientation produced a 700pt reservation at the *bottom*. The first version
flipped the Dock between the user's own position and ours on every quit and launch, so an app could
cache one Dock's rect alongside the other's orientation — which is how windows came to leave a gap on
the left of a bar that was on the bottom.

**Reserved-space mode** (opt-in, `reserveScreenSpace`) therefore parks the Dock **showing**:
`orientation` on the bar's edge, `tilesize` to match its thickness, `autohide` off — one restart, no
second phase. A showing Dock republishes the right rect with the right orientation every time it
re-lays out, and every running app hears about it: measured, the same long-running app kept its
reservation through two tile changes that had each wiped the hidden Dock's. The bar sits one level
above it (21 against 20) and exactly as thick as the reservation, so it covers it. The launch and
attention bounces are switched off, being the only parts of a Dock that reach past its own edge.

The sizing is exact. Measured on 26.6, the reservation is `tilesize + 20` points, linear across the
whole range, and `defaults` accepts tile sizes below the 16pt floor the Dock's own slider enforces:

| `tilesize` | 4 | 8 | 12 | 16 | 24 | 42 |
|---|---|---|---|---|---|---|
| reserved | 24pt | 28pt | 32pt | 36pt | 44pt | 62pt |

A 32pt bar therefore wants `tilesize: 12`. Verified end to end: with the bar on the bottom edge,
`visibleFrame` went from `(62, 0, 1408, 923)` to `(0, 32, 1470, 891)` — exactly 32pt reserved at the
bottom, and the 62pt the user's left-side Dock had been holding handed back.

**What a parked Dock costs**, since it really is there:

- A vibrancy material blurs whatever is behind the bar, which now includes 12pt Dock icons, and a
  custom colour below full opacity shows them through. Not yet judged by eye — screen capture was
  unavailable when this was measured.
- In Fit to Icons mode a Dock wider than the bar would show at its ends. At 12pt tiles it rarely is.
- The mode is dropped while the bar auto-hides (`AppDelegate.applyDockRequest`): a bar that slides
  away would uncover the Dock, and an auto-hiding Dock gives its space back too.
- With several displays the Dock still moves to another display's edge when pushed against, taking
  the reservation with it. That is the system Dock's own behaviour, and there is only one Dock.

**It does not extend to full-screen spaces.** Measured on 26.6: with 32pt reserved at the bottom in
the normal space (`visibleFrame` `(0, 32, 1470, 891)`), a full-screen window still got the whole
`(0, 0, 1470, 923)`, and `visibleFrame` inside that space was `(0, 0, 1470, 923)` — the Dock's
reservation, left-side one included, simply is not there. §5.13 covers what is possible instead.

**Why it stays opt-in.** It rewrites the user's Dock position and tile size, not just its visibility,
and both have to be captured in the backup and restored on exit (they are). Users who keep the system
Dock configured a particular way for other reasons should get to decline. When it is off, the bar
simply floats above windows at level 21, which is what most minimal docks do.

**The AX window nudge is uBar's answer, and still not ours.** uBar reserves nothing: it watches
windows over Accessibility and resizes any that end up under its bar, about half a second after the
fact. That needs the permission, visibly snaps windows after they have moved, fights apps that
restore their own frames, and cannot reach apps with weak Accessibility support — uBar's own
documentation names Java IDEs and Carbon-era apps. A parked Dock does the job through the system's
own machinery, before the window moves, for every app. The nudge is worth revisiting only as a
fallback, if a Dock showing through translucent bars turns out to matter more than all of that.

### 5.7 Trash

**`~/.Trash` is TCC-protected.** This is the finding that matters here, and it invalidated the
original plan. Without Full Disk Access:

- `FileManager.contentsOfDirectory` fails with `EPERM`, and
- `open(path, O_EVTONLY)` fails too, so the `DispatchSource` watch can never even be created.

Both failures used to land on the same answer as "there is nothing in there", which is why the Trash
read as permanently empty and never changed. Measured on macOS 26.6: enumerating `~/.Trash` returns
`NSCocoaErrorDomain 257` while `~/Documents` and `~/Desktop` enumerate fine, so this is the Trash
specifically, not a general sandbox.

What macOS does still allow is `stat`, both on the directory and on named children inside it. On APFS
a directory is a 64-byte header plus a 32-byte record per entry, and `st_nlink` counts every entry
(files included), so the entry count falls out of either number:

```
entries = (st_size - 64) / 32 = st_nlink - 2
```

Requiring the two to agree is what keeps this honest — on a volume laid out differently they diverge
and we report nothing rather than a guess. The housekeeping files are then subtracted by `stat`ing
them by name. Measured against Finder's own `count items of trash` on a machine with no Full Disk
Access: 11 raw entries − 1 `.DS_Store` = **10**, and Finder said 10.

- **State:** `DispatchSource` when the fd opens (Full Disk Access granted), and otherwise a 2s poll
  of the directory's `mtime`, re-counting only when it moves — paused while the displays sleep
  (§5.29), through `TrashWatcher.isPaused`. The snapshot carries `isExact` so a
  caller can tell a listing from an estimate. Consistent with §5.3, use the *system* trash icons
  (the empty/full pair Finder itself uses) rather than SF Symbols, so Trash matches the app icons
  beside it. SF Symbols `trash`/`trash.fill` are the fallback if the system pair proves unreliable
  to resolve.
- **Count:** drawn as a badge (§5.17), which is the same number Finder reports.
- **Drop:** `FileManager.default.trashItem(at:resultingItemURL:)` — preserves Finder's *Put Back*.
- **Empty:** no public API. `NSAppleScript` → `tell application "Finder" to empty trash`. Needs
  `NSAppleEventsUsageDescription` in Info.plist and, under Hardened Runtime, the
  `com.apple.security.automation.apple-events` entitlement. First use triggers one system consent
  prompt; if denied, fall back to opening the Trash in Finder and telling the user why.
  *Deliberately not* doing a raw `FileManager.removeItem` sweep — it bypasses the user's confirmation
  setting, ignores other volumes' `.Trashes`, and is unrecoverable.
- **The confirmation is ours** (`TrashPrompt`). Finder's `empty trash` command does not raise Finder's
  own dialog, so scripting it would otherwise erase the Trash on a single menu click — the one
  irreversible thing in the app, behind no question at all. The number of items is quoted only when
  `TrashSnapshot.isExact`; the metadata estimate above is good enough to badge with, but a dialog
  about permanent deletion must not present an inference as a count.

### 5.8 Persistence & settings

`~/Library/Application Support/Eskele/`
```
layout.json        pinned items (bookmark data + bundle ID), order, separators, per-item overrides
settings.json      edge, screens, thickness nudge, autohide, material, dock-suppression on/off
dock-backup.json   pre-suppression com.apple.dock values + clean-restore flag
```
Atomic writes, schema-versioned, with a `.corrupt` sidecar if a file cannot be read at all.

**Decoding is lenient per key, not per file.** `settings.json` is documented as hand-editable, and the
obvious implementation — `decodeIfPresent` with a `??` default — throws on a value that is present but
invalid, taking every *other* setting down with it. One typo in `edge` should cost `edge`. `layout.json`
decodes item by item and drops only the entries it cannot read, so a schema change costs one pinned
icon rather than the whole arrangement. Both are covered by tests.

**Restore Defaults, Export and Import** (*General ▸ Transfer and Reset*) all end in the ordinary
`AppDelegate.apply`, so nothing downstream can tell a reset from a click on a toggle. An export is
`Persistence.encode` of the settings in memory — the same bytes as `settings.json`, so the two are
interchangeable. Two rules are new, both in `SettingsFile`:

- **What a replacement may not touch** (`Settings.adopting`). `hasCompletedOnboarding`,
  `suppressSystemDock` and `reserveScreenSpace` describe the Mac rather than the bar: they are the
  consent onboarding asked for, given on this machine. A reset that cleared them would bring the Dock
  back mid-session; an import that set them would hide the Dock on a Mac whose owner said no. The
  Custom design is kept unless the file brings one, so a reset leaves the layout it replaced one click
  away under the Custom tile. And an import with both settings routes off gets the icon back, as
  launch does for a hand-edited file.
- **What is not a settings file** (`SettingsFile.read`). The lenient decoder makes `Settings` out of
  *any* JSON object, so `layout.json` would import as a flawless set of defaults — a reset reported as
  a success. Unknown keys cannot be refused outright, because a file from a later version may carry
  settings this one does not know. So most of the file's keys must be settings, counted by name
  (`Settings.recognisedKeyCount`, which has to live in `Settings.swift` because the synthesized
  `CodingKeys` is private to it). The case that sizes the rule is `dock-backup.json`: it shares
  exactly one key, `autohide`, out of seven.

### 5.9 Permissions

| Capability | Prompt | Needed for |
|---|---|---|
| Automation → Finder | Yes, once | Empty Trash |
| Accessibility | Yes, once | Window list, mitigation C — both optional |
| Full Disk Access | No | — |
| Screen Recording | No | Only if we ever add window thumbnails (avoid) |

The app must degrade gracefully with everything denied: no permission is required for the core bar.
A `PermissionsService` centralises status checks so the UI can show inline "grant" affordances rather
than failing silently.

**Signing identity is part of the permission story, and it bit us.** TCC does not remember "this app";
it remembers a *designated requirement*. An ad-hoc signature's requirement is the binary's own
`cdhash`:

```
designated => cdhash H"63b0dde56d81ec8c07b213d60ddd122f34d615da"
```

Every rebuild produces a new hash, so a permission granted in System Settings silently stops applying
the moment you rebuild — the symptom being an app that is listed and ticked under Accessibility while
`AXIsProcessTrusted()` returns false. Signing with any real certificate gives a requirement based on
the identifier and the leaf certificate instead:

```
designated => identifier "de.alhaidari.Eskele" and anchor apple generic
              and certificate leaf[subject.CN] = "Apple Development: … (TEAMID)" and …
```

Measured: changing the binary moved the cdhash from `c6af1d81…` to `5e288819…` while that requirement
stayed byte-identical. `Scripts/build-app.sh` now picks up a Developer ID or Apple Development
certificate automatically and only falls back to ad-hoc — with a warning — when there is none.

**A permission check reports the *responsible* process, not the caller.** This cost real time and
then nearly cost more: `--diagnose` run from a shell reported accessibility as denied while the app
plainly had it. Measured, with the same binary and the same signature:

| Launched by | `AXIsProcessTrusted()` |
|---|---|
| `exec` from a shell | `false` |
| LaunchServices (`open`) | `true` |

macOS attributes the check to whatever is responsible for the process, which for anything started
from a terminal is the terminal. There is no reliable in-process way to tell the two apart —
`isatty` fails as soon as the output is piped — so `--diagnose` states the ambiguity outright
whenever the answer is no, rather than guessing and sending someone off to re-grant a permission
they already hold.

**`Eskele --diagnose`** reports the bundle path, how the app is signed, whether the requirement is
cdhash-based, and each permission's status. It writes the same report to
`~/Library/Application Support/Eskele/diagnose.txt`, because the only launch path that reports
Eskele's *own* permissions is the one with no terminal to print to.

---

### 5.10 Auto-hide

The bar can slide entirely off its edge and come back when the pointer arrives, independent of the
system Dock's own auto-hide.

- **Reveal** is event-driven: an `EdgeTriggerWindow` — 2pt thick, spanning exactly as much of the edge
  as the bar itself — carries a tracking area and costs nothing while idle. 2pt rather than 1pt
  because the window server coalesces fast pointer motion. A global `NSEvent` mouse monitor would be
  the obvious alternative and is exactly the thing macOS gates behind Accessibility.
- **Hide** polls `NSEvent.mouseLocation` at 10Hz, but *only while the bar is out* — so the idle cost
  stays zero. A grace period (`hideDelay`) keeps the bar from vanishing as the pointer crosses it.
- **Interaction guard.** `BarContentView` keeps an interaction depth that is non-zero while a context
  menu is open or a drag is running. Auto-hide waits it out; nothing is worse than the bar sliding
  away underneath an open menu.
- **Hot key.** Carbon `RegisterEventHotKey` (⌃⌥D unless recorded otherwise) toggles reveal. Carbon
  because it is still the only route to a system-wide hot key that needs no permission. Recorded in
  the preferences — see §5.26.

### 5.11 Stacks and window lists

**Stacks.** Clicking a pinned folder lists its contents. This is an `NSMenu`, not a bespoke grid
panel: the Dock's own list view is a menu, and going native brings keyboard navigation, overflow
scrolling and correct screen-edge placement for free. Sub-folders become submenus populated lazily on
`menuNeedsUpdate`, so opening a stack never walks the tree. Capped at 40 entries with an "Open in
Finder" escape. A fan or grid presentation would be a separate view, not a variation on this one.

**Window lists.** A running app's context menu can list its windows, via `AXUIElementCopyAttributeValue`
on `kAXWindowsAttribute`. Minimised windows are indented, the way the Dock marks them; picking one
un-minimises and raises it. Entirely optional — without Accessibility the section collapses to a
single "Enable Window List…" item. AX elements are re-read when the choice is made rather than
captured when the menu is built, because windows close while menus are open.

### 5.12 Preferences, onboarding, login item

- **Designs** (`DesignPreset`) are the top section of the Appearance tab and the first item of the
  status menu: four one-click layouts — Dock, Classic, Unity and Custom — shown as miniatures. A
  design owns five layout settings plus the Trash and the Apps Menu, and nothing else; the defaults
  of `Settings` *are* the Dock design, so a fresh install opens with one selected rather than
  between them. The eight fields live in `DesignFields`, and `matches(_:)` is defined as
  "`applied(to:)` would change nothing", so the apply and match rules cannot drift apart — there is
  one list of fields, not two.
- **Custom is defined by exclusion**: a bar that is none of the shipped three is the custom one, so
  `matching(_:)` always answers rather than returning nothing. `Settings.captureCustomDesign()`,
  called from the one funnel every change comes through (`AppDelegate.apply`), stores the fields
  whenever that is true. One rule gives the whole behaviour: tuning a setting a design owns records
  the result — replacing whatever was under Custom — while *picking* a design writes settings
  without ever recording, so a stored custom design survives a trip through Dock and comes back
  intact. It is `nil` until the user makes one, which is what disables the tile.
- **The tiles are drawn from the settings** (`BarSilhouette`), not hand-drawn per design, so they
  cannot quietly stop describing what they apply. They are deliberately out of scale — a real bar is
  about 3% of the screen's height, which at tile size is a hairline — but they keep the ratio that
  carries meaning, Big being exactly 1.5x Small. The miniature has a `naturalSize`: its contents are
  fixed sizes a smaller frame does not shrink, so a full-height bar drawn into anything shorter
  spills out of its tile. The menu's smaller tiles scale it rather than squeezing it.
- **The status menu's design row** (`DesignMenuRow`) is a menu item with a custom view, because a
  menu cannot draw a row of pictures any other way. It sits inline under a section header at the top
  of the menu rather than behind a submenu: it makes the menu as wide as four tiles, which is the
  price of being able to read the current design without opening anything. Each tile is `BarSilhouette` rendered to an
  image with its name, shown by an `NSImageView` under a transparent `NSButton` that takes the
  click: a button asked to draw the image itself insets it by its cell's margins, which at this size
  is the difference between a name under the tile and no name at all. A click in a custom view does
  not dismiss the menu the way an ordinary item's does, so the row cancels tracking itself.
- **Preferences** is SwiftUI in an `NSHostingController`, in four tabs. An agent owns no windows, so
  showing it calls `NSApp.activate()` explicitly or it opens behind the user's work. The window is
  fixed-size: a `TabView` of `Form`s proposes no intrinsic height to its hosting controller, and
  without an explicit frame it comes up as a bare tab strip.
- **Settings flow** through a `SettingsStore` (`@Observable`). Edits in the UI go out via `onChange`;
  edits from the status menu come back in through `sync`, which does not echo — otherwise the two
  surfaces would drive each other in a loop.
- **Onboarding** runs once and exists for one reason: consent for taking over the system Dock. Its two
  buttons are "Keep Both for Now" and "Replace My Dock"; the latter turns on suppression *and*
  reserved space together, because separately they are hard to explain.
- **Login item** is `SMAppService.mainApp`. Its `requiresApproval` state (the user disabled it in
  System Settings) is surfaced rather than silently retried, since re-registering will not override it.
- **The menu-bar icon is optional** (`showStatusItem`). Hiding it removes the `NSStatusItem` outright
  rather than zeroing its length — a zero-length item still holds its slot and still reads as a gap
  on a crowded menu bar.
- **Its artwork is drawn, not bundled** (`StatusItemIcon`). The pier and one line of water, on the
  same 180-unit grid the app icon's layers use, for the reason `make-icon.sh` derives the .icns from
  those layers instead of drawing them twice: one set of coordinates to edit. It is a template image,
  so only its alpha reaches the screen — which is why the three ports are punched through the bar
  with even-odd winding rather than painted on top, where the system's single tint would swallow them.

**One route to the settings window must survive.** The status menu and the Apps Menu's gear (§5.15)
are the only two, and turning off both would leave `settings.json` as the sole way back — for an app
that may also be suppressing the system Dock, that is a corner the user cannot see themselves into.
So each toggle is disabled wherever it is the last one standing: in the preferences window, in the
status menu, and in the Apps Menu button's own context menu, each with a note saying why. That is a
UI rule, not a data one, so `AppDelegate` re-checks `Settings.hasSettingsRoute` on launch and puts
the icon back if a hand-edited file arrives with neither.

### 5.13 Full-screen spaces

Two separate questions, with two different answers.

**Can the bar reserve space in full screen? No.** Nothing reserves space inside a full-screen space
except the menu bar, and only when "automatically hide and show the menu bar in full screen" is off —
which is why a full-screen window on this machine is 923pt tall rather than 956pt. There is no
equivalent for the bottom, left or right edge, and the §5.6 Dock-reservation trick has no effect
there at all (measured; see §5.6). Reserved-space mode therefore covers maximised windows but not
native full screen. A user who wants the bar to never overlap anything should zoom windows rather
than send them full-screen.

**Can the bar get out of the way? Yes**, via `fullScreenBehavior`:

| Behaviour | Effect |
|---|---|
| Always Show | Floats over the full-screen window. The panel is `.fullScreenAuxiliary`, so this is free. |
| Reveal on Hover | Auto-hide (§5.10) turns on just for full-screen spaces — what the menu bar does there. |
| Hide | The panel is ordered out entirely until the space changes. |

**Detection needs Accessibility, and that is not a shortcut.** The permission-free approach — scan
`CGWindowListCopyWindowInfo` for a window covering the display — was implemented, measured, and
thrown away: an ordinary window the user has sized to fill the screen is geometrically identical to
a full-screen one. In testing it reported a plain editor window as full-screen continuously. Shipping
it would have meant the bar vanishing at random.

What works is `AXFullScreen` on the frontmost application's focused window, plus `kAXPositionAttribute`
to decide which display that is. Sampling is driven by `NSWorkspace.activeSpaceDidChangeNotification`
— which does fire, but **only for a bundled app**; an unbundled test binary never receives it, which
cost some time to work out. The space transition animates for about a second and AX reports stale
geometry until it settles, so each notification triggers re-samples at +0.4s and +1.1s.

Without Accessibility the monitor reports nothing, so the setting degrades to Always Show. Failing
towards "the bar is visible" is the right direction: the opposite failure is a bar the user cannot
find.

### 5.14 Item styles

Two ways to draw a cell, chosen by `itemStyle`.

**Icons Only** (`compact`, the default) is the dock idiom: one square per item, running state shown by
a short pill in the margin along the screen-facing edge — longer and more opaque for the frontmost app.

That indicator started as a 3.5pt dot in a 5pt *exclusive lane*, and the lane was the mistake: it came
straight off the icon, which in a 32pt bar meant 23pt icons where 27 were available. The indicator
does not need a band of its own. It now sits inside a 3pt margin that the icon is merely nudged away
from, and it is a 2pt pill rather than a dot — the same visual weight in half the thickness. Icons
gained 17%, and the indicator arguably reads better for being quieter. `iconPadding` still wins if
the user sets it larger than the margin.

**Icons with Labels** (`expanded`) is the taskbar idiom. Every *running* app becomes a button showing
its icon and name. A pinned app that is not running stays a plain icon — it is a shortcut, not a
task, which is exactly how Windows has drawn the distinction since 7. The indicator lane disappears
in this mode and running state becomes a button fill instead (frontmost darker), which both reads
better on a wide button and lets the icons grow into the reclaimed 5pt.

**Sizing** is a small flex solver, `BarLayoutSolver`, kept as a pure function because it is the part
most likely to be subtly wrong:

- Every cell has a **floor** — its icon-only width — that is never violated.
- A running app's **ceiling** depends on the span mode. In `fullSpan` it is exactly
  `expandedItemWidth` (140pt by default) whatever the name: uniform buttons are what make a row read
  as a taskbar rather than a ragged list, and long names truncate with an ellipsis. In `hugContents`
  the ceiling is `padding + icon + gap + text`, capped at the same number, so a short list stays
  compact instead of padding every button out to 140.
- If the ceilings fit, everyone gets them. Otherwise the surplus above the floors is shared in
  proportion to how much each cell wanted to grow, so buttons narrow *together* rather than the last
  few collapsing while the first stay full width. With uniform ceilings that proportional share is
  an equal share, which is exactly the taskbar behaviour.
- `expandedItemWidth` scales with `barSize` like the rest of `BarMetrics`, so the 140pt default
  becomes 210pt on a Big bar — which matches its larger icons and larger type.
- Cells sit flush against one another and fill the bar's full thickness, so all of a button's
  breathing room comes from `BarMetrics.backgroundInset` — the amount each cell insets its drawn
  slab on every side. Labelled bars use 2pt against an icon cell's 1pt: horizontally that puts 4pt
  between neighbouring buttons, vertically it keeps them off the top and bottom edges of the bar,
  which they otherwise sit flush against. It comes out of the drawn slab rather than the cell, so
  button pitch stays exactly as configured, and it is not scaled by bar size — a couple of points of
  separation reads the same either way. The running dashes shift inward by the same amount on a
  labelled bar, or they would hang outside the slab they belong to.
- Below roughly 30pt of growth a button has no room for text and reverts to a centred icon. When the
  bar is fully packed every cell is at its floor, which is pixel-identical to compact mode — the
  degradation the mode is designed around.
- Past that point the solver stops: sub-icon slivers help nobody, so the strip simply clips.

In `hugContents` the bar grows to its natural width and the solver only engages once it hits the
screen cap. In `fullSpan` the available length is the whole edge, so buttons take their ceilings and
the run is anchored by `itemAlignment`.

**Not available on vertical bars.** A left- or right-hand bar is one icon wide, and widening it to
fit labels would abandon the slim bar that is the premise of the whole project. `Settings.drawsLabels`
gates on this, the menu disables the option, and Preferences explains why.

### 5.15 Apps Menu

A launcher button pinned to the leading end of the bar, in the spirit of a Start button. It is a
first-class item kind (`DockItem.Kind.appsMenu`) rather than a pinned app: always first, never
draggable, and toggled by `showAppsMenu`.

**The popup was an `NSMenu` and is now a panel** (`LauncherPanel`, driven by
`LauncherPanelController`). The menu was the right answer while the launcher was only a list: it
placed itself correctly against any screen edge, scrolled when long, and took keyboard navigation
for free. A search field ends that. `NSMenu` runs its own event-tracking loop and keeps the keyboard
to itself, so no view inside a menu item can become the first responder — a search field in a menu
can be drawn but never typed into. Owning the window is the only way, and what it costs is
edge-aware placement and arrow-key navigation, both written out in `LauncherPanelController` and
neither of them large.

**Taking focus is the real price.** Nothing else in this app ever does: the bar is a
`.nonactivatingPanel` that answers `false` to `canBecomeKey`, precisely so clicking a cell does not
deactivate whatever the user was working in. A search field cannot work that way — an inactive app's
window receives no typing — so the launcher activates the app the way Spotlight does, and puts the
previously frontmost application back in front when it closes without launching anything. That
restore is skipped when something else has already taken the front, so dismissing the launcher *by*
clicking into another app does not snatch focus back out from under that click.

**A gear sits beside the search field**, and it opens the settings window. It is there because the
menu-bar icon is optional (§5.12) and this is the other way in. Closing the panel before opening the
window takes the same "handing the front to someone else" path as launching an app, so the
previously frontmost application is not restored into a fight with the window about to appear.

**A key opens it, because a Start button that only answers the mouse is half a Start button.**
macOS has no lone key for this — the Windows key's whole trick is being a key nothing else uses —
and the near misses are all spoken for: `⌃Space` and `⌃⌥Space` are input-source switching, `⌘Space`
is Spotlight, `⌥⌘Space` is Finder search, all on by default. Measured against a real
`com.apple.symbolichotkeys`, not assumed.

So `appsMenuHotKey` offers three, defaulting to **⌃Esc**:

| Choice | Why | How it is caught |
|---|---|---|
| `controlEscape` | Unassigned on macOS, and on Windows it *is* the Start-menu shortcut. Escape has no text-input role, so nothing is shadowed. | Carbon, no permission |
| `optionSpace` | What most launchers bind, so it is the one people arrive with. Takes over the non-breaking space `⌥Space` types. | Carbon, no permission |
| `rightCommand` | A lone modifier macOS assigns nothing, tapped on its own — the closest thing to a real Windows key. | `RightCommandWatcher`, **needs Accessibility** |
| `custom` | Whatever the user records (`appsMenuCustomHotKey`), for when the three above are taken. Kept when another choice is picked, so trying one does not lose it. | Carbon, no permission — §5.26 |

On by default, unlike the reveal and slot keys. Those are ten combinations likely to collide, or one
tied to a mode most people leave off; this is a single combination the system does not use, and a
launcher nobody can reach from the keyboard is not the feature that was asked for.

**Why the lone modifier is the one that costs a permission.** The other two are key combinations,
which Carbon registers for nothing (§5.10). A bare modifier is not a combination: there is no key
press to register, only a flag going up and coming back down, and seeing that from outside the
frontmost app means `NSEvent.addGlobalMonitorForEvents(.flagsChanged)`, which macOS delivers to
trusted processes alone. The permission-free trick §5.19's overlay chords use — polling
`NSEvent.modifierFlags` — cannot rescue it: a poll sees ⌘ appear and disappear during right-⌘S
exactly as it does during a tap, because the S is invisible without the same permission. The
preferences pane therefore reports the missing permission beside the choice rather than letting it
be discovered.

A tap counts only if right ⌘ goes down alone, nothing happens while it is held, and it is released
within 0.4s. `RightCommandWatcher` tracks the press as a *transition* rather than reading each
event's flags, because a second modifier joining in re-reports the ⌘ that is already held — read
naively, that restarts the clock on a press that should have been cancelled. Verified by posting
synthetic events at the HID tap: a bare tap opens the launcher, right-⌘S and a 0.8s hold do not.

**The key and the click open the same panel, anchored the same way.** `ScreenCoordinator` picks the
bar under the pointer — with several displays that is the one being looked at — and falls back to
the menu-bar screen. The anchor is measured against the bar's *shown* frame rather than its live
window frame, because a hidden bar is revealed first and revealing animates: read from the window
mid-slide, the launcher would hang off wherever the bar had got to. The bar's interaction depth is
held for as long as the panel is open, so an auto-hiding bar does not slide away underneath it.

**Three sources**, chosen by `appsMenuSource`:

| Source | Where it comes from | Order |
|---|---|---|
| Favourites | The apps pinned to the bar. No second list to curate — pinning *is* favouriting. | Bar order |
| All Apps | A scan of the application folders. | Grouped by category |
| Recent Apps | An MRU list we maintain ourselves. | Most recent first |

**Only All Apps is grouped.** The other two are short, and their order *is* their answer — recency
for one, the arrangement of the bar for the other. Grouping either would destroy the thing being
asked for. `LauncherContent` is the pure function that decides this, and it is where the rule is
tested.

**Categories come from `LSApplicationCategoryType`,** the only categorisation a Mac app carries, and
coverage is partial: of the 105 apps found here, 74 declare one. Two rules keep the remainder from
swamping the list. Apps in a `Utilities` folder take that as their category — a small number, but
they are the system tools nobody would think to look for under "Other". Far more important,
background agents are dropped from the catalogue entirely (§ above): they are not things you launch,
they declare no category, and there are more of them installed than there are apps — scanning
without that filter turned up 240 bundles and an "Other" of 142. With it, "Other" is 29. What stays
undeclared lands there, and it sorts last rather than alphabetically between News and Photography.
The nineteen App Store game genres collapse to one "Games", and an identifier this build has never
heard of is title-cased from its own name rather than thrown into `Other`.

**Search flattens the groups.** A search is already a filter, and grouping five results under four
headings is more chrome than answer. Matches are ranked — the name that *starts* with what you
typed, then a name whose second word does, then initials (`vsc` → Visual Studio Code), then anything
containing it — and the ranking is a pure function with the ordering pinned by tests, because "why
is Xcode above Visual Studio Code" is otherwise unanswerable. Case and accents are folded.

**All Apps scans directories** rather than asking Launch Services, which answers "what can open this
file?" rather than "what is installed", or Spotlight, which may be disabled. Each root plus one level
down — enough for Utilities, never descending into a bundle, which is itself a directory. Duplicates
are collapsed by bundle filename with the earlier root winning, so a user's own copy shadows the
system one. `/System/Library/CoreServices` is *not* a root: it was only ever there for Finder, and
scanning it turned up 39 bundles of which two were apps anyone would launch. Finder is named
explicitly instead, and the user-facing `CoreServices/Applications` — Keychain Access, Wireless
Diagnostics, About This Mac — is scanned in its place. The scan runs off the main actor and is cached
for two minutes: ~105 apps here, and a file-system walk on the click that opens the launcher would be
felt. It reads each bundle's `Info.plist` directly rather than through `Bundle`, which would load and
cache a hundred-odd bundles for two keys, and it now reports back through `onChange` so a launcher
opened mid-scan fills itself in instead of sitting on "Still looking…".

**Rows are 40pt with 28pt icons**, against the menu's 16pt. The old list was a menu because it was a
menu; a launcher that is the first thing you click deserves a target you can hit.

**Recent Apps is ours** because the Dock's own recents live in a shared file list with no public read
API. Observing `didActivateApplicationNotification` costs nothing. The list is capped at 20 and
persisted, and it is seeded from whatever is already running at first launch — a launcher that is
empty until you have switched apps a few times reads as broken rather than new.

**The button's glyph is the one piece of our own chrome in the bar.** Everything else is somebody's
real app icon; this is an SF Symbol tinted to the menu bar's label colour, which means it must be
re-rendered when the effective appearance flips. `BarContentView.viewDidChangeEffectiveAppearance`
handles that, and the icon cache is keyed by appearance name as well as size.

### 5.16 Multiple windows

An app with several windows was previously indistinguishable from one with a single window.

**Counts come from Accessibility.** The permission-free alternative was measured and rejected:
counting `CGWindowList` entries picks up helper and panel windows, and against AX ground truth it
over-reported consistently — Mail 2 windows against 0, Steam 2 against 0, Code 3 against 1. AX is
also cheap enough: a full sweep of eight running apps took **12.4ms**.

`WindowInfoService` caches each app's windows. Updates are **event-driven**, via a `WindowObserver`
that registers AX notifications per application (`AXWindowCreated`, `AXFocusedWindowChanged`,
miniaturise/deminiaturise) and per window (`AXUIElementDestroyed`, `AXTitleChanged`). All five were
observed firing. A 5s sweep remains as a safety net for apps whose Accessibility support does not
deliver them.

This started as a 2s poll, which showed as a visible 1–2s lag. Fixing it turned up three separate
costs, none of them the one being blamed:

1. **The AX notification was never the problem** — measured at 70ms from action to callback. The
   delay was entirely in the refresh that followed.
2. **Re-registering window notifications on every sweep cost ~1s.**
   `AXObserverRemoveNotification` against a window that has since closed blocks until the messaging
   timeout, and a closed window is precisely what triggers a refresh. Registration is now additive:
   registrations die with their element, so there is nothing to unregister.
3. **One slow application serialised everything.** Timing each app individually: every native app
   answered in 0–4ms, while one non-native app took 280–330ms on its own. Three changes followed —
   the observer reports *which* pid changed so only that app is re-read; the focused-window lookup
   runs only for the frontmost app, since no other app's windows draw as active; and the messaging
   timeout came down from 250ms to 120ms.

Slow apps are also backed off in the safety sweep — one that answers in over 100ms is skipped for the
next five sweeps, since its own notifications still update it immediately.

Measured after: window **open 424ms** end to end (including the app's own time to create it),
**close 194ms**, and the safety sweep down from ~1000ms to **16–20ms**.

**Hovering names the window, not the app.** `NSView.toolTip` is not used: AppKit's tooltip manager
expects an ordinary app with an ordinary key window, and this bar is a borderless, non-activating
panel belonging to an agent that is never active. `HoverTooltip` is our own panel, which also means
it can sit against the bar's screen-facing edge rather than at the pointer, and be clamped to the
display — a cell at the end of a full-width bar is exactly where the longest titles are. It shows
the focused window's title, falling back to the app's name when nothing is open. The window *count*
is left to the dashes; saying it again would cost the label the only line it has.

**One dash per window**, up to four, sized by `WindowIndicator`:

- A single dash keeps exactly the length it had before this existed, so the common case is unchanged.
- Extra dashes shrink rather than widening the group past 85% of the icon. A test asserts that,
  and caught a real bug: rounding the fitted dash length *up* pushed the recomputed total back over
  the ceiling. It rounds down.
- Zero windows still draws one dash. Without Accessibility every count is zero, and an app that is
  running must not read as having nothing open.
- Labelled bars normally show running state as a button fill and draw no dashes — but a *count* is
  something a fill cannot express, so multi-window apps get dashes in both modes.
- On the frontmost app the focused window's dash is bright and expanded to the length a
  single-window frontmost app's dash has. Its siblings shrink to dots at the level a background
  app's dashes use, so the long bright dash means "the window you are on" whether the app has one
  window or four. Brightness alone was too quiet a difference: at three or four windows the dashes
  are already short, and one short bright dash among dim ones is easy to miss, whereas the length
  difference reads at a glance. The group's total length does not depend on which dash is
  expanded, so it stays put while you cycle. The dashes follow `windowsByPID`'s title order, the same order `cycleOrder` steps through, so
  a click moves the long dash one place along. When focus cannot be placed (an untitled or
  duplicate-titled window, or one past the cap), every dash stays bright, as it did before. Lighting
  the last dash would name a window it does not stand for, and dimming them all would make the
  frontmost app look like a background one.

**Clicking gains a step.** Not running → launch. Running, not frontmost → bring forward. Frontmost
with one window → hide, as before. Frontmost with several → cycle to the next window, which is what
⌘` does and is more useful than hiding an app the user is evidently still working in.

**Two of those cells used to do nothing at all**, which read as "the app is semi-closed and clicking
does not open it". Both involve an app that is running with nothing on screen — closed all its
windows, or minimised them, which on macOS leaves the process alive. Measured on this machine: Mail
and Finder were both in that state.

- Not frontmost → `NSRunningApplication.activate()` moved the menu bar and opened no window.
- Frontmost → `cycleWindow` needs more than one window, so it fell through to `hide()`, and hiding an
  app with nothing on screen is invisible.

The real Dock does not activate in either case: it asks LaunchServices to *open* the app, which sends
`kAEReopenApplication`, and AppKit's default handler is what gives a windowless app a window back and
un-minimises an all-minimised one. `NSWorkspace.openApplication(at:configuration:)` is therefore now
the call for every "bring this app forward", running or not — it also sidesteps the cooperative
activation rules that can quietly drop an activation requested by a background agent. `ActivationPolicy`
holds the matrix, pure and tested.

The count that decides this is *un-minimised* windows, and it is `nil` rather than zero when
Accessibility has not been granted: without the permission every app reports zero windows, and
reading that as "nothing open" would turn click-to-hide into click-to-reopen for everyone who has not
granted it.

**A window button whose title has moved on** was the other dead click. Windows are re-found by title
at click time (there is no stable identifier — see above), so a button drawn before a rename finds
nothing and returned `false` into a discarded result. It now falls back to activating the owning app.

**And a click that slipped.** `mouseUp` required the release point to be inside the cell, but a
movement under the 4pt drag threshold never becomes a drag either — so a press near a cell edge that
drifted two points outside was swallowed entirely, in both directions. A release counts as a click if
it is inside the cell *or* the pointer barely moved.

#### One button per window

In full-width labelled mode (`splitsWindows`) each window becomes its own task, titled with
`kAXTitleAttribute` — so a Safari button reads the page name rather than "Safari". Grouped buttons
remain the behaviour everywhere else, because a hugging bar has no room to spread out and an
icons-only bar would show a row of identical icons saying nothing about which window is which.
`separateWindows` turns it off for people who prefer grouping.

Three details that are easy to get wrong:

- **Ordering is alphabetical by title, not AX order.** AX returns windows in z-order, which changes
  every time the user switches between them — laying buttons out that way would make them shuffle
  around as you work.
- **Only the focused window draws as frontmost.** Otherwise every window of the active app lights up
  at once. That costs one extra AX call per app to read `kAXFocusedWindowAttribute`.
- **Identity is `pid` + title + a duplicate counter.** The only stable window identifier macOS
  exposes is behind a private symbol, so windows are re-found by title at click time. Two windows
  sharing a title are distinguished by order, which is the best available without that symbol.

Titles refresh on the same 2s poll as the counts, so a button can lag a page navigation by up to two
seconds.

#### Full-screen windows

**`kAXWindowsAttribute` only ever lists the windows of the *active* Space.** This is the finding, and
it took three wrong guesses to reach. Measured on macOS 26.6 with VS Code holding one ordinary window
and one full-screen window in a Space of its own, queried from the ordinary Space:

```
AX: 1 entries          →  todo • Untitled-1 — eskele
window server: 2       →  1470x874 on-screen
                          1470x923 off-space display-sized
patient AXWindows (2s timeout): 1 returned, 1 advertised (AXError 0)
after AXManualAccessibility:    1 entries
app AXChildren:                 AXMenuBar×1 AXWindow×1
```

So it is not the messaging timeout (a 2s one returns the same), not Electron's lazy accessibility
tree (`AXManualAccessibility` and `AXEnhancedUserInterface` change nothing), and not the title filter
that was blamed first — the app *advertises* one window and its children hold one `AXWindow`. There
is no public API that crosses a Space boundary.

**Measured, with a control.** A throwaway app with *two* windows — one ordinary, one full-screen in
its own Space — driven from the ordinary Space. Two windows matter: with one, activating the app
follows it into full screen all by itself, and every route looks like it works.

```
0. activate only:            B on screen=false     ← what the bar did; the reported bug
1. AXRaise + activate:       B on screen=true
2. activate + menu press:    B on screen=true
```

Route 2 pressed *before* activating reached nothing, so the order is part of the finding. Three
things follow, in order of how good the answer is:

1. **`AXFocusedWindow` and `AXMainWindow` are not bound by the Space.** Measured in the same session:
   `AXWindows` listed `todo • Untitled-1` while `AXFocusedWindow` returned `SteamLibrary.md —
   filedeck`, the full-screen window, as a real element with a real title. Folding those two
   attributes into the list recovers such a window properly — named, and raisable. It costs two AX
   round trips per app, which §5.16 spent real effort removing, so it is asked for only where the
   window server says there is something to find.

2. **The window server sees every Space and needs no permission**, but `CGWindowList` cannot be
   trusted wholesale — its off-Space entries are mostly ghosts. Measured: cached panels at 500×500,
   800×600 and 420×632 belonging to apps whose real window count was zero. One narrow slice is
   reliable: an off-Space, layer-0 window the size of a whole display. None of the ghosts come near
   it, and a merely zoomed window stops short of the menu bar *and* the Dock — 874pt against a
   full-screen window's 923pt on a 956pt display — so the two ranges do not touch. Bounded above as
   well as below, or an oversized window on a large display would read as full-screen on a small one.
   `SpaceWindowService` does this, and a test pins the measured ghosts as rejections.

3. **An element, once held, stays valid.** A window drops out of `AXWindows` when you leave its
   Space, but the `AXUIElement` you already have keeps working — so every full-screen window AX ever
   reports is cached per app, validated on each use by reading its title (which is also how a closed
   window is pruned). This is what makes the button *work* rather than merely appear: measured
   behaviour is that activating an app goes to whichever window is already its front one, so an app
   holding both an ordinary and a full-screen window always activated onto the ordinary one.
   `AXRaise` on the cached element makes the full-screen window the front one first, and the
   activation then follows it into its Space. Order matters; activating first is the broken case.

   The cache fills itself: the first time the user is in that full-screen Space with Eskele running,
   the window is an ordinary `AXWindows` entry and gets remembered.

4. **The app's own Window menu lists what Accessibility will not.** Measured on VS Code from the
   ordinary Space: `AXWindows` returned one window while the Window menu held both, the full-screen
   one with its real title. Menu items are pressable, and route 2 above shows that carries across the
   Space — so this reaches a window from a cold start, which the element cache cannot. The menu is
   found without knowing its name, since localisation would make that unreliable: it is the menu
   whose trailing run of items contains a window we already know about, and that same match is the
   proof it is the window list rather than some other group.

5. **What is left gets a stand-in.** A full-screen window the window server counts and no element was
   ever obtained for becomes a button named after its app and marked unreachable. Clicking it
   activates the app — what the system Dock's own icon offers for a window on another Space. The
   count subtracts the windows AX did recover, so the same window is never both named and stood in
   for.

Separately, the listability filter was on a non-empty `kAXTitleAttribute`, which drops toolbars
correctly and full-screen windows incorrectly, since many report no title once they have a Space.
It is now on **subrole**: listable if it has a title *or* its subrole is `AXStandardWindow`. An
untitled window borrows its application's name.

#### Reaching a window and judging a Space pull in opposite directions

The two features above read the same signal and want opposite things from it: the button needs
off-Space windows *in* the list, and the full-screen verdict needs them *out*. Getting one right by
itself breaks the other, and it did — twice, in both directions. `isOffSpace` is the seam. Every
window recovered by any route other than `AXWindows` carries it; the list keeps them, the verdict
drops them, and `unreachableCount` subtracts them so nothing is both named and stood in for.

**"An app has a full-screen window" is not "this display is in full screen", and conflating the two
breaks the ordinary desktop.** Once off-Space windows started being folded into the window list, both
routes to the full-screen verdict began counting them:

- the sweep, which took every `isFullScreen` window's position and marked its display, and
- `FullScreenMonitor`'s frontmost check, because `AXFocusedWindow` is not bound by the Space either —
  an app's focused window is quite often a full-screen one the user is not currently looking at.

The visible symptom was a bar with auto-hide *off* auto-hiding on the desktop, and the "In Full
Screen" setting appearing to govern ordinary-desktop behaviour: `effectiveAutohide` is
`autohide || (isFullScreen && behaviour == .revealOnHover)`, and `isFullScreen` was simply wrong.

The test for "on the Space we are looking at" is the same finding that started all this: `AXWindows`
lists the active Space and nothing else. So a window recovered any other way is off-Space by
construction and carries `isOffSpace`, only `showsActiveSpaceFullScreen` counts towards the verdict,
and the frontmost check now requires its focused window to appear in `AXWindows` before believing
anything it says. `--diagnose-windows` prints the resulting verdict, so "displays in a full-screen
space" can be read off directly rather than inferred from behaviour.

`WindowRef` carries `isFullScreen` from the undocumented but long-stable `AXFullScreen` attribute.
The window list marks such entries "(Full Screen)", because picking one switches Spaces rather than
raising a window in front of you, and §5.13's detection unions the frontmost-app check with the
displays found during the sweep — so an app full-screen on a second display is noticed too.

### 5.17 Number badges

**No *API* reads another app's badge — but the Dock will tell you.** `NSDockTile.badgeLabel` is set
in-process and handed to the Dock over a private channel, and the only system-wide cache is
`~/Library/Group Containers/group.com.apple.usernoted/`, which is undocumented private storage *and*
TCC-protected (verified: `EPERM` without Full Disk Access). That was where this section stopped.

The way through is that **the Dock is an ordinary application**. Its tiles are ordinary Accessibility
elements — `AXApplicationDockItem` under one `AXList` — and each one carries an `AXStatusLabel`
holding exactly the string the Dock is drawing. Measured on 26.6:

- A test app setting `badgeLabel = "7"` read back as `AXStatusLabel = "7"`, and following it through
  a cycle of values tracked every change.
- Mail, unprompted, went `nil → "1" → nil` across a message arriving and being read.
- Both while Eskele had the Dock suppressed — a hidden Dock still publishes its tree.
- Accessibility is the only permission involved. No Screen Recording, no Full Disk Access.

**It has to be polled.** Registering on the Dock for `AXValueChanged`, `AXTitleChanged` and
`AXLayoutChanged` all return `kAXErrorNotificationUnsupported` (-25207), and nothing fires when a
badge changes. `AXUIElementDestroyed`, `AXCreated` and `AXSelectedChildrenChanged` do register, but
say nothing about badges. A full sweep of every tile measured at **0.78 ms**, so `DockBadgeReader`
re-reads the lot every 2s and skips the bookkeeping that tracking individual tiles would need. It
only runs while *Show Badges* is on.

Tiles are matched to apps by `AXURL` — the app's location — rather than by `AXTitle`, which is
localised and not unique. The URL-to-bundle-ID map is cached, since resolving one reads an
`Info.plist`.

**The two gaps, both honest.** A badge that is not a number — the bare dot a few apps use — has no
number to draw and is reported as none. And a badge lives in the *Dock's* process, so restarting the
Dock loses it: measured, an app that set its badge before the restart shows `AXStatusLabel = nil`
afterwards, because macOS does not re-push it. Eskele restarts the Dock in order to hide it, so a
count already standing at launch stays missing until the app next changes it. This is what any
`killall Dock` does, and nothing can ask an app to re-publish.

So Eskele draws, in order:

- **The real badge**, for any app the Dock is badging. Nothing to configure.
- **The Trash counts itself**, exactly (§5.7).
- **`badges.json`** in Eskele's support directory, for the rest: a bundle ID, a shell command, and an
  interval. The first run of digits in the command's output becomes the badge; no output, a non-zero
  exit, or a zero means no badge — and in that case the real badge is drawn instead. A command that
  *does* answer wins its cell, so it overrides as well as supplies: it is the explicit instruction,
  and it means an existing user's configuration keeps behaving as it did. The file is seeded on
  first run with a Mail and a Reminders example under keys the decoder ignores — JSON has no
  comments — both of which count something slightly different from what those apps badge.

`--diagnose-badges` prints every tile, its raw `AXStatusLabel`, the bundle ID it resolved to and the
merged result, for the same reason `--diagnose-windows` exists: a missing badge has several
indistinguishable causes from outside — no Accessibility, an app that is not badging, a badge with
no number in it, or a tile that could not be matched.

Commands run through `/bin/sh` off the main thread, one at a time per source, with a 10s watchdog:
an `osascript` that raises an Automation prompt will otherwise sit there indefinitely, and the bar
must not. Nothing runs until the user puts something in that file. The trust model is a shell
profile's — the user's own commands, on the user's own machine.

Drawing is a red capsule on the icon's outward top corner, in both item styles, clamped inside the
cell's own slab: on a bar exactly as thick as its icons, an unclamped badge welds itself to the top
edge of the screen. Counts past 99 read "99+". The number is repeated in the tooltip, since at Small
scale the capsule is about 12pt tall.

#### Tooltip sizing

`NSTextField.intrinsicContentSize` reports the width of the glyphs and nothing else, while
`NSTextFieldCell` insets the text it *draws* by 2pt on each side. A label framed from the intrinsic
width is therefore 4pt short of what it takes to draw itself, and `.byTruncatingTail` does not
degrade gracefully over 4pt — it drops characters and appends an ellipsis, which is how a 45pt-wide
"Terminal" came out as "Ter…". `HoverTooltip.contentSize(of:showing:maximumWidth:)` measures with
`cellSize` instead, and the test asserts the result is strictly wider than the glyphs alone, since
that is exactly what the broken version was not.

### 5.18 Attention

**A bouncing Dock icon cannot be observed.** `NSApplication.requestUserAttention` goes to the Dock
over the same private channel the badge in §5.17 travels: no notification, no `NSRunningApplication`
property — and, unlike the badge, no AX attribute on the tile either. A literal "is it bouncing?" is out of reach and there is no honest way to
fake it.

What is reachable, with the Accessibility permission the window list already needs, is the thing
bouncing usually accompanies — the app has put a modal in front of the user while they were working
somewhere else:

- **A dialog window**, subrole `AXDialog` or `AXSystemDialog`. Re-checked by every sweep, so it
  clears itself the moment the dialog goes.
- **A sheet**, which is a child of its parent window rather than an entry in the window list, so
  `kAXSheetCreatedNotification` is the only trace we ever get of one. That one is latched, and
  cleared when the user next activates the app — the same moment a bouncing icon would stop.

An app that is frontmost never needs attention: the user is already looking at it. Leaving an app
also recomputes, because the app you just left may have a dialog that only counts now that it is
behind you.

Verified end to end on macOS 26.6 with `--diagnose-windows` (§5.20): a background app showing an
`NSAlert` reports one AX entry, subrole `AXDialog`, and is flagged. Note it is *not* listable — a
dialog gets the glow, not a task button of its own.

**One shape of dialog is invisible to this, and it is worth knowing which.** AppleScript's
`display dialog`, even inside a `tell application "Finder"` block, is not drawn by the target app at
all: measured, the window belongs to **`UserNotificationCenter`**, a separate CoreServices process,
so it never enters Finder's AX window list. The same goes for other system-presented alerts. Only
dialogs an app owns itself are detectable — which is the large majority of the ones that matter, but
not all of them.

### 5.20 `--diagnose-windows`

`--diagnose` explains permissions; this explains what Accessibility actually *says*. The AX-dependent
features are the ones whose bugs are invisible from outside — a window silently missing from a list
looks exactly like a window that does not exist — so the flag prints, for every running app, its AX
entries with subrole, listability, full-screen and dialog flags, and whether the app would be flagged
as needing attention.

Like `--diagnose` it exits before the delegate is built, so it touches neither the Dock nor the
status item, and it has to be run through LaunchServices to report Eskele's own permissions rather
than the terminal's. It is also strictly read-only: an earlier version probed whether Chromium's
lazy accessibility tree was to blame by *setting* `AXManualAccessibility` on other apps, which is not
something a diagnostic should do to somebody else's process. That probe, and the ones for the
messaging timeout and the application's `AXChildren`, were one-off questions; they are answered
above and the code that asked them is gone.

The cell glows amber — deliberately not the accent colour, which already means "drop target" —
pulsing on a 1.6s sine driven by a 10Hz timer that runs only while something is actually asking, and
redraws only the cells that are.

### 5.19 Groups and reordering

**Pinned apps in labelled mode.** A pinned app that is not running is a shortcut; a running one is a
task. Left interleaved, the shortcut sits among the labelled buttons looking like a button that has
lost its label. In labelled mode they are hoisted into a compact tray at the leading end — pinned
apps, folders and files, plus the separators the user placed among them — with a divider between the
tray and the task run. Icons-only mode is untouched: there a launcher and a task are drawn
identically, so separating them would move icons about for no reason.

`BarComposition` does the partition and the assembly, pure and separately tested, for the same reason
`BarLayoutSolver` is: three buckets, two item styles, and a divider that must appear only when it has
something on both sides of it.

**Reordering.** Three kinds of thing get dragged, and each has its own notion of position:

| Dragged | Position lives in | On drop |
|---|---|---|
| A pinned item | `layout.json` | Rewrites the stored order |
| A running app with no stored slot | memory | Reordered if dropped among the other running apps; **pinned** if dropped anywhere else, which is what dragging it into the pinned run plainly means |
| A window button | memory | Reordered within its own app; dragged clear of its app's run it moves the whole app instead |

The in-memory orders are deliberately not persisted: an app that is not pinned has no place on the
bar once it quits, so an arrangement of them cannot outlive the session that made it. That is the
bargain the Windows taskbar strikes too.

Window buttons used to refuse to drag at all, which made "reorder the bar" false in exactly the mode
where the bar is most crowded. They drag now.

**⌘-drag means move, never remove.** A plain drag off the bar still unpins, as before — but while
rearranging a full-width bar the pointer strays outside constantly, and losing a pinned app to a
slipped drag is not a good trade. Holding ⌘ suppresses both the disappearing-item cursor and the
removal.

`ReorderSolver` holds the arithmetic, pure and tested, because an off-by-one in a drag is invisible
until somebody drags something — and by then it has already scrambled their bar.

### 5.21 Rows

The bar wraps into up to five rows, as uBar's draggable edge does. On a full-width taskbar with thirty
windows it is the only answer that keeps the labels: `BarLayoutSolver.lengths` narrows the buttons and
then collapses them to icons, and past that point the strip simply clips.

**The thickness is fixed at the row count, not fitted to the contents.** A bar that grew a row when an
app opened would resize under the pointer, and with reserved screen space (§5.6) it would re-park the
system Dock every time, restarting it. So the rows are asked for rather than earned:
`barRows` says how thick the bar is, and `BarLayoutSolver.rows` decides what goes where inside it.

**Cells spread evenly across the rows rather than filling each in turn.** Each row aims at an equal
share of the total; a cell is taken when it leaves the row closer to that share than leaving it out
would. Filling greedily would leave a three-row bar showing one row of icons and two empty strips,
which reads as a bug rather than as a setting.

`rows` is deliberately blind to how long the bar actually is. Wrapping at the bar's length instead —
which is what it did first — gives thirty buttons on a two-row bar ten comfortable ones and twenty
crammed into what is left, since the first row fills before the second starts. An equal share gives
fifteen and fifteen, squeezed alike. A row longer than the bar is then `lengths`'s problem, which is
what `lengths` is for. It also means the split needs no length to compute, which is what lets
`preferredLength` ask for it *before* there is one.

Each row is then solved by `lengths` on its own, against the full length of the bar: a row is a bar's
worth of cells, and the row above it neither lends nor borrows width.

**Rows stack in reading order** — downwards on a horizontal bar, rightwards on a vertical one, where
they are columns instead. The axis is the only thing that changes; `BarMetrics.thickness` is one row
and `totalThickness` is the window's. Every cell is drawn from the row thickness, so a two-row bar is
two rows of ordinary cells rather than one row of enormous ones, and each row keeps its own indicator
lane along its own screen-facing edge.

The pin tray (§5.19) is drawn once per row rather than once per bar. A pin group long enough to wrap
would otherwise be given a single union rectangle spanning both rows end to end, swallowing everything
between them.

### 5.22 One bar per display, or one bar per display's windows

`screenMode` has three settings: the same bar everywhere (uBar calls this Mirror, and it is our
default), a bar on every display showing only the tasks whose windows are on it (uBar's default), or
the main display only.

`BarComposition.onDisplay` is the filter, and it filters **tasks only**. The launcher, the pinned
shortcuts, the Trash and the clock carry no display at all: a shortcut is not on a display the way a
window is, and a second bar without a launcher on it would be a worse bar. The divider the strip
inserts for itself is dropped on a display where no task landed, where it would be a line at the end
of the pins.

**A task nobody could place is shown on every bar, not on none.** Empty is the value for a task with
nothing open, a window on a Space we cannot reach, and — the case that matters — every task on a
machine without Accessibility. Showing it everywhere makes the mode degrade to Mirror rather than to
an empty bar; losing an app off every bar is the one outcome worth ruling out.

**Which display a window is on costs an Accessibility read per window.** `kAXPositionAttribute` on
each window, against the four attributes the sweep already reads — so it is asked for only by this
mode, and only when there is more than one display to tell apart (`WindowInfoService.tracksDisplays`).
The origin decides, not the centre: the centre costs a second read for the size, and a window
straddling two displays has no right answer anyway, only a consistent one. This is the same rule
§5.13 has always used for full-screen detection.

`CGWindowList` would give the same geometry for free and without the permission, but its window names
need Screen Recording, so its entries cannot be matched to the AX windows the bar is actually built
from — and per-window buttons (§5.16) are exactly the case this mode has to get right.

**Two things stop being the same list once a bar is filtered**, and both had to follow:

- *Drop positions.* `BarContentView` numbers its own cells; `DockModel` numbers all of them. The
  delegate translates through the item on the far side of the drop — dropping before a cell means
  dropping before that same cell in the strip — rather than passing an index that means something
  different at each end.
- *Slot numbers* (§5.19's positional hot keys). One global key set addresses the whole strip, so the
  numbering is assigned there, in `DockModel.rebuild`, and carried on the item. A filtered bar then
  draws gaps — 1, 3, 6 — which is truthful, where renumbering its own cells 1, 2, 3 would have the
  overlay disagree with the keyboard.

### 5.23 Progress in the tile

A cell that has something under way fills up. Three sources, one shape (`ProgressReport`), and two
ways of drawing it.

**Media players are asked, because nothing tells us.** `MPNowPlayingInfoCenter` publishes *your own*
process's now-playing information; there is no public reader for anyone else's. The private route,
`MRMediaRemoteGetNowPlayingInfo`, is worse than unavailable — measured on macOS 26.6, the framework
still `dlopen`s and every symbol still resolves, but an unentitled process gets a nil info dictionary
and then no further callbacks at all. It has needed `com.apple.mediaremote.set-playback-state` since
15.4. What is left is the players' own scripting interfaces, which are public, documented and exact:
Music, Spotify and VLC each answer `state|position|duration` in one Apple event. That costs an
Automation consent per player, so it is opt-in — the same bargain window previews strike with Screen
Recording, and the second and last time Eskele trades a permission for a feature.

*Asked rarely, drawn smoothly.* An Apple event into another process is far too expensive to send at
the rate a progress bar wants to move. `ProgressService` samples every four seconds and `MediaPosition`
extrapolates between samples — a playing track advances one second per second — resnapping on every
sample, so a seek is wrong for at most one interval and nothing accumulates drift. The redraw clock
runs only while something is actually playing, and only republishes when the fraction has moved far
enough to change a pixel.

*The scripts answer in whole milliseconds, and that is not a detail.* AppleScript coerces a real to
text using the **system's** decimal separator, so a German-locale Mac answers `268,605987548828`
where an English one answers `268.605987548828`. `Double(_:)` reads only the second. Shipped that
way, media progress did nothing at all across most of Europe — with the player running, Automation
granted, the script exiting 0 and a well-formed reply on stdout, which is as invisible as a bug gets;
it took `--diagnose-progress` printing the raw stdout to see it. Each script now does its own unit
conversion and truncates with `div 1`, because an integer has no separator to disagree about. That is
also why the per-player unit differences — Spotify reports a position in seconds and a duration in
milliseconds — live in the scripts rather than in a table on this side. `MediaPlayer.milliseconds`
stays lenient about both conventions anyway, and a test pins the German reply.

**File operations are observed, and cost nothing.** `Progress.addSubscriber(forFileURL:)` is public,
needs no permission, and genuinely works across processes: measured here, a progress published by one
process arrives in another with its fraction, its operation kind and its localised description.

Two measured limits shape what could be built on it:

- *It carries no publisher.* There is no bundle identifier, no pid, nothing naming the app doing the
  copying. So a download cannot be put on the downloading app's tile. Eskele puts it where it *can*
  be attributed — on the cell for the folder the file is landing in.
- *It matches one URL exactly.* Subscribing to a directory reports nothing about the files inside it;
  the handler is simply never called. So each folder cell is watched with the same `O_EVTONLY`
  `DispatchSource` `TrashWatcher` uses, and every file in it that was touched recently gets its own
  subscription, capped per folder.

This is emphatically not "show me what the Dock shows". A Dock tile does publish its own progress as
`AXProgressValue`, alongside the `AXStatusLabel` §5.17 reads — but a bare fraction names neither the
file nor the operation, which is most of what the folder cell is for.

`--diagnose-progress` runs every source for real and prints what each answered, for the same reason
`--diagnose-windows` exists: a bar that does not appear has four indistinguishable causes from the
outside — the player is not running, it is not one we know, its consent was refused, or the track has
no duration — and telling them apart from the UI is impossible.

**Commands are the catch-all**, exactly as they are for badges: a build, a render, a backup, anything
not scriptable. `progress.json` mirrors `badges.json` key for key. A number above 1 is read as a
percentage and 0–1 as a fraction, which makes `1` mean *finished* — the reading that matches "1 out
of 1" — and a trailing `%` settles it explicitly either way.

**Two idioms, because the two item styles have different room and different conventions.**

| Style | Drawn as | Why |
|---|---|---|
| Icons only | A track and fill along the screen-facing edge, in the running dashes' lane, *instead* of them | Three points of margin holds one thing. An app part-way through a track is self-evidently running, so the bar says everything the dashes would and one thing more |
| Icons with labels | The button's slab fills from its leading edge, with a brighter line at the head of the fill | Room is what labelled mode has and compact mode has not. It reads across a whole row, survives a button too narrow for its text, and leaves the icon, the name and the dashes where they were |

A *track* under the fill, not a fill alone: a bar 12% along with nothing behind it is a short dash,
which is exactly what the running indicator looks like. The track is what makes the same mark read as
"12% of the way" rather than "one window". On a side bar the long axis runs downward, so the fill
grows from the top — otherwise a track plays upwards.

The reports reach the cells the way the activity overlay does — pushed through `ScreenCoordinator`
straight onto the views — rather than through `DockModel.rebuild`. Reassembling the whole strip once
a second to move one bar would be absurd.

Indeterminate progress is deliberately not drawn. Every source here has an end: a track has a
duration, a file operation has a size, a command prints a number. A bar that could not say how far
along it was would be an animation rather than information.

### 5.24 Custom icons and custom names

Two small overrides, both stored where the thing they override already lives.

**Icons come from a folder, not a picker.** `Icons/` in the support directory, each file named after
the cell it replaces — `com.apple.Safari.png`, `trash.png`, `apps-menu.png` — which is uBar's
convention and needs no interface at all: dropping a file in a folder is the whole gesture. The
folder is watched with the same `O_EVTONLY` `DispatchSource` `TrashWatcher` uses, so a file appearing,
changing or being deleted reaches the bar without a restart, and a `README.txt` is seeded into the
folder so opening it answers "what do I call the file".

Matching is case-insensitive, because a default macOS volume is: a `com.apple.safari.png` that
silently did nothing would be a puzzle with no clue in it. A key with several files takes the earliest
listed extension, so the answer does not depend on what order the file system happened to enumerate.
A file `NSImage` cannot read yields `nil` and the real icon is drawn — which is what makes a stray
text file in the folder harmless rather than a blank cell.

`IconService` renders an override exactly like a real icon: same cache, same downscale-never-upscale
rule, same mtime in the cache key so replacing a file takes effect. Setting the override map clears
the cache, because the cache is keyed by *source* file and a cell that has just gained or lost an
override would otherwise keep serving whichever icon it was built with.

**Only cells with a name to be addressed by.** An app has a bundle identifier; the Trash and the
launcher get reserved words. A folder or a file has only a path, which does not fit in a filename —
and needs no equivalent, because Finder's own Get Info ▸ paste-an-icon already overrides those and
`NSWorkspace.icon(forFile:)` reads the result.

**Names are stored beside the item, in `layout.json`.** `PersistedItem.customName` is deliberately a
second field rather than an overwrite of `name`: `name` is what the thing was called when it was
pinned, and keeping the two apart is what lets an app renamed on disk follow its new name unless
somebody has said otherwise.

The name is fed in at one place — `DockModel.rebuild` — but reaches readers two ways. `DockItem`
carries it for its own `displayName` and hover title, and for an app it is also written into
`AppRef.name`, because the ref is what a window button, the Quit menu item and the launcher all read.
Both come from the same field in the same assignment, so they cannot drift.

A window button is not renameable: the name belongs to the app and that cell is showing a window
title, so the menu item would change something the user is not looking at. Renaming an app that is
not pinned pins it first, in the place it already occupies — a name is a deliberate statement that
you want the thing to stay, the same reading `move` gives to dragging a running app into the pinned
run, and the alternative is a rename that evaporates when the app quits.

### 5.25 Menu-bar apps with windows

An app with `LSUIElement` set has no Dock tile, so a window it opens has no representation
anywhere — not in the Dock, not in a window list, nowhere. Eskele's own settings window is the
reference case: it is plainly on screen, and once something covers it there is no route back but to
find it with the mouse. (This is a different problem from the one the Dock's *window menu* has.
That menu mirrors the app's Windows menu, so a window with `isExcludedFromWindowsMenu` set falls out
of it — Finder's settings window is the usual example. Eskele never adopted that filter: it
enumerates `AXWindows` directly, and `AppWindow.isListable` admits such a window already. Only the
no-tile-at-all case needed building.)

These apps cannot simply join `RunningAppsService`. A machine runs dozens of agents — login items,
helpers, the Dock itself — and almost none ever show a window; a permanent cell for each would be
worse than no feature. So the rule is *an accessory app that has a window right now*, which makes
the cell transient: it arrives with the window and leaves with it.

**The window server answers the question, not Accessibility.** Asking AX "do you have a window?"
would mean a synchronous round trip into every agent on every sweep — the cost §5.16 exists to
remove. `CGWindowList` answers it for every process at once and needs no permission, so it is the
pre-filter and AX is asked only about the few agents that turned out to have something. Same shape
as the off-Space pre-filter in §5.13.

**Measured on macOS 26.6.** An accessory app's ordinary windows are reported at **layer 0**, exactly
like a regular app's — the activation policy changes the Dock's behaviour, not the window server's.
What an agent puts above layer 0 is precisely what must not earn a cell: status items at 25, the
system Dock at 20, Eskele's bar at 21, its tooltip and edge trigger at 22, its launcher at
`popUpMenu`. So the layer separates "a window" from "menu-bar chrome" with nothing left over, and
for Eskele itself it admits the settings and onboarding windows and nothing else. On-screen-only
rejects the cached template ghosts of §5.13 for free; a size floor rejects the small layer-0 windows
agents keep for event capture and drag feedback.

**Minimised windows are answered from the other side.** On-screen-only rejects a minimised window
too, and has to: off screen is where the ghosts are, and nothing in a window server entry tells the
two apart. Left there, minimising a window took its cell away, and the route back with it. So an app
that *already has* a cell and has lost its on-screen window is asked, live, whether it has a
minimised one (`AccessoryAppsService.keeping`, `WindowService.hasMinimisedWindow`) — AppKit for our
own windows, AX for anyone else's, and only for the handful with a cell. A window minimised before
any scan saw it still earns none. **Measured on macOS 27.0:** a minimising window leaves the screen
3–7ms before `isMiniaturized` turns true, with the app's main thread busy with the animation until
then. So for our own windows the question cannot be asked inside that gap, and for anyone else's the
AX read is answered by that same thread once it is free.

**Three things had to be guarded.**

1. *The attention highlight.* Measured: an `NSPanel` at `.floating` level reports its AX subrole as
   `AXDialog`, which is indistinguishable here from a real modal. Floating panels are what menu-bar
   agents are made of, so admitting them to the sweep unguarded would light up half the bar the
   moment the feature was switched on — §5.18 reads "a dialog, while the app is not frontmost" as a
   summons. Accessory apps therefore do not raise it. Regular apps keep the behaviour they have;
   the same false positive exists there in principle, but it is pre-existing and rarer.

2. *Eskele itself.* `RunningAppsService` excludes its own bundle so the bar can never show a cell
   for the bar. That exclusion is on the `.regular` branch only, so we fall through to the accessory
   branch like any other agent — which is the point: our bar is layer 21 and our settings window is
   layer 0, so we appear exactly when the user has settings open and vanish when they close it.

3. *Accessibility will not describe our own process.* **Measured on macOS 26.6:**
   `AXUIElementCopyAttributeValue` aimed at our own pid returns `kAXErrorNotImplemented` (-25208) —
   immediately, not as a timeout — and `AXObserverAddNotification` on it is refused the same way.
   macOS does not let a process inspect itself this way. Left alone, the one app whose settings
   window prompted the feature would be the one app the feature could not describe: a cell reporting
   no windows, with nothing for a click to raise. So our own pid takes an AppKit path instead
   (`WindowService.ownWindowRefs()` and the `ownPID` branches beside it), which costs nothing — we
   hold our own windows already — and works without the Accessibility permission. The cut is the
   same one the scan makes from outside: `.normal`-level windows only.

   The click needed its own answer. `ActivationPolicy` returns `.reopen` for any app that is running
   but not frontmost, and reopening an already-running agent does nothing visible, so the cell would
   have been inert. `applicationShouldHandleReopen` raises our front window instead — in the app
   delegate rather than the model, so every sender gets the same behaviour.

Off by default (`Settings.showAccessoryApps`), and gated behind `showRunningUnpinned`: the cell is
by definition an unpinned running app, so it has nowhere to be drawn while that run is off, and
scanning for it would be work for a cell that could not appear. `--diagnose-windows` reports which
menu-bar apps the scan found and what AX then said about each, whether or not the setting is on.
(Our own row is the one it cannot show: the diagnostic runs as a second, short-lived copy of Eskele,
and the AppKit path belongs to the copy that owns the windows.)

### 5.26 Recording hot keys

Four things register global hot keys, and they are configured three ways, because they are three
different shapes of thing:

| Role | Configured by | Why that way |
|---|---|---|
| Reveal (`revealHotKey`) | A recorder | One combination with nothing to vet it against: any key the rules allow. |
| Slots (`slotChord`) | A picker of four chords | The keys *are* the number row; only the modifiers are a choice. And the chord doubles as the overlay's (§5.19), so it has constraints a recorder could not explain. |
| Apps Menu (`appsMenuHotKey`) | A picker, plus a recorded `custom` | The three vetted keys stay the answer (§5.15); the recorder is the way out when one is taken. |
| Focus (`focusHotKey`) | A recorder | The reveal key's shape: one combination. On by default — §5.27. |

**Registration tells you almost nothing.** The TODO that asked for this assumed a combination
another app owns "fails to register". Measured on macOS 26, it does not: `RegisterEventHotKey`
returned `noErr` for ⌃Esc while a running Eskele held it, for ⌘Space and ⌘Tab, and for two separate
processes registering ⌃⌥⌘T at once. The one failure it reports is the *same process* registering a
combination twice (`eventHotKeyExistsErr`, -9878). There is no public way to list another app's
hot keys, so that collision cannot be detected, and the preferences say so rather than implying a
check that does not exist. `GlobalHotKey.unavailable` still reports a failed registration by role,
for whatever is left.

**What can be checked is checked before registering** (`HotKeyReview`), in this order:

1. *The rule* (`KeyCombination.refusal`). A global hot key is taken from every app, text fields
   included, so the rule is about what would be lost: without ⌃ or ⌘ the key types something (⇧ is
   capitals, ⌥ is é and ™ — how accents are typed on half the world's keyboards); ⌘ or ⌘⇧ alone is
   the front app's menu shortcut; ⌃ and a lone letter is the Cocoa text system's (⌃A, ⌃E, ⌃K).
   Function keys are exempt. The vetted Apps Menu choices are not held to it — ⌥Space is offered
   knowing what it costs — and a hand-edited `settings.json` is: a recorded key the rule would
   refuse decodes as the default, since registered as written a bare letter would stop typing
   everywhere.
2. *Our own keys against each other*, reported on both sides, since which one registers second —
   and so fails — is not the user's business.
3. *macOS's own shortcuts* (`SystemShortcuts`). `com.apple.symbolichotkeys` is no use for this: it
   records only what the user changed — 28 entries on the Mac measured, with neither ⌘Space nor any
   screenshot key among them. `CopySymbolicHotKeys` returns the table macOS applies, defaults and
   changes merged (234 entries). It was documented Carbon API and is still exported from HIToolbox,
   but no longer declared in the SDK headers, so it is found with `dlsym`; if it goes, the set is
   empty and only this warning goes quiet. Its masks carry the function-key bit on arrow and F keys,
   which a registered hot key never does, so it is masked off before comparing.

**The recorder** (`ShortcutRecorder`, an `NSButton` in a representable) listens with a local event
monitor rather than as first responder, because a monitor sees a key before anything can claim it
as a menu or button shortcut. Eskele's own hot keys are registered with the window server, which
takes them before any monitor, so they are suspended for as long as it listens — otherwise pressing
the assigned key to record it again would fire it. A refused key is answered under the button and
listening continues. It is AppKit because it has to know its own bounds: a click on it must be left
to its action, which ends the recording, where ending it in the monitor would have the action start
it again. Driven through posted `NSEvent`s: refusal, acceptance, Escape and a click elsewhere each do
what they should. The key's *name* is looked up in the current ASCII-capable layout when drawn,
since a key code is a position: the key a US keyboard calls D is E on Dvorak.

**Every slot chord includes ⌃.** The chord is also the overlay's (`BarOverlay.chords(for:)`), held
while looking at the bar with the pointer on it, and a chord you look with must not be a click
gesture. ⌃-click is always the context menu. ⌥⌘ was the obvious fifth choice and is Show Only This.

### 5.27 Keyboard and VoiceOver

Eskele hides the system Dock, which VoiceOver reads and ⌃F3 reaches, and puts in its place a bar that
until this section had neither: `ItemView` set no role, label or value, and nothing on the bar
answered a key. That is a worse regression here than in most apps, because the thing being replaced
was accessible.

**What VoiceOver is told** is written once, in `CellDescription`, a pure value built from a
`DockItem` and its progress — so the whole table is asserted rather than discovered with VoiceOver
running. Each cell is a *button* (a folder and the Apps Menu are *menu buttons*, since a press opens
a list), labelled with its name, with a value listing what the drawing says, most urgent first:
not responding or opening, needs attention, running, active, hidden, the window count, full screen,
the badge, progress, and last the page it is on. Choices worth recording:

- The **label is the app, not the page.** The tooltip leads with the window title because a sighted
  user already has the icon to say which app it is; a VoiceOver user has only the label. The title
  goes last in the value.
- **Not running says nothing**, as in the system Dock. Said on every pinned launcher, it buries the
  cells that are open.
- A zero window count is not said: `windowCount` is 0 for "unknown" too (§5.16).
- The **badge is read as "badge 3"**, not "3 new items". What a badge counts is the app's business,
  and a `badges.json` command's number may not be new anything. The Trash is the exception: its
  badge *is* a count of what is in it, so it says "4 items".
- A separator is not an element. It is a gap, and announcing it would be announcing nothing.

The strip (`BarContentView`) is a **list**, as the system Dock's is, with its orientation, and
overrides `accessibilityChildren` to return the cells **in bar order**: AppKit's default is subview
order, and a cell made for an app that launched mid-session is added last wherever it sits.

`AXPress` is the plain click and `AXShowMenu` the context menu, both performed on the next turn of the
run loop rather than inside the call — a stack or a context menu runs a tracking loop until it closes,
and the assistive app waiting for the reply would hang with it. The modifier-clicks become **custom
actions** (`ClickAction.alternatives`, derived from `resolve` so the two cannot drift): a screen reader
presses but holds no modifier, and two of them, Show Only This and the force relaunch, are on no menu.

**The keyboard** is a session a bar is handed by a global key, ⌃⌥⇥ by default
(`BarWindowController.takeKeyboard`):

1. The bar is revealed and held open — keyboard focus counts as an interaction (§5.10), since the
   pointer is then likely nowhere near it.
2. The strip puts focus on the cell of the app in front, read *before* activating: from the moment
   Eskele activates, the app in front is Eskele and no cell says otherwise.
3. Eskele activates and the panel becomes key. `BarPanel.canBecomeKey` is true only for the length of
   the session; the rest of the time it is false as §5.2 requires. Activating is the launcher's cost
   too (§5.15): an inactive app's window is sent no keys.
4. Keys arrive at the focused cell, which is the first responder so that AppKit and VoiceOver agree on
   where focus is, and climb the responder chain to the strip. `BarKeyCommand` maps them per edge.

The session ends on the one signal every exit shares: **the panel resigning key.** Return opening an
app, a click into another app, the launcher taking over — each takes key from the panel, so one
observer covers them all without a case for each. Only Escape, or the key again, hands the keyboard
back to the app it came from, and only if Eskele is still in front — once another app is, the user has
already said where the keyboard goes. A press that opens nothing (quit, hide, a stack's menu dismissed)
leaves the session running, which is what lets a run of apps be quit from the keyboard.

The launcher needs one hand-off in each direction, or the keyboard is left with an agent that owns no
windows. Opened from a bar that has the keyboard, it finds Eskele already in front, so it is passed the
bar's return app (`toggle(returningTo:)`). Pressing the focus key inside the launcher closes it
*without* handing the keyboard back (`relinquishKeyboard`) and passes its return app on to the bar.

Choices worth recording:

- **Every cell but a separator is a stop**, the Apps Menu included. `BarComposition.addressable`,
  which the TODO suggested traversal follow, leaves the launcher out so that ⌃⌥1 means the same thing
  with or without one; nothing is counted here, and a button the arrows skip is one a keyboard cannot
  reach.
- **Return is a click, modifiers and all**: `ClickAction.resolve` reads ⌘Return as ⌘-click. ⌃Return is
  the context menu, as ⌃-click is — `resolve` refuses ⌃, so it could mean nothing else. The arrow
  pointing into the screen opens the menu too, in the direction a cell's menu opens.
- **The ends stop rather than wrap.** On a bar the ends are places — the launcher, the Trash — and
  arriving at the launcher after the Trash reads as the bar having jumped.
- **Rebuilds keep focus by id**, and fall back to whatever now stands where the cell stood. Only a
  move is announced: the bar rebuilds every few seconds while anything changes, and VoiceOver
  repeating the current cell each time would make it unusable. For the same reason the value is never
  pushed with a change notification — a playing track would be read out every second.
- **The ring is drawn by the cell**, inside its slab, in `keyboardFocusIndicatorColor` at full
  strength. AppKit's ring is drawn outside the view, which on a bar one icon thick is off the
  edge of the strip. The colour comes at half alpha, meant for a ring around a control's border,
  and vanishes over an icon of the same hue.
- **`becomeFirstResponder` refuses** any cell the strip did not choose. `NSWindow.makeFirstResponder`
  never consults `acceptsFirstResponder` — only a click does — so without it the first responder, the
  ring and VoiceOver could describe three different cells. The refused call still returns `true`,
  because the window succeeds in making *itself* first responder; the test checks where focus went.
- **⌃⌥⇥, on by default.** macOS's own key for the job is ⌃F3, *Move focus to the Dock*, measured
  enabled on this Mac (`CopySymbolicHotKeys`, §5.26) — so it is refused by the recorder until the
  system's is turned off, which is how a user who wants the Dock's key gives it to the bar. Tab is
  what moves focus; ⌃⌥ is the bar's own chord. On by default because it is the bar's only keyboard
  route, the reasoning the Apps Menu's ⌃Esc already uses (one combination macOS does not use).

**Verified:** the description table, the key table on every edge, navigation and type-select, and
the strip's focus through moves, presses and rebuilds, as unit tests; the responder chain in a real
`BarPanel` — the focused cell is first responder, a key sent to it moves focus, no other cell can take
it; and the rebuilt app launching and saving ⌃⌥⇥ as the default. **Not verified:** VoiceOver's
actual speech, and the hot key pressed — this session could neither run VoiceOver nor post keys,
having no Accessibility grant of its own, and registration succeeding proves little when
`RegisterEventHotKey` accepts nearly anything (§5.26). Nor what ⌃F3 does while Eskele has the Dock
hidden.

### 5.28 Updates

Sparkle 2, from SwiftPM, behind `UpdateService`. The feed is
`https://github.com/hossainalhaidari/eskele/releases/latest/download/appcast.xml`: GitHub redirects
`releases/latest/download/<name>` to that asset on the newest non-draft, non-prerelease release, so
the appcast travels with the release and publishing the release is the whole of publishing the
update — no site to deploy, no commit to push back. It needs the repository public; a private one's
assets need a login Sparkle does not have.

- **The bundle, by hand.** There is no Xcode project to embed frameworks, so `build-app.sh` copies
  `Sparkle.framework` from beside the binary into `Contents/Frameworks` and adds
  `@executable_path/../Frameworks` to the executable's rpaths. It strips the XPC services, which only
  a sandboxed app uses (§9), and the headers and modules. Sparkle's `LICENSE`, which carries the
  bsdiff, sais-lite and ed25519 licences after its own, goes into `Contents/Resources/Licenses`
  beside Eskele's: MIT and bsdiff's BSD terms both want their notices in every binary copy.
  `sign-app.sh` then signs inside out —
  `Autoupdate`, `Updater.app`, the framework, the app — because `--deep` would give nested code the
  app's entitlements, and notarisation wants Hardened Runtime and a timestamp on every piece.
- **Only releases update.** Sparkle compares `CFBundleVersion`. A release gets the version from its
  tag and a build number that is the commit count on `main`, which only goes up; the workflow
  refuses a release that is not a descendant of the last one, since that could count lower. Any
  other build keeps the placeholder `1` — which every release beats — so `build-app.sh` removes its
  `SUFeedURL`. Without that, `make run` would offer to replace itself with the published build and,
  on Install Automatically, would do it on the next quit. `UpdateService` starts no updater without
  a feed and a key: started, Sparkle alerts the user that the app is misconfigured.
- **One picker, two switches.** Sparkle keeps "check on a schedule" and "download what it finds" in
  the app's defaults, and its update alert's "Automatically download and install updates" box sets
  the second itself. `UpdatePolicy` maps the three meaningful combinations to Install
  Automatically, Ask Before Installing and Only When I Check, reads them back through KVO so the
  alert's change shows up in the pane, and writes both every time so an old download switch cannot
  resurface. Not in `Settings`, like the login item: a copy in `settings.json` would be a second
  record the alert never updates.
- **Nothing goes out unasked.** `SUEnableAutomaticChecks` is `false` in `Info.plist`, so a fresh
  copy starts on Only When I Check and Sparkle never shows its second-launch prompt.
  `SUEnableSystemProfiling` is `false`, so the anonymous system profile is never offered, and
  `allowedSystemProfileKeys(for:)` returns an empty list, so a `SUSendProfileInfo` switched on
  through `defaults` still attaches nothing. `userAgentString` is plain `Sparkle` in place of
  Sparkle's `Eskele/<version> Sparkle/<version>`, and `httpHeaders` sets `Accept-Language: *` over
  the user's languages, which URLSession would otherwise add. Neither is needed to answer: Sparkle
  compares the local `CFBundleVersion` with each item's `sparkle:version` on the Mac. Sparkle puts
  both on the appcast, release-notes and archive requests, and URLSession keeps them across GitHub's
  redirect to the asset host; an empty value would not remove the header, only send it blank. What
  is left is the IP address.
- **Gentle reminders.** An agent is never frontmost on its own, so a scheduled check's alert would
  open behind the user's work. Sparkle shows it only when it proposes immediate focus — just after
  launch, or after idle — and otherwise hands it to the delegate, which puts the version in the
  status menu (*Update to Eskele 1.2.0…*) and the General pane. Choosing it runs a check, which is
  how Sparkle brings a held update forward.
- **Keys.** `make update-key` makes the EdDSA pair under the Keychain account `eskele` and writes the
  public half into `Info.plist`. Neither `SUVerifyUpdateBeforeExtraction` nor `SURequireSignedFeed`
  is set: both close the recovery path in which a lost EdDSA key is replaced by a release signed
  with the same Developer ID.

**Verified:** a throwaway app embedded, stripped and signed by these same scripts — Apple
Development certificate, Hardened Runtime, timestamp — updated itself from 1.0.0 to 1.0.1 against a
local feed written by `generate_appcast` with markdown notes, relaunched as the new version with its
signature intact, and refused the same update with a forged EdDSA signature. `package.sh` run end to
end with the Developer ID: every piece carries the runtime flag and a timestamp, the packaged app
loads Sparkle under library validation, and Apple accepted the DMG with an empty issue list across
all 17 signed files; `spctl` accepts both the DMG and the app inside it as Notarized Developer ID.
The workflow then published v0.1.0 and v0.1.1 unattended: tag on `main` to a notarised, stapled DMG
and a signed appcast, whose signature verifies against the key in `Info.plist` and whose download
Gatekeeper accepts as Notarized Developer ID. With both out, the owner installed 0.1.0 from its DMG
and updated it to 0.1.1 from inside the app — the last step nothing here could exercise, since a
second Eskele cannot run beside the one in use.

### 5.29 Polling while nobody is looking

Much of what the bar shows has no notification to wait for, so it is polled: the Dock's badges and
the Trash every 2s, off-Space windows every 3s, progress sources every 4s, badge commands and the
AX window sweep every 5s — and, when switched on, the Dock watchdog (5s), the menu-bar app scan
(2s) and the overlay chord (80ms). Each carries a tolerance, so the system coalesces them, but
nothing used to stop any of them while the displays were asleep.

Every repeating timer that can run indefinitely is now a `Poll`, and `PollGate` stops all of them
while the displays sleep (`screensDidSleep`) or another user has the console
(`sessionDidResignActive`), then runs each once on the way back so the bar is current by the time
anyone can see it. That covers the three that are not background work, too — the attention pulse,
auto-hide's pointer check and the progress drawing clock — because each of them can run all night:
an app can ask for attention and never be answered. System sleep needs nothing of its own, since no
timer fires while the machine sleeps; what does run is the time around it with the display off, and
Power Nap's dark wakes, which leave the display asleep.

- **Low Power Mode** doubles the background intervals rather than stopping anything: the bar is
  still on screen and still has to be right. The chord, the pulse and the pointer check keep their
  pace — someone is watching those as they run, and slower would look broken.
- **The Trash watcher** lives in TrashKit, which knows nothing of `Poll`, so the app sets its
  `isPaused` from the gate. Unpausing reads the Trash at once. It is not stretched: its poll is one
  `stat`.
- **Left as plain timers:** the clock (once a minute, aligned to the minute), the activity sampler
  (only while its chord is held) and the launch poll (only while an app is starting). None of them
  can run on with nobody there.

**Measured on macOS 27.0**, M4, with the activity overlay on (so the 80ms chord poll runs), as
Eskele's wakeups — `proc_pid_rusage`, idle plus interrupt — and CPU time over 20s:

| Build | Display on | Display asleep |
|---|---|---|
| Before the gate | 388 wakeups, 150ms | 344 wakeups, 175ms |
| With the gate | 338 wakeups, 176ms | **9 wakeups, 1ms** |

The first row is the answer to "does App Nap do this already?" — Eskele does not opt out of it, and
a sleeping display leaves none of its windows visible, but the old build carried on at the same rate
regardless. So the drop is the gate's. Not measured: battery life, and Low Power Mode's stretch.

## 6. Risks & spikes (do these before writing the app)

| ID | Risk | Result |
|---|---|---|
| **S1** | `autohide-delay` ignored on macOS 26? | **Resolved — works.** `autohide` + `autohide-delay: 1000` + Dock restart hides it for good. Level 21 occlusion is in place as belt-and-braces. |
| **S2** | Restore-on-crash correctness | **Resolved — verified.** `SIGTERM` restores; `SIGKILL` leaves the backup dirty and the next launch restores it, including *removing* keys that were absent before. |
| **S3** | Menu bar thickness on external / non-notched displays | **Resolved — removed.** The bar no longer matches the menu bar: Small and Big are fixed at 32pt and 48pt (§5.1), so there is no per-display thickness to measure. What is still read per display is `menuBarInset` (§5.2), so a full-height side bar stops below the menu bar; it is the plain `frame`/`visibleFrame` gap, but has likewise only been seen on the notched display. |
| **S4** | Non-activating panel + click-to-activate focus ordering | **Open.** Needs hands-on clicking; the panel is `.nonactivatingPanel` and `canBecomeKey` is false, which is the required setup — except while the bar has been handed the keyboard (§5.27), which no click can bring about. |

S1, S2 and S3 are answered, S3 by dropping what it was testing. S4 needs a human at the keyboard.

---

## 7. Milestones

| M | Deliverable | Status |
|---|---|---|
| **M0** | Spikes | S1–S3 resolved above; S4 needs hands |
| **M1** | Walking skeleton | **Done.** Agent app, status item, borderless panel, 32pt thickness verified against the live menu bar, click-to-launch |
| **M2** | Live items | **Done.** RunningAppsService, running/frontmost/hidden indicators, context menus, quit/hide/activate |
| **M3** | Geometry | **Done.** Left/right/bottom verified pixel-exact, per-display panels keyed by display ID, screen-change handling |
| **M4** | Icon quality | **Done.** Retina-correct representation picking, mtime-keyed cache, system Trash icon pair |
| **M5** | Dock suppression | **Done.** DockPrefsKit, watchdog, full restore matrix, plus reserved-space mode (§5.6) |
| **M6** | Trash + drag & drop | **Done.** TrashKit, pin/unpin/reorder, drag-off-to-remove, drop-to-open, drop-to-trash, persistence |
| **M7** | Preferences + polish | **Done.** SwiftUI settings window (4 tabs), `SMAppService` login item, first-run onboarding, non-prompting permission status rows |
| **M8** | Distribution | **Done.** `Scripts/package.sh` signs with Hardened Runtime, builds and verifies a DMG, notarises and staples — run with the Developer ID, Apple accepted it with no issues; `.github/workflows/release.yml` runs it from a tag or by hand on `main` and published v0.1.0 that way. Sparkle auto-update — see §5.28. Each release also moves the cask in `hossainalhaidari/homebrew-tap`, so `brew install --cask hossainalhaidari/tap/eskele` installs it |
| **M9** | Auto-hide & reveal | **Done.** Edge trigger window, slide animation, interaction guard, ⌃⌥D global hot key (§5.10) |
| **M10** | Stacks & window management | **Done.** Lazy stack menus, AX window lists with graceful degradation (§5.11). The AX window *nudge* is dropped in favour of reserved-space mode |
| **M11** | Full-screen behaviour | **Done, unverified.** Show / reveal-on-hover / hide per §5.13. The AX detection path could not be exercised here — granting Accessibility needs the user |
| **M12** | Item styles | **Done.** Compact and labelled-button modes with a tested flex solver (§5.14) |
| **M13** | Bar scale | **Done.** Small / Big, with every derived measurement routed through `BarMetrics` (§5.1) |
| **M14** | Apps Menu | **Done.** Launcher panel with search, categorised All Apps, Favourites and Recents, on any edge (§5.15) |
| **M15** | Multiple windows | **Done.** AX-backed counts, one dash per window capped at four, click-to-cycle, live window titles, and one button per window in full-width mode (§5.16) |

M1–M10 are implemented and building clean with no warnings, v0.1.1 is published, and a copy has
updated itself to it. What remains is the one open spike — a human clicking things for S4.

---

## 8. Repository layout

```
eskele/
├── ARCHITECTURE.md
├── CHANGELOG.md                what each release changed, and the notes it ships with
├── README.md
├── Eskele.xcodeproj
├── Sources/Eskele/             app target
│   ├── App/                    main, AppDelegate, StatusItemController, SettingsStore
│   ├── Windowing/              BarPanel, BarWindowController, EdgeTriggerWindow,
│   │                           ScreenCoordinator, AuxiliaryWindows
│   ├── Model/                  Settings, DockItem, DockModel, PersistedItem, UpdatePolicy
│   ├── Services/               RunningApps, Icon, SystemDock, Persistence, ScreenMetrics,
│   │                           Window(AX), Permissions, LoginItem, GlobalHotKey, Update, Poll
│   ├── UI/                     BarContentView, ItemView, StackMenuController,
│   │                           PreferencesView, OnboardingView, DragTypes
│   └── Resources/              Info.plist, entitlements
├── Packages/
│   ├── DockPrefsKit/           read/write/backup/restore com.apple.dock  (unit-tested)
│   └── TrashKit/               trash watching + operations               (unit-tested)
├── Tests/EskeleTests/          settings + layout decoding
├── Scripts/                    build-app.sh (bundle), sign-app.sh (inside-out signing),
│                               package.sh (signed DMG), update-key.sh (Sparkle key pair)
├── .github/workflows/          ci.yml (build + test), release.yml (tag → notarised release → Homebrew cask)
└── Makefile                    build / test / run / package / update-key / restore-dock
```

---

## 9. Distribution constraints

- **Cannot be sandboxed.** Writing `com.apple.dock` preferences and terminating the Dock process are
  both outside any sandbox entitlement. → **Mac App Store is out** unless Dock suppression is dropped.
- Ship as a Developer ID–signed, notarized, stapled `.dmg` with Hardened Runtime and the
  `com.apple.security.automation.apple-events` entitlement.
- **Updates through Sparkle**, from an appcast attached to each GitHub release (§5.28). Its XPC
  services exist for sandboxed apps and are stripped from the bundle. The feed is only reachable
  while the repository is public.
- README must document manual Dock recovery for the worst case:
  ```bash
  defaults delete com.apple.dock autohide-delay; defaults write com.apple.dock autohide -bool false; killall Dock
  ```

---

## 10. Open questions for the owner

1. **Running-but-unpinned apps** — currently shown, like the Dock. "Bookmarks only" is the more
   minimal product and a one-line default change.
2. **Reserved-space mode as the default** — now that it works, is floating-above-windows still the
   right out-of-the-box behaviour, or should "Replace My Dock" be the recommended path?
3. **Icon fit** — icons currently inset ~2pt with a 5pt indicator lane, giving ~24pt icons in a 32pt
   bar. Full-bleed would read larger; the indicator would need somewhere else to live.
4. **Full-screen default** — currently Always Show, which is also the no-permission fallback. Is
   Reveal on Hover the better default for people who do grant Accessibility?
5. ~~**Configurable hot key**~~ — answered in §5.26: the reveal key is recorded, the slot keys pick
   their chord from a vetted list, and the Apps Menu's list gained a recorded fifth choice.
6. **Favourites** — currently means "the apps pinned to the bar", so there is nothing extra to
   curate. A separate favourites list would let the menu hold apps that are not cluttering the bar,
   at the cost of somewhere to manage it.
7. **Labels on vertical bars** — currently refused, because fitting them means a ~168pt-wide bar
   rather than a 32pt one. Worth offering as an explicit "wide vertical bar" mode, or is the
   slim side bar sacrosanct?
