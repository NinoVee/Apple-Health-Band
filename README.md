# Apple Health Band

An iOS app that connects to a Bluetooth LE smart band, reads its sensors in
real time, displays Apple-Activity-style Move/Exercise/Stand rings, and
syncs the data it collects into Apple Health automatically.

> **Built without Xcode.** This project was scaffolded in a Linux
> environment, so the Swift/SwiftUI source has been written to compile
> against public Apple APIs but has **not** been built, run in a
> simulator, or tested on a device. Open it in Xcode and do a first build
> before relying on it — see "Known rough edges" below for what's most
> likely to need a tweak.

## What it does

- **Today** — Move / Exercise / Stand rings, styled after Apple's Activity
  app, plus steps, distance, live heart rate, and a highlighter-green
  workout picker (8 types) that starts a real, Health-recorded workout
  session. See "Workouts" below.
- **Sensors** — scans for and pairs with a nearby BLE band, shows live
  heart rate (with a short graph and a computed HRV/SDNN readout), SpO2,
  cadence, battery, body temperature, body composition (weight/body
  fat/lean mass), etc., plus a read-only list of ECG recordings already
  in Health.
- **Trends** — a segmented Activity/Scale switcher in the nav bar:
  - *Activity*: step and active-energy history, read back from Health,
    with a Week/Month/Year range picker (daily bars for Week/Month,
    monthly bars for Year).
  - *Scale*: a manually-logged smart-scale history — weight, height,
    BMI, body fat %, fat-free body weight, muscle mass, bone mass,
    visceral fat, subcutaneous fat, and basal metabolic rate, plus a
    weight-over-time chart. See "Scale log" below for what syncs to
    Health vs. what stays local.
- **AI Insights** — a chat tab where you can ask Claude or ChatGPT about
  your Health data, with optional photo attachments. Off by default;
  see "AI Insights" below.
- **Settings** — Move/Exercise/Stand goal editors, Health authorization
  status, paired-device management, a Light/Dark/System appearance
  toggle, and AI Insights configuration.

## How it talks to your devices

`Sources/Bluetooth/BandBluetoothManager.swift` can hold **several
simultaneous connections** — a wrist band, a smart scale, and a blood
pressure cuff can all be paired and reporting into the app at once.
CoreBluetooth itself has no problem with multiple concurrent peripheral
connections; `BandBluetoothManager` tracks connection state per device
(`connectionStates: [UUID: ConnectionState]`) and persists every paired
device's ID so all of them reconnect automatically on next launch, not
just the most recent one. Since the parsers below key off the
*characteristic*, not which physical product sent it, a scale
implementing the standard Body Composition Service and a cuff
implementing the standard Blood Pressure Service work with the exact
same decoding code as the band — no per-device-type logic needed. Go to
Sensors → **Add a device** once per accessory to pair each one; they all
stay connected together, and each just syncs whatever it reports.

The one shared bit of state across devices is `latestReadings` — if two
connected devices report the *same* kind of reading (e.g. a wrist band's
PPG heart rate and a cuff's pulse rate), the more recent one simply wins,
same "latest reading" rule the rest of the app already uses. In
practice this rarely matters since a band, scale, and cuff mostly report
non-overlapping kinds.

`Sources/Bluetooth` implements a generic Core Bluetooth client for the
**standard Bluetooth SIG GATT profiles** most fitness bands expose:

| Data | Service | Characteristic |
|---|---|---|
| Heart rate | Heart Rate (`180D`) | Heart Rate Measurement (`2A37`) |
| Battery | Battery (`180F`) | Battery Level (`2A19`) |
| Cadence / distance | Running Speed and Cadence (`1814`) | RSC Measurement (`2A53`) |
| SpO2 | Pulse Oximeter (`1822`) | Spot-check Measurement (`2A5E`) |
| Weight / body fat / lean mass | Body Composition (`181B`) | Body Composition Measurement (`2A9C`) |
| Body temperature | Health Thermometer (`1809`) | Temperature Measurement (`2A1C`) |
| Blood pressure | Blood Pressure (`1810`) | Blood Pressure Measurement (`2A35`) |

Blood pressure is written to Health as a paired `HKCorrelation`
(systolic + diastolic together), not two independent samples, so it
displays as one linked "120/80" reading rather than two unrelated
numbers — see `HealthKitManager.writeBloodPressure`. If the cuff
includes a pulse rate in the same measurement (a common optional
field), it's surfaced as an ordinary heart rate reading too.

Heart rate variability isn't its own GATT profile — it's computed
in-app from **RR intervals** (beat-to-beat gaps), which the standard
Heart Rate Measurement characteristic already carries as an optional
field when a band supports it. `ActivitySyncCoordinator` keeps a rolling
window of RR intervals and computes SDNN (their standard deviation), the
same statistic behind HealthKit's `heartRateVariabilitySDNN` — a real
computation, just a simpler rolling window rather than Apple Watch's
full pipeline.

Cheap/generic bands vary a lot in what they actually implement, and many
push steps, sleep, and SpO2 through **vendor-specific** services instead
of these standard ones. `Sources/Bluetooth/GattProfiles.swift` has a
`VendorService`/`VendorSensorDecoder` extension point — add your exact
band's UUIDs and a decoder there once you know them (a BLE sniffer app
like LightBlue is the easiest way to find them).

## How it talks to Apple Health

`Sources/HealthKit/HealthKitManager.swift` requests read/write access and
writes heart rate, step count, distance, active energy, blood oxygen,
blood pressure, body temperature, heart rate variability (SDNN), height,
BMI, basal metabolic rate, and body composition (body fat %, weight,
and fat-free mass mapped to HealthKit's `leanBodyMass`) as it receives
them — these are ordinary HealthKit types any app can write, so they
show up in Health and count toward your existing totals immediately.
This is the full set of vitals/metrics this app collects that Health
actually has a data type for — see the table above and "Scale log"
below for exactly what maps to what.

**ECG is not writable by this app, and that's not a bug to fix later.**
Apple lets any app *read* ECG recordings that are already in Health (e.g.
ones an Apple Watch took), but *writing* a new ECG recording requires a
dedicated entitlement Apple only grants to reviewed medical-device
accessory makers through a formal application process — it's not a
capability you can enable in Xcode or a project file. So the Sensors tab
shows a read-only list of existing ECG recordings (classification +
average heart rate, via `HealthKitManager.fetchRecentECGs`), and the app
never attempts to record a new one from band data.

## Workouts

The Today tab's workout grid (`Sources/Views/Components/WorkoutControlsView.swift`,
`Sources/Models/WorkoutType.swift`) covers 8 types — Running, Weight
Training, Swimming, Cycling, Yoga, Boxing, Basketball, Tennis — each a
highlighter-green push button, Apple Fitness-style. Tapping one starts a
real `HKWorkoutSession` via `Sources/Workout/WorkoutSessionManager.swift`.

**`HKWorkoutSession`/`HKLiveWorkoutBuilder`/`HKLiveWorkoutDataSource`
require iOS 26** — they were watchOS-only before that, when Apple added
iOS support specifically so third-party accessories (not just Apple
Watch) can record real workouts to Health. That's why the app's
deployment target is iOS 26.0, not the iOS 17 it started at — building
against these APIs with a lower minimum fails at compile time (this
was actually discovered as a build error, not read from a changelog, so
trust the compiler over any doc that says iOS 17 elsewhere). Ending a
workout here produces an actual `HKWorkout` — duration, calories,
average heart rate — that shows up in the Fitness/Health apps like any
Watch-recorded workout, not a pile of disconnected samples. This needs
the `workout-processing` background mode (already in `project.yml`) so
a session can keep running if you background the app mid-workout.

**What "calibrated per exercise" actually means here** — worth being
precise about, since it's easy to overclaim:
- `WorkoutType.healthKitActivityType` tells HealthKit which activity
  this is, so **Health's own** calorie/zone algorithms calibrate to it —
  the same heart rate produces a different calorie estimate for running
  vs. yoga. This app doesn't compute that; Apple's does, correctly, once
  it knows the activity type.
- `WorkoutType.exerciseHeartRateThreshold` calibrates
  `ActivitySyncCoordinator`'s own exercise-minute heuristic per activity
  (e.g. yoga's threshold is lower than boxing's) while a workout is active.
- `WorkoutType.scanningInterval`, applied via
  `BandBluetoothManager.setScanningInterval`, controls how often the app
  re-polls **read-only, non-notify** BLE characteristics during a
  workout. This is the one real lever the app has over "scanning
  frequency" — a connected device's notify-based sensors (heart rate,
  etc.) push updates on their own firmware schedule regardless of this
  setting, and no generic BLE central can make a peripheral's physical
  sensor sample faster than its own firmware does.

Start/Pause/Resume/End map directly to `HKWorkoutSession`'s state
machine; ending a workout also stops the calibrated re-poll timer.

## Appearance

Settings has a Light/Dark/System segmented picker (`AppearanceMode`,
backed by `@AppStorage`), applied once via `.preferredColorScheme(...)`
on `RootView`'s `TabView` — every screen and sheet inherits it. "System"
(the default) follows the device's own appearance setting.

**One real Apple constraint to know about:** `appleExerciseTime`,
`appleStandTime`, and `appleStandHour` — the data types behind Apple's
*own* Exercise and Stand rings — can only be written by Apple Watch.
HealthKit rejects writes to them from any other app, including this one.
So:

- The app **reads** those types, and if you also have an Apple Watch, its
  real Exercise/Stand data will show up in this app's rings too.
- When there's no Watch data, `Sources/Sync/ActivitySyncCoordinator.swift`
  computes its own on-device estimate from the band's heart rate and
  cadence (exercise minutes while heart rate is elevated; a stand "hour"
  credited for any clock hour with elevated heart rate or movement) so
  the rings still move. This is a documented heuristic, not Apple's
  proprietary algorithm — don't expect it to match a Watch exactly.

Steps written by the app are Health's real, shared `stepCount` type, so a
Watch or other app's steps and this app's band-derived steps combine into
one daily total, same as Health does for any two sources.

## Scale log

The Scale section of Trends (`Sources/Views/Scale/`) is a manual entry
log — this app
doesn't talk to a body-composition scale over Bluetooth, since those are
almost always Wi-Fi/cloud devices (Withings, Renpho, etc.) tied to their
own manufacturer app, not exposed over BLE the way a wrist band's sensors
are. You type in what the scale's own app shows you.

**What syncs to Apple Health** (real HealthKit quantity types any app can
write): weight, height, BMI, body fat %, fat-free body weight (mapped to
`leanBodyMass`), and basal metabolic rate (mapped to `basalEnergyBurned`).

**What stays in this app's own log only:** muscle mass, bone mass,
visceral fat rating, and subcutaneous fat %. This isn't a missing
feature to fix — Apple Health simply has no data type for any of these,
for any app, so there's nothing to sync them *to*. `ScaleLogStore`
persists the full entry (all fields) locally via `UserDefaults` so
they're still tracked and chartable inside the app.

Entries are logged in either Metric or Imperial units in the form; a
"Calculate BMI from weight & height" button offers `ScaleEntry`'s BMI
formula as a convenience, but you can always type in the exact value
your scale displayed instead — its formula may differ slightly.

## AI Insights

A chat tab (`Sources/Views/Insights/HealthChatView.swift`) where you can
ask Claude or ChatGPT questions about your Health data. **Off by default**
— nothing is sent anywhere until you turn it on in Settings and send a
message yourself.

**Architecture, and why:** the app never holds an Anthropic/OpenAI API
key directly — an API key embedded in an app binary can be extracted by
anyone who decompiles it, and then spent against your account. Instead,
the app calls a small relay server (`Server/`, a Vercel serverless
function) that you deploy and that holds the real API keys as
server-only environment variables. See **`Server/README.md`** for
deploy steps — you need to do this before the feature works; there's no
built-in server.

**What actually gets sent:** on each message, `HealthContextBuilder`
builds a plain-text summary from the same aggregate numbers already
shown on the Today/Sensors/Scale tabs (steps, heart rate, SpO2, body
composition, your latest scale log entry, etc.) — never raw HealthKit
samples — plus the visible chat conversation. `Settings → AI Insights`
also has a Shared Secret
field: it's a weaker, app-side secret (separate from your real API
keys) that just keeps random internet traffic off your relay endpoint;
set the same value in both places.

**Photo attachments:** tap the photo icon next to the text field to
attach a picture from your library (via `PhotosPicker` — no photo
library permission prompt needed, since it runs out-of-process). It's
downscaled and JPEG-compressed on-device (`ImageResizer`, max 1024px,
~0.7 quality) before sending, then included as an image block in the
relay's request — both `claude-sonnet-4-5` and `gpt-4o-mini` (the
default models) accept image input, so no model change was needed.
Chat history, images included, lives only in memory for the session —
nothing is written to disk, and it clears when you tap Clear Chat or
relaunch the app.

This sends health information (and, if you attach one, a photo) to a
third-party AI service by design — that's the feature. Treat its
answers as informational, not medical advice; the relay's system
prompt tells the model the same thing.

## Project structure

```
Sources/
  App/            App entry point, root TabView
  Models/         Plain data types (SensorReading, DailyActivity, Goals, BandDevice,
                   ScaleEntry/ScaleLogStore, TrendRange, WorkoutType, ...)
  Bluetooth/       CBCentralManager wrapper, GATT UUIDs, characteristic parsers
  HealthKit/       HKHealthStore wrapper: auth, writes, today's totals, Trends history
  Sync/           Glues Bluetooth readings -> HealthKit writes + ring/HRV estimates
  Workout/        WorkoutSessionManager: HKWorkoutSession/HKLiveWorkoutBuilder lifecycle
  AI/             Health summary builder, relay client, chat view model, image resizer
  Views/          Today / Sensors / Trends / Scale / Goals / Insights / Settings folders —
                   Scale and Goals are embedded in Trends and Settings, not their own tabs
  Extensions/
  Resources/      Assets.xcassets (add your own AppIcon image — a 1024x1024
                   slot is scaffolded but empty)
Tests/
  AppleHealthBandTests/   Pure-logic unit tests for the BLE parsers and ring math
Server/
  api/chat.js     Vercel serverless relay for AI Insights — see Server/README.md
```

There's no hand-edited `.xcodeproj` in the repo — see setup below for why.
`Server/` is a separate Node.js project, deployed independently (not
part of the Xcode project or iOS build).

## Setup

**Requirements:** macOS with a version of Xcode that includes the iOS 26
SDK (needed for `HKWorkoutSession` on iOS — see "Workouts" above), and
[XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).
The app's deployment target is iOS 26.0, so it needs a device or
Simulator running iOS 26+ to build and run.

1. Clone the repo and generate the Xcode project:
   ```bash
   git clone https://github.com/NinoVee/apple-health-band.git
   cd apple-health-band
   xcodegen generate
   open AppleHealthBand.xcodeproj
   ```
   (`project.yml` is the source of truth — `Info.plist`, entitlements, and
   the `.xcodeproj` itself are all generated from it and gitignored. If
   you don't want to install XcodeGen, you can instead create a new iOS
   App project in Xcode by hand, add the files under `Sources/` to it,
   and copy the `Info.plist`/entitlement keys from `project.yml`.)

2. In **Signing & Capabilities**:
   - Set your Team so the app can be signed.
   - Confirm **HealthKit** is enabled (added from the entitlements file
     XcodeGen generates; add it manually via the `+ Capability` button if
     Xcode doesn't pick it up).
   - Confirm **Background Modes** has "Uses Bluetooth LE accessories" and
     "Background processing" checked.
   - HealthKit requires a paid Apple Developer account for on-device
     testing (it won't run in the Simulator, which has no Health app).

3. Build and run on a physical iPhone. On first launch it will prompt for
   Bluetooth and Health permissions — accept both, then go to **Sensors**
   to scan for and pair your band.

4. Run the unit tests (`Cmd+U`) to sanity-check the BLE parsing and ring
   math without needing hardware.

## Known rough edges to check on first build

- If your band doesn't expose any of the standard GATT services above,
  the Sensors tab will show a connected device with no live readings —
  you'll need to add its vendor UUIDs (see "How it talks to your band").
- The app icon slot in `Assets.xcassets` is empty; add a 1024×1024 image
  or Xcode will warn about a missing app icon at archive time.
- `DEVELOPMENT_TEAM` isn't set in `project.yml` (there's no team ID to
  put there) — set it in Xcode's Signing tab after the first
  `xcodegen generate`.
