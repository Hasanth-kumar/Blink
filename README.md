# Blink

A menu bar app for macOS that reminds you to rest your eyes, and waits for a good moment to do it.
Original name, icon, copy and design; built for personal use.

- macOS 13 or later, Swift 5.9+, SwiftUI with AppKit where SwiftUI can't reach
- No third-party dependencies
- About 6,200 lines across 36 Swift files

> **Status: animated reminders added, not yet built on a Mac.**
> The blink and posture reminders are now animated and have sound (section 8). The part that
> decides every frame and every sound cue (`NudgeChoreography.swift`, and the synthesiser in
> `NudgeSounds.swift`) was compiled and run with a Swift compiler on Linux, and its frames were
> rendered and checked. The SwiftUI and AppKit code around it needs a Mac to compile, so it has
> only been checked for syntax. If a build prints errors, they are saved to
> `build/last-build.log`; share that file (or the error lines) and they can be fixed quickly.

---

## 1. Build and run

### Easiest: double-click the installer

In the folder that contains `BlinkApp`, double-click **Install Blink.command**. It builds Blink,
copies it to your Applications folder, starts it and shows it in Finder. From then on Blink opens
like any other app: click its icon in Launchpad, Finder, Spotlight or the Dock. Opening it this
way shows the Settings window, so you can see it started; a start at login stays quiet.

The installer needs the Command Line Tools (step 1 below). If macOS refuses to open the file,
right-click it and choose **Open**, or use Option A.

### Option A: Command Line Tools only (no Xcode needed)

1. Check for the tools: open Terminal and run `swift --version`.
   If it says the command is not found, run `xcode-select --install` and follow the prompt.
2. In Terminal, go to this folder and run:

   ```bash
   bash build.sh run
   ```

   This compiles the app, assembles `build/Blink.app`, signs it for this Mac and launches it.
   An eye icon appears in the menu bar, and Settings opens on the very first launch.
3. To install it properly: `bash build.sh install` (copies to `/Applications` and launches).
   Then turn on **Settings → General → Open Blink at login**.

What this route does **not** give you: the Focus Filter and the Shortcuts-app actions. macOS only
discovers those from metadata that Xcode's build system generates. Everything else works.

### Option B: Xcode (full feature set)

1. Install Xcode from the App Store (Xcode 15 or later recommended).
2. Double-click `Blink.xcodeproj`.
3. Select the **Blink** scheme and **My Mac**, then press **⌘R**.
   Signing is already set to "Sign to Run Locally", so no Apple developer account is needed.
4. For daily use: **Product → Show Build Folder in Finder**, open `Products/Debug`, and drag
   `Blink.app` into `/Applications`. Launch it from there.

### If the included project will not open: create it by hand

1. Xcode → **File → New → Project → macOS → App**. Name: `Blink`, Interface: SwiftUI,
   Language: Swift. Save it somewhere new.
2. Delete the generated `BlinkApp.swift`, `ContentView.swift`, `Assets.xcassets` and
   `Blink.entitlements` (move to Trash).
3. Drag the contents of this repo's `Blink/` folder into the project navigator
   (tick **Copy items if needed** and **Create groups**; target **Blink**).
4. Select `Info.plist` and `Blink.entitlements` in the navigator and, in the File inspector,
   untick **Target Membership** for both (they are configuration, not resources).
5. Target → **Build Settings**:
   - *Info.plist File* → `Blink/Info.plist`
   - *Generate Info.plist File* → `No`
   - *Code Signing Entitlements* → `Blink/Blink.entitlements`
   - *Product Bundle Identifier* → `local.blink.app`
   - *macOS Deployment Target* → `13.0`
   - *Swift Language Version* → `Swift 5`
6. Target → **Signing & Capabilities**: remove **App Sandbox** if it is listed; set
   *Team* to None and *Signing Certificate* to **Sign to Run Locally**.
7. Press **⌘R**.

### Testing quickly

Waiting 20 minutes per test is no fun. In **Settings → Break Schedule** set *Work for* to
`1 min`, *Then rest for* to `5 sec`, and the heads-up to `10 sec before`. Changing the work
interval restarts the countdown immediately.

---

## 2. Plan

### Folder structure

```
Blink/
├─ BlinkMain.swift               entry point (plain AppKit, no storyboard)
├─ AppDelegate.swift             wires everything together; URL scheme; main menu
├─ Info.plist, Blink.entitlements
├─ Core/                         no UI in here
│  ├─ Models.swift               SchedulerState, BreakKind, HoldReason, effects, config
│  ├─ SchedulerCore.swift        the state machine: pure logic, no timers, no system calls
│  ├─ OfficeHours.swift          working days and hours, including overnight shifts
│  ├─ BreakScheduler.swift       gives the core a clock, system readings and persistence
│  ├─ AppSettings.swift          every preference, backed by UserDefaults
│  ├─ StatsStore.swift           break history as Codable JSON
│  └─ TimeFormat.swift
├─ System/
│  ├─ SystemActivityMonitor.swift  idle, typing, camera, mic, full screen, video, lock state
│  ├─ HotKeyCenter.swift           global shortcuts (Carbon hot keys)
│  ├─ LaunchAtLogin.swift          SMAppService
│  ├─ SoundPlayer.swift            the chime at the end of a break
│  └─ NudgeSounds.swift            builds and plays the reminder sounds
├─ UI/
│  ├─ StatusItemController.swift   menu bar icon, countdown and menu
│  ├─ HeadsUpView/Controller       floating pre-break card
│  ├─ BreakOverlayView/Controller  full-screen break on every display
│  ├─ NudgeChoreography.swift      every frame and sound cue of the reminders (no UI code)
│  ├─ NudgeController.swift        paints the reminders and puts them on screen
│  ├─ Panels.swift, Theme.swift
├─ Settings/                     sidebar window: General, Break Schedule, Smart Pause,
│                                Break Screen, Wellness, Shortcuts, Stats, About
├─ Intents/
│  ├─ FocusFilter.swift            SetFocusFilterIntent
│  └─ ShortcutsIntents.swift       Start / Skip / Pause / Resume for the Shortcuts app
└─ Resources/AppIcon.icns
```

### Key types

| Type | Role |
|---|---|
| `SchedulerCore` | The state machine. Takes "now" and a few probes, returns effects. Deterministic and testable. |
| `BreakScheduler` | Single source of truth (`ObservableObject`). Owns the timer, listens for sleep / lock / screen saver, persists state, publishes `state`. |
| `SchedulerState` | `working`, `preBreakWarning`, `holding`, `onBreak`, `paused`, `idle`, `outsideOfficeHours`. Every case carries wall-clock `Date`s. |
| `SchedulerProbes` | Closures for "seconds since input", "seconds since key press", "smart-pause reason", "display kept awake". Only called when a decision needs them. |
| `AppSettings` | One observable object for all preferences; produces a plain `ScheduleConfig` for the core. |
| `StatusItemController`, `HeadsUpController`, `BreakOverlayController`, `NudgeController` | Each watches the scheduler and shows or hides its own surface. None of them make scheduling decisions. |
| `NudgeScript` | One reminder from start to finish. Given a time it returns the shapes to draw; it also lists the sound cues on the same clock. Pure arithmetic, like `SchedulerCore`. |

### State machine

Deadlines are absolute dates, so a late timer tick can delay a transition but can never
miscount time. One extra state was added to your list: **holding**, meaning "a break is due but
now is a bad moment".

| From | Event | To |
|---|---|---|
| working | heads-up time reached, nothing blocking | preBreakWarning |
| working | heads-up time reached, but a call / video / recording / presentation / game / excluded app is active | stays working (no heads-up over a call) |
| working | deadline reached, nothing blocking, not typing | onBreak |
| working | deadline reached, something blocking or user is typing | holding |
| working | no input for N minutes (and no video or call keeping the user present) | idle |
| working | screen locked, display or Mac asleep, screen saver, user switched out | idle |
| working | clock leaves office hours | outsideOfficeHours |
| preBreakWarning | break time reached, clear | onBreak |
| preBreakWarning | break time reached, blocked or typing | holding |
| preBreakWarning | **Start now** | onBreak |
| preBreakWarning | **Snooze 1 / 5 min** (if snoozes remain) | working (short cycle, shorter heads-up) |
| preBreakWarning | **Skip** | working (new cycle, counted as skipped) |
| preBreakWarning | screen locked / asleep | idle |
| holding (typing) | no key press for N seconds | onBreak |
| holding (typing) | still typing after 60 s | onBreak |
| holding (call, video, …) | activity ends | preBreakWarning (10-second heads-up) |
| holding | user goes away | idle |
| onBreak | time is up | working (chime, counted as taken) |
| onBreak | **Skip** or Esc (not in strict mode) | working (counted as skipped) |
| idle | user returns after ≥ one break length | working, fresh countdown, "natural break" recorded |
| idle | user returns sooner | working, with the time that was left |
| outsideOfficeHours | office hours begin | working |
| paused | pause expires, or **Resume** | working |
| any except onBreak | **Pause** (15 min / 1 h / until tomorrow / indefinitely) | paused |
| any except onBreak | Focus Filter turns on "Pause break reminders" | paused (by Focus) |
| paused (by Focus) | that Focus turns off | working |
| any except onBreak | **Take a Break Now** | onBreak (returns to paused afterwards if it was paused by hand) |
| working / preBreakWarning / holding | Mac slept without warning (tick gap > 90 s) | working, fresh countdown |

Other rules: every Nth break is a long one when long breaks are on; the snooze count resets
after each break; changing the work interval restarts the countdown; a clock set backwards can
never stretch the wait beyond one full interval; an in-progress break or pause survives a relaunch.

---

## 3. Decisions made (and why)

- **`ObservableObject`, not `@Observable`.** `@Observable` needs macOS 14 and the target is 13.
- **No `@State` anywhere.** With the macOS 27 SDK, `@State` is a macro whose compiler plug-in
  ships only with Xcode, so a Command Line Tools build fails on it. The few bits of view state
  (sidebar selection, stats range, heads-up hover) live in small observable objects instead,
  which builds with or without Xcode.
- **Settings use `@Published` + `UserDefaults` in one `AppSettings` object rather than `@AppStorage`.**
  The scheduler is not a SwiftUI view, and this guarantees the engine and the UI always see the
  same live values. Storage is still plain `UserDefaults`.
- **Smart pause holds the break instead of freezing the timer.** After a 50-minute call you have
  been at the screen for 50 minutes, so the break arrives (with a short heads-up) when the call
  ends, not 15 minutes later.
- **Idle time does not count while a video or call keeps the display awake.** Watching a film
  with your hands off the keyboard is not a break for your eyes.
- **Strict mode means no skipping anywhere**: break screen, heads-up, menu, shortcut and URL.
  Snoozing still follows your snooze limit.
- **Menu bar shows minutes by default** ("12m", switching to seconds for the last minute). A
  seconds counter that never stops is distracting; a live countdown is one setting away.
- **The blurred break screen follows light / dark mode; colour, gradient and photo backgrounds
  always use white text** on a dark surface for contrast.
- **"Until tomorrow"** resumes at midnight, or at your next office-hours start if office hours are on.
- **Not sandboxed, no dependencies.** Shortcuts use Carbon hot keys (no Accessibility permission);
  no Sparkle since this is a personal build.
- **URL scheme and Shortcuts actions are included now** (they were phase 2) because they were
  small: `blink://break`, `blink://pause?minutes=30`, `blink://resume`, `blink://skip`, `blink://settings`.
- **Bundle identifier** is `local.blink.app`.

### Known limits

- **Screen recording** has no public "is recording" switch in macOS. Blink detects the system
  recorder (⌘⇧5) and OBS. Add any other recorder under *Smart Pause → Never interrupt these apps*.
- **Microphone check** is per device. A USB headset that is one device for both playback and
  microphone can look "in use" while only playing music. If breaks never arrive, turn off
  *Calls* under Smart Pause to confirm, then exclude differently.
- **Full-screen video** is detected as "frontmost app is full screen and something is keeping the
  display awake". An app such as Amphetamine keeping the display awake while you work full screen
  will look like video.
- **Games** are recognised by the category the game declares; add others to the app list.

---

## 4. Info.plist keys, entitlements and permissions

| Key | Value | Why |
|---|---|---|
| `LSUIElement` | `true` | Menu bar only: no Dock icon, no app menu. The Dock toggle switches the activation policy at runtime. |
| `CFBundleURLTypes` | scheme `blink` | Enables `blink://…` automation links. |
| `LSMinimumSystemVersion` | `13.0` | `SMAppService`, Focus Filters, Swift Charts and grouped forms all need macOS 13. |
| `CFBundleIconFile` | `AppIcon` | The icon in `Resources/AppIcon.icns`. |
| `NSSupportsAutomaticTermination`, `NSSupportsSuddenTermination` | `false` | macOS must not quietly terminate a windowless app that is counting down. |
| `NSPrincipalClass` | `NSApplication` | Standard for an AppKit app without a storyboard. |

**Entitlements:** only `com.apple.security.app-sandbox = false`. The app is not sandboxed because
it reads system-wide state (power assertions, other apps' window sizes, lock notifications).

**Privacy permissions: none are requested, and none are needed.**

| Feature | How it works | Permission |
|---|---|---|
| Camera in use | Reads CoreMediaIO's "device is running somewhere" flag. Never opens the camera. | None. No `NSCameraUsageDescription`. |
| Microphone in use | Reads CoreAudio's "device is running somewhere" flag. Never records. | None. No `NSMicrophoneUsageDescription`. |
| Idle and typing detection | `CGEventSource.secondsSinceLastEventType` (a counter the system keeps). Blink never sees which keys are pressed. | None. No Accessibility, no Input Monitoring. |
| Global shortcuts | Carbon `RegisterEventHotKey`. | None. |
| Full-screen detection | `NSApplication.currentSystemPresentationOptions`, plus window *sizes* from `CGWindowListCopyWindowInfo`. Never reads window titles or contents. | None. No Screen Recording permission. |
| Video playing | Power assertions via `IOPMCopyAssertionsByProcess`. | None. |
| Launch at login | `SMAppService.mainApp`. | macOS shows its own "login item added" notice. |
| Focus Filter | `SetFocusFilterIntent`. | Configured by you in System Settings → Focus. |

Phase 2 calendar awareness would add `NSCalendarsFullAccessUsageDescription` (macOS 14+) and
`NSCalendarsUsageDescription` (macOS 13).

---

## 5. Manual test checklist

Use the fast settings from "Testing quickly" unless a test says otherwise.

**Basics**
- [ ] First launch opens Settings; an eye icon is in the menu bar; no Dock icon.
- [ ] Quit Blink and open it again from Launchpad or the Applications folder: it starts and shows Settings.
- [ ] With *Open Blink at login* on, log out and back in: Blink starts without showing Settings.
- [ ] Menu bar shows minutes, then seconds in the last minute. Each *Menu bar shows* option works.
- [ ] Heads-up appears before the break, top-right, without stealing keyboard focus (keep typing in another app while it appears).
- [ ] Break screen fades in, counts down, plays the chime, fades out. Focus returns to the app you were in.
- [ ] **Take a Break Now**, **Skip Next Break**, each **Pause** option and **Resume** work from the menu.
- [ ] Quit and relaunch: settings are remembered.

**Multi-monitor**
- [ ] With two displays, the break covers both, and both countdowns match.
- [ ] Unplug a display during a break: the remaining display stays covered, no crash.
- [ ] Plug a display in during a break: it is covered within a second.
- [ ] The heads-up appears on the display the pointer is on.
- [ ] Displays with separate Spaces: the break appears on whichever Space each display is showing.

**Full-screen apps**
- [ ] Put Safari or Xcode in native full screen (no video): heads-up and break appear on top.
- [ ] Play a YouTube video full screen: no heads-up, no break; menu says "Break is waiting until the video stops". Exit full screen: a 10-second heads-up, then the break.
- [ ] Start a Keynote slideshow: the break is held. End it: heads-up, then break.
- [ ] Start a FaceTime or Zoom call (camera on): held. Hang up: heads-up, then break.
- [ ] Start a screen recording with ⌘⇧5: held until the recording stops.
- [ ] Add an app under *Never interrupt these apps*, keep it frontmost past the deadline: held. Switch away: break follows.

**Typing**
- [ ] Type continuously in a text editor as the heads-up reaches zero: the card changes to "Break is ready" and the break starts about 3 seconds after you stop.
- [ ] Keep typing for a full minute: the break starts anyway.

**Sleep and wake**
- [ ] Close the lid for several minutes mid-countdown and reopen: no break appears on wake; a fresh countdown starts.
- [ ] Sleep the Mac during a break: on wake the break is gone and work has resumed.
- [ ] Let the display sleep (not the Mac) for a few minutes: same as idle, fresh countdown on return.
- [ ] Leave the Mac asleep overnight: correct state next morning, no burst of breaks.

**Lock and screen saver**
- [ ] Lock the screen (⌃⌘Q) for 30+ seconds and unlock: fresh countdown; Stats shows a natural break.
- [ ] With the break length back at 20 sec, lock for only ~5 seconds: the countdown continues from roughly where it was. (An absence counts as a break once it is at least as long as a short break.)
- [ ] Start the screen saver and dismiss it after a minute: fresh countdown.
- [ ] Lock during a break: after unlocking, no stuck overlay.

**Idle reset**
- [ ] Set *Count me as away after* to 1 min. Leave the Mac untouched for 70 seconds: menu icon becomes a moon. Move the mouse: fresh countdown.
- [ ] Watch a windowed video hands-off for 2 minutes: Blink does **not** treat you as away.
- [ ] Turn idle reset off: being away no longer restarts the timer.

**Snooze limits**
- [ ] With a limit of 3: snooze three times; the label counts 2, 1, "No snoozes left"; the buttons then disable.
- [ ] After the break, the count is back to 3.
- [ ] *Limit snoozes* off: unlimited, and no label.
- [ ] *Show how many snoozes are left* off: the limit applies but the label is hidden.
- [ ] Compact heads-up: shows only the ring and time, expands on hover (or click).

**Office hours**
- [ ] Enable office hours with the end time two minutes from now: at that minute the icon changes and the menu says "Outside office hours – back …".
- [ ] Set the start to one minute from now: Blink resumes with a fresh countdown.
- [ ] Untick today's weekday: Blink goes quiet immediately.
- [ ] Overnight hours (for example 22:00 – 06:00) behave correctly at 23:00 and 05:00.
- [ ] **Pause → Until Tomorrow** shows the next office start (or midnight when office hours are off).

**Long breaks, strict mode, appearance**
- [ ] Long breaks on, every 2nd: short, long, short, long. The menu says "(long break)" when one is next.
- [ ] Strict mode: no Skip button, Esc does nothing, **Skip** is disabled in the menu.
- [ ] Each background (blur, colour, gradient, image) renders; **Preview Break Screen** works and closes.
- [ ] Switch macOS between light and dark: Settings, heads-up and the blurred break screen follow.
- [ ] Turn on *Reduce motion* in System Settings → Accessibility → Display: fades become near-instant.
- [ ] Edit, add, remove and restore break messages; a new message shows up on a break.

**Shortcuts, automation, Focus**
- [ ] Record a shortcut for each action; each works from another app. Clear one with the ✕.
- [ ] In Terminal: `open "blink://break"`, `open "blink://pause?minutes=1"`, `open "blink://resume"`.
- [ ] (Xcode build) System Settings → Focus → a Focus → Focus Filters → Add Filter → Blink → *Pause break reminders*. Turning the Focus on shows "Paused by Focus"; turning it off resumes.
- [ ] (Xcode build) The Shortcuts app lists Blink's four actions and they work.

**Wellness and stats**
- [ ] **Show Me** plays each reminder with its sound; it is click-through and leaves by itself.
- [ ] Each *Animation* choice plays in the looping preview and with **Show Me**, and sound and picture stay together.
- [ ] *Play a sound* off silences that reminder only; the volume slider changes both.
- [ ] Size, position, dimming and the caption each change the next reminder.
- [ ] With *Reduce motion* on, a reminder is a still picture that fades in and out.
- [ ] With blink reminders every 1 min, a nudge appears mid-cycle and never in the last seconds before a break.
- [ ] Stats shows today's numbers and the 7-day and 30-day charts; **Reset Statistics** clears them.

**Resources**
- [ ] In Activity Monitor, Blink sits at about 0% CPU while counting down. With *Icon only* or *Icon and minutes left* it wakes roughly every 5 seconds; only a visible seconds countdown ticks every second.

---

## 6. Phase 2 (designed for, not built)

**Calendar awareness.** Add a `.meeting` case to `HoldReason` and one check inside
`SmartPause.currentReason` that asks EventKit whether an event with other attendees is in
progress. Nothing else changes: the core already holds a break for any reason it is given.

**iPhone companion that blocks apps during Mac breaks.** Three pieces:

1. *Transport.* The Mac publishes "break started (ends at T)" and "break ended". The simplest
   reliable channel is a CloudKit private database record with a silent push subscription, so
   both devices only need the same Apple ID. `BreakScheduler.effects` already emits exactly
   these two events; a `CompanionBroadcaster` would subscribe to it.
2. *iOS app.* Requests Screen Time authorisation with `FamilyControls`
   (`AuthorizationCenter.shared.requestAuthorization(for: .individual)`), lets the user choose
   apps with `FamilyActivityPicker`, and on "break started" applies
   `ManagedSettingsStore().shield.applications`; on "break ended" clears it.
3. *Safety net.* A `DeviceActivityMonitor` extension schedules the shield's removal at the
   break's end time, so the phone unblocks even if the "ended" message never arrives.

This needs a paid Apple Developer account and the Family Controls entitlement, which is why it
is not part of a personal local build.

---

## 7. Renaming the app

"Blink" is a placeholder. To rename (say, to "Pause"):

1. `Blink/Info.plist`: change `CFBundleName`, `CFBundleDisplayName`, `CFBundleExecutable` and,
   if you like, `CFBundleIdentifier` and the URL scheme.
2. `Package.swift`: change both `name:` values (keep `path: "Blink"` unless you rename the folder).
3. `build.sh`: change `APP_NAME` (and `BUNDLE_ID` if you changed it).
4. In Xcode: click the project, rename the target, and update *Product Bundle Identifier*.
5. Search the sources for `"Blink` to update the visible strings (menu items, About page).


---

## 8. Blink and posture reminders

A reminder is a small round badge that grows from a dot, opens to show a face, plays its
animation and closes again. It is drawn in code, so it stays sharp at any size.

| Reminder | Animation | What it does |
|---|---|---|
| Blink | Squeeze (classic) | Eyes screwed shut, two quick releases, then a smile. About 2.8 s. |
| Blink | Natural blink | Open eyes that blink three times: a fast close and a slower open. About 3.2 s. |
| Blink | Slow, full blink | Two slow, complete blinks to follow along with, with a rest while shut. About 6.3 s. |
| Posture | Rise (classic) | A chevron stretches the whole badge upward and becomes an arrow. About 2.8 s. |
| Posture | Slouch to upright | A slouched seated figure sinks a little, then sits up tall. About 3.4 s. |
| Posture | Shoulder release | Shoulders lift to the ears, hold, then drop and loosen. Twice. About 4.9 s. |
| Posture | Neck stretch | The head tips toward one shoulder, then the other, and returns. About 4.9 s. |

**Where the designs come from.** The two "classic" animations follow LookAway's reminders as shown
in its public demo, which was studied frame by frame (the demo runs at about 14 frames a second):
the same sequence of movements, with timing matched to within one of its frames. They are redrawn
from scratch, not copied:
no artwork or sound from LookAway is used, and they should not be described as identical. That
demo shows one blink and one posture animation; the other five are additions in the same style.

**Sound.** Nothing is recorded or bundled. Each sound is a few soft sine tones worked out in
code (a "pop" as the badge appears, taps for quick blinks, bell-like notes and breath-like
glides). One buffer is built per animation from the same timeline that drives the picture, and
both start at the same instant, so they cannot drift apart. LookAway's own sounds could not be
examined, so these are original and only aim for the same gentle character.

**Settings** (Wellness): animation, sound on or off for each reminder, one volume for both,
size, position, optional screen dimming and an optional caption. Each animation loops in a small
preview, and **Show Me** plays it for real.

**How it is built.** `NudgeScript` (in `NudgeChoreography.swift`) turns a time into a list of
shapes and holds the sound cues. `NudgeCanvas` paints the shapes, `NudgeSoundSynth` renders the
cues, and `NudgeController` shows a see-through, click-through panel while a reminder plays.
A new animation is one more timeline plus, if it needs one, a new figure in `GlyphPen`.
