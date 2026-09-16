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
  app, plus steps, distance, and live heart rate.
- **Sensors** — scans for and pairs with a nearby BLE band, shows live
  heart rate (with a short graph), SpO2, cadence, battery, body
  composition (weight/body fat/lean mass), etc., plus a read-only list of
  ECG recordings already in Health.
- **Trends** — 7-day step and active-energy history, read back from Health.
- **Goals** — editable Move/Exercise/Stand targets, persisted locally.
- **Settings** — Health authorization status and paired-device management.

## How it talks to your band

`Sources/Bluetooth` implements a generic Core Bluetooth client for the
**standard Bluetooth SIG GATT profiles** most fitness bands expose:

| Data | Service | Characteristic |
|---|---|---|
| Heart rate | Heart Rate (`180D`) | Heart Rate Measurement (`2A37`) |
| Battery | Battery (`180F`) | Battery Level (`2A19`) |
| Cadence / distance | Running Speed and Cadence (`1814`) | RSC Measurement (`2A53`) |
| SpO2 | Pulse Oximeter (`1822`) | Spot-check Measurement (`2A5E`) |
| Weight / body fat / lean mass | Body Composition (`181B`) | Body Composition Measurement (`2A9C`) |

Cheap/generic bands vary a lot in what they actually implement, and many
push steps, sleep, and SpO2 through **vendor-specific** services instead
of these standard ones. `Sources/Bluetooth/GattProfiles.swift` has a
`VendorService`/`VendorSensorDecoder` extension point — add your exact
band's UUIDs and a decoder there once you know them (a BLE sniffer app
like LightBlue is the easiest way to find them).

## How it talks to Apple Health

`Sources/HealthKit/HealthKitManager.swift` requests read/write access and
writes heart rate, step count, distance, active energy, blood oxygen, and
body composition (body fat %, weight, and fat-free mass mapped to
HealthKit's `leanBodyMass`) as it receives them — these are ordinary
HealthKit types any app can write, so they show up in Health and count
toward your existing totals immediately.

**ECG is not writable by this app, and that's not a bug to fix later.**
Apple lets any app *read* ECG recordings that are already in Health (e.g.
ones an Apple Watch took), but *writing* a new ECG recording requires a
dedicated entitlement Apple only grants to reviewed medical-device
accessory makers through a formal application process — it's not a
capability you can enable in Xcode or a project file. So the Sensors tab
shows a read-only list of existing ECG recordings (classification +
average heart rate, via `HealthKitManager.fetchRecentECGs`), and the app
never attempts to record a new one from band data.

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

## Project structure

```
Sources/
  App/            App entry point, root TabView
  Models/         Plain data types (SensorReading, DailyActivity, Goals, BandDevice)
  Bluetooth/       CBCentralManager wrapper, GATT UUIDs, characteristic parsers
  HealthKit/       HKHealthStore wrapper: auth, writes, today's totals, 7-day history
  Sync/           Glues Bluetooth readings -> HealthKit writes + ring estimates
  Views/          Today / Sensors / Trends / Goals / Settings, one folder each
  Extensions/
  Resources/      Assets.xcassets (add your own AppIcon image — a 1024x1024
                   slot is scaffolded but empty)
Tests/
  AppleHealthBandTests/   Pure-logic unit tests for the BLE parsers and ring math
```

There's no hand-edited `.xcodeproj` in the repo — see setup below for why.

## Setup

**Requirements:** macOS with Xcode 15+, and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`).

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
