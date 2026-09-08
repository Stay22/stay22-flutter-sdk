# Stay22 Flutter SDK

Captures the travel intent your app already knows about — where the user is going
and when — and turns it into a single, well-timed local notification that opens a
Stay22 accommodation booking page, credited to your partner ID.

The package version always equals the version of the native SDK it wraps.

| Native SDK | Version | How it reaches your build |
|---|---|---|
| iOS (`Stay22SDK.xcframework`) | 1.2.0 | Bundled in this package. Nothing to set up. |
| Android (`com.stay22:sdk`) | 1.2.0 | Fetched from Stay22's Maven repository — **one line to add**, below. |

The asymmetry is not a preference. CocoaPods embeds a bundled framework happily.
Gradle will not: Flutter's own build tooling ignores any repository a plugin
declares for itself, and a plugin cannot bundle an `.aar` directly either, so the
Android SDK has to be fetched rather than carried.

Android and iOS only. Importing the package on web or desktop is safe; calling into
it throws. Guard shared code with `Stay22.isSupportedPlatform`.

## Requirements

- Flutter 3.19 or newer
- Android API 26+
- iOS 15.0+

## Installation

The package is distributed from its own public repository, pinned to a release tag.
It is not on pub.dev.

```yaml
dependencies:
  stay22_flutter:
    git:
      url: https://github.com/Stay22/stay22-flutter-sdk.git
      ref: "1.2.0"
```

**`android/build.gradle.kts`** — add Stay22's Maven repository. Without it the
Android build fails with `Could not find com.stay22:sdk`.

```kotlin
allprojects {
    repositories {
        google()
        mavenCentral()
        maven { url = uri("https://raw.githubusercontent.com/Stay22/stay22-android-sdk/main/maven") }
    }
}
```

iOS needs no equivalent step.

Then declare your partner ID natively, so the SDK starts during app launch.

**`ios/Runner/Info.plist`**

```xml
<key>Stay22PartnerAID</key>
<string>your-partner-id</string>
```

**`android/app/src/main/AndroidManifest.xml`**, inside `<application>`

```xml
<meta-data
    android:name="com.stay22.sdk.PartnerAID"
    android:value="your-partner-id" />
```

This is strongly preferred over calling `Stay22.initialize` from Dart, and on iOS it
is the only arrangement that works properly. The SDK claims the notification delegate
when it starts; Dart code runs after iOS has already decided who receives a
notification tapped from a cold start, so a Dart-only setup loses that tap and the
booking behind it. On Android it is what lets the notification permission prompt find
a live screen to appear on.

If your partner ID is only known at runtime, call `Stay22.initialize(aid: ...)` instead
and read the caveats above.

## Quick Start

```dart
import 'package:stay22_flutter/stay22_flutter.dart';

// The user's consent gate. Persisted, and safe to set before the SDK starts.
await Stay22.setEnabled(userHasOptedInToStay22Offers);

await Stay22.requestNotificationPermission();

await Stay22.setTravelContext(TravelContext(
  address: 'Paris, France',
  checkinDate: '2026-03-20',
  checkoutDate: '2026-03-25',
));
```

That is the whole integration. The SDK decides whether an offer is worth showing,
when to show it, and what to open.

## Consent And Permission

`Stay22.setEnabled(false)` stops all scheduling and clears anything already pending.
The value survives app restarts, so a user's opt-out is remembered, and it can be set
before the SDK starts — which is what makes it usable as a consent gate rather than
something you have to sequence carefully.

`requestNotificationPermission()` shows the system prompt and completes with what the
user actually chose, on both platforms. It completes immediately with the current
state when no prompt is possible: Android 12 and below, an already-denied permission,
or a notification channel the user switched off, which only system settings can undo.

## Travel Context

Supply what your app knows. Every field is optional, but the SDK needs at least an
address, a hotel name or coordinates to have somewhere to offer.

```dart
await Stay22.setTravelContext(TravelContext(
  address: 'Paris, France',
  latitude: 48.8566,
  longitude: 2.3522,
  checkinDate: '2026-03-20',   // YYYY-MM-DD or MM/DD/YYYY
  checkoutDate: '2026-03-25',
  hotelName: 'Hotel Example',
  adults: 2,
  children: 1,
));
```

Setting a context replaces the previous one; there is no merge. Dates are validated
in Dart, including rejecting dates that do not exist, so a typo throws at your call
site rather than producing a booking link for the 30th of February.

## Notification Appearance

```dart
await Stay22.setNotificationConfig(NotificationConfig(
  title: 'Hotels in {destination}',
  message: 'Tap to find the best deals nearby',
  interruptionLevel: NotificationInterruptionLevel.timeSensitive,
  actions: [NotificationAction(identifier: 'book', title: 'See deals')],
));
```

`{destination}`, `{checkin}` and `{checkout}` are filled in when the notification is
scheduled; the date placeholders resolve to empty when no dates are set. Omitting a
field uses the SDK default rather than keeping whatever a previous call set.

| Field | Default |
|---|---|
| `title` | `Hotels in {destination}` |
| `message` | `Tap to find the best deals nearby` |
| `categoryId` | `stay22_destinations` |
| `threadId` | `stay22` |

Attachments must be local files. Download a remote image first and pass the path.

## App Detection (Required on iOS)

The SDK checks which booking apps are installed so the offer can open the one the
user already has, signed in, with a saved card. iOS only answers that question for
schemes the host app declares, and silently reports "not installed" otherwise.

Add all five to `ios/Runner/Info.plist`:

```xml
<key>LSApplicationQueriesSchemes</key>
<array>
    <string>airbnb</string>
    <string>booking</string>
    <string>expda</string>
    <string>hotelsapp</string>
    <string>agoda</string>
</array>
```

Android needs nothing — the equivalent declaration ships inside the SDK.

## Scheduling

Automatic scheduling is evaluated when the app goes to the background. To run the
pipeline by hand:

```dart
await Stay22.advanced.scheduleNotification();
```

That bypasses only the background trigger. Home-city suppression, the local cooldown,
the server's decision and your partner configuration all still apply. Pass
`force: true` during integration testing to skip the local gates and shorten the delay
to a few seconds; it writes no cooldown, so it is repeatable, and it never overrides
the partner kill switch.

## Events

```dart
Stay22.events.listen((event) {
  switch (event) {
    case NotificationScheduled(:final destination, :final delay):
      print('$destination in ${delay.inMinutes} min');
    case NotificationClicked(:final destination, :final url):
      print('Tapped $destination → $url');
    case NotificationBlocked(:final reason):
      print('Blocked: $reason');
    default:
      break;
  }
});
```

The hierarchy is sealed, so an exhaustive `switch` tells you at compile time when a
new event appears.

| Event | Carries |
|---|---|
| `LocationUpdated` | `destination` |
| `NotificationScheduled` | `destination`, `delay` (a `Duration`) |
| `NotificationShown` | `destination` |
| `NotificationClicked` | `destination`, `url` |
| `NotificationBlocked` | `reason` |
| `NotificationSkipped` | `reason` |
| `NotificationCancelled` | `reason` |
| `EnabledChanged` | `isEnabled` |
| `TravelContextCleared` | — |

Listening late is safe: events raised while the app was not running are replayed to
the first subscriber. Do not call the native `setEventListener` yourself — the SDK has
one listener slot and this plugin holds it.

## Notification Delegate

**Most apps need nothing here.** The SDK installs itself as the iOS notification
delegate, chains to whatever was already there, and re-claims the slot whenever the
app becomes active.

If your app deliberately owns `UNUserNotificationCenter.delegate` — which
`firebase_messaging` and `flutter_local_notifications` both do — check
`Stay22.diagnostics.run()`. If the delegate check fails, forward the two callbacks
from `ios/Runner/AppDelegate.swift`:

```swift
import stay22_flutter
import UserNotifications

override func userNotificationCenter(
  _ center: UNUserNotificationCenter,
  didReceive response: UNNotificationResponse,
  withCompletionHandler completionHandler: @escaping () -> Void
) {
  // The guard is required. When Stay22 owns the delegate it has already handled
  // this response before calling you, and handling it twice opens the booking
  // page twice and records two clicks.
  if !Stay22FlutterPlugin.ownsNotificationDelegate,
     Stay22FlutterPlugin.handleNotificationResponse(response) {
    completionHandler()
    return
  }
  super.userNotificationCenter(center, didReceive: response,
                               withCompletionHandler: completionHandler)
}
```

`Stay22FlutterPlugin.handleWillPresentNotification(_:)` mirrors this for
`willPresent`; present the notification with at least `[.banner, .sound, .list]` —
dropping `.list` shows the banner and then loses the notification for good once it
disappears. The example app implements both.

## Diagnostics

```dart
final report = await Stay22.diagnostics.logReport();
if (!report.isHealthy) {
  for (final check in report.failures) {
    print('${check.name}: ${check.detail}');
  }
}
```

Answers "is this wired up correctly, and if not, which part is wrong?" without waiting
out a multi-hour notification delay. Side-effect free — it schedules, cancels and posts
nothing.

## Testing

```dart
await Stay22.testing.setShowLogs(true);
await Stay22.testing.setForce(true);      // ~5s delay, local gates skipped
await Stay22.testing.setBaseUrl('https://staging.example.com');
```

Never ship with these enabled.

## Example App

`example/` is a runnable integration covering travel context, notification
configuration, events, diagnostics and the iOS delegate forwarding above. It is also
what compiles the plugin's Kotlin and Swift in CI.

## Privacy

The SDK never asks for device GPS permission. The IP-derived home city is used only to
suppress offers where the user already lives, never as a destination to advertise.
Notifications are gated on `Stay22.setEnabled` and should be treated as promotional.

## API Summary

| Call | Returns |
|---|---|
| `Stay22.isSupportedPlatform` | `bool` |
| `Stay22.initialize(aid:)` | `Future<void>` |
| `Stay22.isInitialized()` | `Future<bool>` |
| `Stay22.setEnabled(bool)` / `isEnabled()` | `Future<void>` / `Future<bool>` |
| `Stay22.setMedium(String)` / `setCampaignId(String?)` | `Future<void>` |
| `Stay22.hasNotificationPermission()` | `Future<bool>` |
| `Stay22.requestNotificationPermission()` | `Future<bool>` |
| `Stay22.setTravelContext(TravelContext)` | `Future<void>` |
| `Stay22.clearTravelContext()` | `Future<void>` |
| `Stay22.setNotificationConfig(NotificationConfig)` | `Future<void>` |
| `Stay22.ownsNotificationDelegate()` | `Future<bool>` |
| `Stay22.events` | `Stream<Stay22Event>` |
| `Stay22.advanced.scheduleNotification({force})` | `Future<void>` |
| `Stay22.testing.setForce` / `setShowLogs` / `setBaseUrl` | `Future<void>` |
| `Stay22.diagnostics.run()` / `logReport()` | `Future<Stay22Diagnostics>` |

Failures arrive as a `PlatformException` whose `code` is one of
`Stay22ErrorCode.notInitialized`, `.invalidArgument`, `.missingArgument`,
`.unsupportedPlatform`, `.pluginUnavailable`, `.nativeFailure` — identical on both
platforms. Bad arguments throw `ArgumentError` or `RangeError` from Dart before
anything reaches the platform.

## Support

support@stay22.com
