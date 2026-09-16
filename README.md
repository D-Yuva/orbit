# Orbit

A native macOS notch companion for reminders and focused work.

The avatar uses the transparent LEGO Batman cutout supplied by the user, bundled locally. A native SwiftUI character rig supplies six eye and mouth expressions while preserving the supplied cowl, costume, lighting, and textures.

Orbit extends your Mac’s camera notch straight down without widening it. The avatar’s upper body sits below the camera area, with two hands resting over the bottom edge. Native view clipping trims the residual fringe in the supplied cutout. Reminder text appears in a compact callout to the right, with softer SF Rounded typography, an adaptive frosted material, and subtle borders. Hover shows only the upcoming reminder or focus countdown. Click the message to reveal **Pause** (or **Resume** when paused); the first click only opens controls. Pause stops reminders for one hour. Active reminders also reveal **Done**, **5 min**, and dismiss controls after a message click. The interface follows macOS light/dark appearance and Reduce Transparency.

On a notched display, the black extension uses the exact measured hardware width. When collapsed, Orbit draws no additional shape, shadow, or avatar; its invisible hover area fits the hardware notch exactly. Displays without a notch use a 188-point fallback. The speech bubble has its own nonactivating window so the transparent space between the notch and bubble does not intercept desktop clicks.

## Run

Requires macOS 14 or later and the Xcode Swift toolchain. No third-party dependencies or Python environment are needed. SwiftPM build files and compiler caches stay in `.build/` inside this project.

```sh
zsh scripts/build-app.sh
open build/Orbit.app
```

Closing the controls leaves Orbit running. Use the Orbit menu bar icon to reopen controls or quit.

## Focus timer

Open **Focus** in the main app, or choose **Focus timer…** from the Orbit menu. Choose 15, 25, 45, or 60 minutes, or enter a duration from 1 to 180 minutes. Once started, click the countdown to reveal **Pause** and **Cancel**. The first click only opens the controls. Pause freezes the remaining time and becomes **Resume**; Cancel ends the session without a completion sound or message. The same interaction works on the countdown message beside the notch. These controls affect the focus timer independently of the general one-hour reminder pause. Your chosen duration is saved for next time. Clicking Batman also keeps the optional small timer beside the notch; click outside or press Escape to close that panel. The timer keeps running when either view closes.

**Pause reminders** starts enabled. Scheduled nudges and their sounds stay quiet throughout running and paused focus sessions. Change the toggle in the timer panel or **Settings → During focus**. When focus ends, is reset, or this protection is switched off, reminder intervals start fresh, so missed reminders do not pile up.

Focus uses an absolute deadline and accounts for sleep. It finishes independently of reminder pause and quiet hours, with the chosen completion sound and a message. If another reminder is visible, its message finishes first; if the timer panel is open, it shows completion there and presents the message after closing. Quitting Orbit ends the active session.

## Audio

Tap the speaker in the focus panel or the app header, or open the **Audio** tab. Focus completion, stretching, and other reminders each have their own sound toggle and a choice of **Pop, Tink, Chime, or Ping**. A speaker beside each choice previews that sound, including when its automatic alerts are muted. The compact audio page stays inside the timer panel; its back button returns to the timer without interrupting focus.

Stretch reminders default to every hour with Pop; focus completion defaults to Chime. Focus and stretch sounds start enabled; other reminder sounds retain your existing preference. Sound volume follows the Mac’s output volume.

## Reminders

Open **Reminders & settings…** from the menu bar, then **Add reminder**, or use the visible **Edit** button beside a reminder. Write a name and message, choose **Repeat every** (1–1,440 minutes or 1–24 hours) or **Daily at**, and pick an expression. Save applies your changes; Cancel discards the draft. The list shows your message and schedule. All customization stays in the app window.

- Water, stretching, eye breaks, and meal reminders with editable intervals or daily times.
- Custom reminders and messages; an empty custom message uses its reminder name.
- Five-minute snooze, completion tracking, and one-hour pause.
- Quiet hours, separate reminder and focus sounds, and adjustable reading time.
- English, Tamil, Hindi, and Telugu; optional English translations.
- Natural, Soft, and Mono appearances.
- Six expressions: hopeful for water, cheerful for stretching, peaceful closed eyes for eye breaks, hungry for meals, yawning for rest, and surprised for custom reminders.
- Expression changes fade smoothly and respect Reduce Motion.
- See the avatar’s expressions in the Companion tab.

Intervals begin when Orbit launches or the Mac wakes; a manual pause resets intervals on resume. Daily reminders use the next occurrence of their local time, including daylight-saving changes. Quiet hours suppress scheduled reminders; daily occurrences scheduled inside quiet hours are skipped. Ending focus, waking, or resuming after a manual pause starts fresh intervals and uses the next future daily time. Reminder-preview buttons and menu commands are removed; sound auditions remain available through the audio speakers. Reminders due together are staggered, and a visible reminder finishes before another appears.

Preferences and the last 100 activity records live in `~/Library/Application Support/Orbit/`. There are no accounts, analytics, network calls, calendar permissions, microphone permissions, or screen recording permissions. The app’s visual verification renders its own views only.

## Verify

```sh
zsh scripts/test.sh
build/Orbit.app/Contents/MacOS/Orbit --snapshot "$PWD/build/orbit-previews"
```

The developer snapshot command briefly presents the app’s own windows and renders the controls, all six reminder fixtures, notch states, controls revealed by clicking, regional text, a long custom message, focus setup/running/paused/completed states, and the compact audio page. `batman-reminders.png` shows the six reminders together; `avatars/` contains six transparent PNG exports of the native expression views. Each notch PNG composites the separate notch and callout at their real relative positions; JSON files record their geometry, reminder kind, and artwork loading mode. It uses temporary in-memory preferences, stays silent, and does not start reminder timers.

This is a local prototype with an ad-hoc signature. Calendar integration, app-usage tracking, launch at login, and a notarized public installer are not implemented.

## Artwork

Both source uploads are preserved: `Sources/Orbit/Assets/batman-reference.png` (1000 × 667) and `batman-cutout.png` (1568 × 1576, with alpha). Their provenance is documented in [Resources/avatar-source.txt](Resources/avatar-source.txt). The expression overlay and silhouette mask are native view layers calibrated to this cutout; the PNG itself is not modified. Hands use framed portions of the same supplied image. Exported variations are renders of these UI states, not AI-generated images. Earlier failed generation attempts remain recorded in [Resources/batman-prompts.txt](Resources/batman-prompts.txt). No image generation or network request runs inside the app.
