# Lift + Run + Body

Native SwiftUI iOS app (iOS 17+) for lifting, with runs and Renpho body composition pulled in from Apple Health.

- **Lift**: routines, live set logging pre-filled from your last session, double progression (all sets at the top of the rep range → next session pre-fills heavier), rest timer, PR detection, per-exercise history charts, plate math, supersets, five exercise types (weight × reps, bodyweight, assisted, timed, distance + weight).
- **Run**: running workouts from Apple Health with route map, splits and heart rate.
- **Body**: Renpho trend weight, body fat, lean mass, rate and goal ETA; manual weigh-ins when the scale isn't syncing.
- **Trends**: relative strength, weekly training load, weight vs. lean mass.
- **Live Activity + Dynamic Island** for the rest timer; **widgets**: trend weight (small), next up (small), this week (medium).
- Import old workouts by pasting free-text notes ("Bench 205x5, 205x5", "Pullups 12, 10, 9"); exercise-name aliases are remembered.

All data is stored on-device with SwiftData. The shipping build starts empty (first-day state); nothing is seeded.

## Project layout

| Path | What |
| --- | --- |
| `project.yml` | XcodeGen spec (app + widget extension). `LiftRunBody.xcodeproj` is generated from it and checked in. |
| `Config/Signing.xcconfig` | **Your Team ID and bundle ID prefix** — the only file you need to edit. |
| `App/Sources` | App: models, progression/PR logic, HealthKit, rest timer, views. |
| `Widgets` | WidgetKit extension: home-screen widgets and the rest-timer Live Activity. |
| `Shared` | Code compiled into both targets (palette, App Group, widget snapshot, Live Activity attributes, intents). |

## 1. Open the project

Requires Xcode 16 or newer.

```sh
git clone https://github.com/Colhodm/fitness.git
cd fitness
open LiftRunBody.xcodeproj
```

If you change `project.yml`, regenerate the project with `brew install xcodegen && xcodegen generate`.

## 2. Set your team and bundle ID

Edit `Config/Signing.xcconfig`:

```
DEVELOPMENT_TEAM = ABCDE12345        // developer.apple.com → Account → Membership details → Team ID
BUNDLE_ID_PREFIX = com.yourname      // any reverse-DNS prefix you own
```

That one prefix drives every identifier:

| | Identifier |
| --- | --- |
| App | `<prefix>.LiftRunBody` |
| Widget extension | `<prefix>.LiftRunBody.Widgets` |
| App Group (shared by both) | `group.<prefix>.LiftRunBody` |

The Simulator builds without a team; a device or TestFlight build needs one.

## 3. Capabilities

The entitlements are already in the project (generated from `project.yml`):

- **LiftRunBody** (app): HealthKit, App Groups (`group.<prefix>.LiftRunBody`). Live Activities are enabled through `NSSupportsLiveActivities` in Info.plist.
- **LiftRunBodyWidgets** (extension): App Groups (same group).

With **Automatically manage signing** (the default here), Xcode registers the App IDs, the App Group and the HealthKit capability for you the first time you build to a device or archive. If it complains:

1. Open the project → target **LiftRunBody** → **Signing & Capabilities**, confirm your team is selected, and that **HealthKit** and **App Groups** (with `group.<prefix>.LiftRunBody` ticked) are listed. Click "Try Again" if Xcode offers it.
2. Do the same for target **LiftRunBodyWidgets** (App Groups only).
3. If you sign manually instead: at developer.apple.com → Certificates, IDs & Profiles, create the App Group `group.<prefix>.LiftRunBody`, then the two App IDs above with **App Groups** enabled on both and **HealthKit** on the app, and assign the group to both.

## 4. Run on your iPhone

Plug in the phone (or pair over Wi-Fi), pick it as the run destination and press ⌘R. On first launch the app walks you through units, Apple Health access and weekly goals. In the Health permission sheet, **Turn On All** so weight, body fat, lean mass, workouts, routes and heart rate come through.

Renpho must be writing to Apple Health: Health app → profile → Apps → Renpho Health → Turn On All.

## 5. Ship to TestFlight

1. In App Store Connect (appstoreconnect.apple.com) → **Apps** → **+** → **New App**: platform iOS, name "Lift + Run + Body" (or any available name), bundle ID `<prefix>.LiftRunBody`, any SKU.
2. In Xcode, set the run destination to **Any iOS Device (arm64)**.
3. **Product → Archive**.
4. In the Organizer that opens: **Distribute App → App Store Connect → Upload** (keep the defaults: automatic signing, upload symbols).
5. After processing (usually 5–15 minutes) the build shows in App Store Connect → your app → **TestFlight**. Answer the export-compliance question if asked (the app declares no non-exempt encryption).
6. Add yourself under **Internal Testing**, then install from the TestFlight app on your iPhone.

For later builds, bump `CURRENT_PROJECT_VERSION` (and `MARKETING_VERSION` for a new version) in `project.yml` and regenerate, or edit them in the target's build settings.

## Debug sample data (Simulator only)

Debug builds accept launch arguments for screenshots; none of this is compiled into Release builds. Add them under **Product → Scheme → Edit Scheme → Run → Arguments**:

| Argument | Effect |
| --- | --- |
| `-sampleData` | In-memory store with ~12 weeks of Push/Pull/Legs history, plus fake Renpho weigh-ins and runs |
| `-firstDay` | With `-sampleData`: no workouts (first-day state) |
| `-staleRenpho` | Last weigh-in 5 days ago (stale-scale state) |
| `-noRuns` | No runs (Health access-off state) |
| `-onboarding` | Show onboarding |
| `-tab today\|lift\|run\|body\|trends` | Start on a tab |
| `-open "exercise:Bench Press"`, `-open run:long`, `-open settings`, `-open import`, `-open routine:Pull` | Open a screen |
| `-active Pull -activeSets 4` | Mid-workout with a rest timer running |
| `-summary` | Workout summary for the most recent workout |

Settings → Data also has "Load sample data (debug)" / "Erase all workouts (debug)" in Debug builds.
