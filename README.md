# Stay22 Flutter SDK

Captures the travel intent your app already knows about — where the user is going
and when — and turns it into a single, well-timed local notification that opens a
Stay22 accommodation booking page, credited to your partner ID.

This release wraps native SDK 3.1.1 on both platforms.

| Native SDK | Version | How it reaches your build |
|---|---|---|
| iOS (`Stay22SDK.xcframework`) | 3.1.1 | Bundled in this package. Nothing to set up. |
| Android (`com.stay22:sdk`) | 3.1.1 | Fetched from Stay22's Maven repository — **one line to add**, below. |

The asymmetry is not a preference. CocoaPods embeds a bundled framework happily.
Gradle will not: Flutter's own build tooling ignores any repository a plugin
declares for itself, and a plugin cannot bundle an `.aar` directly either, so the
Android SDK has to be fetched rather than carried.

Android and iOS only. Importing the package on web or desktop is safe; calling into
it throws. Guard shared code with `Stay22.isSupportedPlatform`.

## Requirements

- Flutter 3.19 or newer
- Android API 24+
- iOS 15.0+

## Installation

The package is distributed from its own public repository, pinned to a release tag.
It is not on pub.dev.

The examples below describe this source tree. For a released package, use the README
at the tag you install; the published package may expose a different API.

```yaml
dependencies:
  stay22_flutter:
    git:
      url: https://github.com/Stay22/stay22-flutter-sdk.git
      ref: "3.1.1"
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
<!-- Add this if your app requires an affirmative consent choice. -->
<key>Stay22RequiresConsent</key>
<true/>
```

**`android/app/src/main/AndroidManifest.xml`**, inside `<application>`

```xml
<meta-data
    android:name="com.stay22.sdk.PartnerAID"
    android:value="your-partner-id" />
<!-- Add this if your app requires an affirmative consent choice. -->
<meta-data
    android:name="com.stay22.sdk.RequiresConsent"
    android:value="true" />
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

// Illustrative app-chosen validity bounds, not SDK defaults.
final now = DateTime.now().millisecondsSinceEpoch;
final request = NotificationRequest(
  trip: TravelContext(address: 'Paris, France'),
  timing: const NotificationTiming.after(delayMs: 30 * 60 * 1000),
  expiresAtMs: now + 12 * 60 * 60 * 1000,
  actionExpiresAtMs: now + 24 * 60 * 60 * 1000,
);
final result = await Stay22.ensureNotification(request);
```

Inspect `result.outcome` and `result.reason`, and save the receipt's reference when one
is returned. Submission is an acknowledgement; preparation can still reject the offer.
Retain the same request and deadlines when retrying the same occurrence.

## Consent And Permission

`Stay22.setEnabled(false)` stops all scheduling and clears anything already pending,
including a notification being prepared at the same time. The value survives app
restarts and can be set before the SDK starts. If your app requires an affirmative
consent choice, declare the native consent-required keys above, then pass the app's
current choice to `setEnabled` on each launch before sending travel context.

`requestNotificationPermission()` shows the system prompt and completes with what the
user actually chose, on both platforms. It completes immediately with the current
state when no prompt is possible: Android 12 and below, an already-denied permission,
or a notification channel the user switched off, which only system settings can undo.

## Travel Context

Supply what your app knows. Every field is optional, but the SDK needs at least an
address, a hotel name or coordinates to have somewhere to offer.

```dart
final trip = TravelContext(
  address: 'Paris, France',
  latitude: 48.8566,
  longitude: 2.3522,
  checkinDate: '2027-03-20',   // YYYY-MM-DD
  checkoutDate: '2027-03-25',
  hotelName: 'Hotel Example',
  adults: 2,
  children: 1,
);
```

Each request carries a complete trip. Omitted fields do not inherit values from an earlier
request, so collect partial form data in your app before submitting it. For a different
trip, use `replaceNotification` with the saved reference and the complete new request.
Replacement revokes the previous offer before preparing the new one, even if the new
request is rejected.

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
field resets it rather than keeping whatever a previous call set. An unset `title` or
`message` shows your account's text for the trip, then the built-in text; set both to
keep fixed text.

| Field | Default |
|---|---|
| `title` | unset: your account's text, else `Hotels in {destination}` |
| `message` | unset: your account's text, else `Tap to find the best deals nearby` |
| `categoryId` | `stay22_destinations` |
| `threadId` | `stay22` |

Attachments must be local files. Download a remote image first and pass the path.

## App Detection (Required on iOS)

The SDK checks which booking apps are installed so the offer can open the one the
user already has, signed in, with a saved card. iOS only answers that question for
schemes the host app declares, and treats any other app as unknown.

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

Use `ensureNotification` to submit a trip and timing request. Timing can use the account
default, a delay, a not-before time or a fixed time. Timestamps and durations are in
milliseconds. Give execution and notification actions separate expiry deadlines, as in the
quick start; if omitted, a valid cached account policy must supply them.

Use the saved reference with `updateNotification` to change timing, `replaceNotification`
to replace a trip, or `cancelNotification` to cancel it. Retain the original reference and
arguments when retrying a command. An update supplies a complete new timing intent:
omitting `allowedWindows` removes your restriction, and omitted deadlines require a valid
cached account policy. Read `getNotificationState()` or listen for `NotificationChanged`
to inspect later state. A queued notification does not prove that the operating system
displayed it at the selected time.

## Events

```dart
Stay22.events.listen((event) {
  switch (event) {
    case NotificationChanged(:final receipt):
      print('${receipt.id}: ${receipt.requestStatus} ${receipt.execution?.phase}');
    case NotificationClicked(:final destination, :final url):
      print('Tapped $destination → $url');
    default:
      break;
  }
});
```

The hierarchy is sealed, so an exhaustive `switch` tells you at compile time when a
new event appears. Follow a notification's lifecycle with `NotificationChanged`; the SDK
no longer emits `LocationUpdated`, `NotificationScheduled`, `NotificationShown`,
`NotificationSkipped`, `NotificationBlocked` or `NotificationCancelled` for new
notifications.

| Event | Carries |
|---|---|
| `NotificationChanged` | `receipt` |
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

If another library owns `UNUserNotificationCenter.delegate`, find which delegate
receives taps and foreground notifications, then check whether it already forwards
them to Stay22. The delegate check in `Stay22.diagnostics.run()` reports ownership,
not whether callbacks were forwarded. Forward each callback through one path only;
otherwise a tap can open the booking page and record the click twice.

Use the following overrides only when your `AppDelegate` receives both callbacks
and no other delegate forwards them through Stay22. If another delegate receives
them, integrate there instead; if it already forwards through Stay22, do not add
another path.

```swift
import stay22_flutter
import UserNotifications

override func userNotificationCenter(
  _ center: UNUserNotificationCenter,
  didReceive response: UNNotificationResponse,
  withCompletionHandler completionHandler: @escaping () -> Void
) {
  if !Stay22FlutterPlugin.ownsNotificationDelegate,
     Stay22FlutterPlugin.handleNotificationResponse(response) {
    completionHandler()
    return
  }
  super.userNotificationCenter(center, didReceive: response,
                               withCompletionHandler: completionHandler)
}

override func userNotificationCenter(
  _ center: UNUserNotificationCenter,
  willPresent notification: UNNotification,
  withCompletionHandler completionHandler:
    @escaping (UNNotificationPresentationOptions) -> Void
) {
  if !Stay22FlutterPlugin.ownsNotificationDelegate,
     Stay22FlutterPlugin.isStay22Notification(notification) {
    let shouldPresent = Stay22FlutterPlugin.handleWillPresentNotification(notification)
    completionHandler(shouldPresent ? [.banner, .sound, .list] : [])
    return
  }
  super.userNotificationCenter(center, willPresent: notification,
                               withCompletionHandler: completionHandler)
}
```

Keep `.list` so an offer remains in Notification Centre after its banner disappears.

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
final result = await Stay22.scheduleDiagnosticNotification(
  TravelContext(address: 'Paris, France'),
);
```

This is a per-call diagnostic. Use test controls only in internal builds.

## Example App

`example/` is a runnable integration covering travel context, notification
configuration, events, diagnostics and the iOS delegate forwarding above. It is also
what compiles the plugin's Kotlin and Swift in CI.

## Privacy

The SDK never asks for device GPS permission.
Notifications are gated on `Stay22.setEnabled` and should be treated as promotional.

## API Summary

| Call | Returns |
|---|---|
| `Stay22.isSupportedPlatform` | `bool` |
| `Stay22.initialize(aid:)` | `Future<void>` |
| `Stay22.isInitialized()` | `Future<bool>` |
| `Stay22.setEnabled(bool)` / `isEnabled()` | `Future<void>` / `Future<bool>` |
| `Stay22.setCampaignId(String?)` | `Future<void>` |
| `Stay22.hasNotificationPermission()` | `Future<bool>` |
| `Stay22.requestNotificationPermission()` | `Future<bool>` |
| `Stay22.ensureNotification(request)` | `Future<NotificationResult>` |
| `Stay22.updateNotification(...)` | `Future<NotificationResult>` |
| `Stay22.replaceNotification(...)` | `Future<NotificationResult>` |
| `Stay22.cancelNotification(reference)` | `Future<NotificationResult>` |
| `Stay22.getNotificationState()` | `Future<NotificationQuery>` |
| `Stay22.scheduleDiagnosticNotification(trip)` | `Future<NotificationResult>` |
| `Stay22.clearTravelContext()` (deprecated) | `Future<void>` |
| `Stay22.setNotificationConfig(NotificationConfig)` | `Future<void>` |
| `Stay22.ownsNotificationDelegate()` | `Future<bool>` |
| `Stay22.events` | `Stream<Stay22Event>` |
| `Stay22.testing.setShowLogs` / `setBaseUrl` | `Future<void>` |
| `Stay22.diagnostics.run()` / `logReport()` | `Future<Stay22Diagnostics>` |

Notification rejections and conflicts are returned in `NotificationResult`; inspect its
`outcome` and `reason`. Platform channel failures can throw `PlatformException`, and some
Dart input validation can throw `ArgumentError` or `RangeError` before a call reaches the
platform.

## Support

See https://dev.stay22.com/docs/mobile-sdk, or email support@stay22.com.
