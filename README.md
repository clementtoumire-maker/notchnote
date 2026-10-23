# NotchNote

A personal, paywall-free notch notepad and checklist for macOS 15+, modelled on GlideNote. Menu-bar app (no Dock icon), Swift + SwiftUI + AppKit. Everything is unlocked: no Pro tier, no task limit, no subscription.

## Build and run

You need a Mac with the current stable **Xcode** (App Store or developer.apple.com, free) and nothing else. No paid Developer Program account: the project signs with **Sign to Run Locally** (ad-hoc, `CODE_SIGN_IDENTITY = "-"`) and uses no entitlements.

### Command line

```bash
cd NotchNote
xcodebuild -project NotchNote.xcodeproj -scheme NotchNote -configuration Release \
  -derivedDataPath build CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="" build
open build/Build/Products/Release/NotchNote.app
```

(`./scripts/build.sh` runs exactly that.)

`make install` uses Xcode if present and falls back to the Command Line Tools only (`xcode-select --install`). New to this? Follow the step-by-step guide in [INSTALL.md](INSTALL.md).

### One command: build and install into /Applications

```bash
make install        # same as ./scripts/install.sh
```

It builds Release, quits a running copy, copies to `/Applications/NotchNote.app`, re-signs ad-hoc, clears quarantine and launches it.

Or double-click **Install NotchNote.command** in Finder (if macOS blocks it: right-click, Open).

**Running in the background.** NotchNote has no Dock icon and no window. After install it starts, sits in the notch (or as a pill on a notchless display) and has a menu bar icon. The first launch switches on **Launch at login** once, so it starts by itself after every restart; turn it off in Settings if you do not want that. Only one copy can run. Quit it from the menu bar icon; remove it with `make uninstall` (your notes stay in `~/Library/Application Support/NotchNote`). If macOS asks, allow it under System Settings, General, Login Items. Whether the login item actually registers for an ad-hoc signed app has not been tested here.

### Xcode GUI

1. Open `NotchNote.xcodeproj`.
2. Select the **NotchNote** target → **Signing & Capabilities**. Set **Team: None**; signing certificate **Sign to Run Locally**. (A free personal team also works: pick it instead, Xcode creates a development certificate.)
3. Scheme **NotchNote**, destination **My Mac**, press **⌘R**.

### No Xcode project? (fallback)

`make fallback` (`scripts/build-fallback.sh`) compiles with `swiftc` and the Command Line Tools only and assembles `build/fallback/NotchNote.app`. Everything works except that the Shortcuts "Add task" action is only registered by the Xcode build.

### First launch

* NotchNote is unsigned by an identified developer. If macOS blocks the first launch: **System Settings → Privacy & Security → Open Anyway**, or run `xattr -cr /Applications/NotchNote.app`.
* Allow notifications when asked (needed for reminders).
* Launch at login: Settings → General. It works best from `/Applications`.

### Regenerating the Xcode project

`python3 tools/gen_xcodeproj.py` rebuilds `NotchNote.xcodeproj` from the files under `NotchNote/` (or just add files in Xcode).

### Self-test of the Markdown logic

`make test` compiles `MarkdownCodec.swift` plus `tests/main.swift` with `swiftc` and runs 30 checks (shortcut conversion, no duplicate markers, Return/Backspace rules, round trip).

## The six stages

All stages are in this project. Each can be exercised as below.

**Stage 1 – Notch panel.** Hover the notch (or click it) and the panel springs open (damping 0.70, response 0.42, anchored at the top centre) with a haptic tick on hover. It collapses when the pointer leaves, on Esc, or on a click elsewhere; the pin keeps it open. Displays without a notch get a floating pill with a translucent glass look. One panel per display; one open at a time; Esc and typing go to the panel you opened. Display geometry is computed from the screen frame and the notch metrics, and rebuilt (debounced 0.6 s) only when the set of displays really changes, so entering/leaving clamshell mode does not move the panel. Resize by dragging the bottom-right handle; notch size, panel size and text colour are in Settings.

**Stage 2 – Editor.** `# ` heading, `- ` bullet, `- [ ] ` checkbox (also `[] `), Return continues a list, Return on an empty item ends it, Backspace removes a whole marker, Tab/Shift-Tab indent, click a checkbox to tick it. ⌘⇧L checklist, ⌘⇧B bullet, ⌘⇧H heading, ⌘Return tick, ⌘Z / ⇧⌘Z undo/redo. Conversions never run while an input method is composing and never during undo, which prevents duplicate markers with Korean/Japanese input.

**Stage 3 – Tasks, window, favorites, cards.** Many tasks (one note each). The task window (panel button or status-menu item) has a collapsible sidebar with search, drag-to-reorder, summaries (title, `done/total`, first line), a bottom bar with favorite and new-task buttons, and a context menu. ⌘⇧S toggles favorite everywhere; favorites are reorderable by dragging. Drop text on the notch to save a card (copy and delete buttons). Title editing ends when the panel collapses.

**Stage 4 – Reminders.** A task with unchecked items triggers a notification at the interval you pick (Settings). Click it to open that task. The timer is cancelled while the Mac sleeps, the screens sleep, the session is inactive, the screen is locked or the screen saver runs, and restarts fresh afterwards.

**Stage 5 – Sync folder, Spotlight, Shortcuts.** Choose a sync folder (e.g. in iCloud Drive). Move single tasks between **local** and **sync folder** from the context menu. Changes made by another Mac are merged when the folder changes (newest `updatedAt` wins). Tasks are indexed with CoreSpotlight (click a result to open the task). Shortcuts has an **Add task** action. See `docs/CLOUDKIT.md` for the later CloudKit switch.

**Stage 6 – Settings, onboarding, polish.** Launch at login, reminder interval, sync folder, text colour, notch and panel size, optional anonymous usage toggle (default off; the app has no networking code at all, so nothing is sent), getting-started guide on first run (also in the status menu). Autosave: debounced 0.5 s, flushed on collapse/resign/quit, always written atomically; deleted tasks go to the Trash. No polling timers; the only recurring work is the reminder timer (10 % tolerance).

Data lives in `~/Library/Application Support/NotchNote/` (tasks, cards, order) and, for synced tasks, in `<sync folder>/NotchNote/`.

## Not verified (read this first)

This code was written in a cloud sandbox that has no Swift compiler, no Xcode and no macOS. **It has never been compiled.** Expect a handful of compile errors on the first build (most likely small API-signature or Swift-concurrency mistakes); the `STATUS.md` checklist says how to report them.

* Not verified: that `xcodebuild` succeeds; that the hand-generated `NotchNote.xcodeproj` opens cleanly (if Xcode complains, run `make project` or use `make fallback`).
* Not verified: hover spring feel, the haptic tick, exact notch alignment, the glass look, clamshell behaviour, multi-display Esc/typing routing, drag-text-to-notch, checkbox click hit area, Korean/Japanese IME (the safeguards are in place but untested), notification click-through, reminder pause/resume on lock/sleep, Spotlight results, the Shortcuts action, launch at login.
* Verified here: the static checks in `tools/verify_static.py` (balanced braces, every source in the project, plists valid, ad-hoc signing, no paid entitlements, no networking code, no paywall identifiers).

Run `make test` first: it compiles only the pure Markdown logic, so it tells you quickly whether your toolchain works with this code.
