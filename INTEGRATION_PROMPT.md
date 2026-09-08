# Stay22 Flutter SDK - Integration Prompt

Use this prompt when integrating the Stay22 Flutter SDK into a Flutter app. The
package wraps the prebuilt native SDKs: the iOS `Stay22SDK.xcframework` ships inside
the package, and the Android library is resolved from Stay22's Maven repository.

Provide the integrator with:

- the package URL `https://github.com/Stay22/stay22-flutter-sdk` and the release tag
  to pin
- this prompt
- the Stay22 partner ID (`aid`)

## Prompt

````text
Integrate the Stay22 Flutter SDK into this Flutter app.

Context:
- Package: https://github.com/Stay22/stay22-flutter-sdk (git dependency, not pub.dev)
- Minimum Flutter: 3.19; Android API 26+; iOS 15.0+
- Partner ID: <AID>

Tasks:

1. Confirm this is a Flutter app.
   Look for a `pubspec.yaml` with a `flutter:` section, a `lib/main.dart`, and
   `android/` and `ios/` directories.

2. Add the dependency, pinned to a release tag.

   In `pubspec.yaml`:

   ```yaml
   dependencies:
     stay22_flutter:
       git:
         url: https://github.com/Stay22/stay22-flutter-sdk.git
         ref: "<VERSION>"
   ```

   Then run `flutter pub get`.

   This package is not published on pub.dev. Do not add a version-constraint
   dependency such as `stay22_flutter: ^<VERSION>`; it will not resolve.

3. Add Stay22's Maven repository for Android.
   Without it the Android build fails with `Could not find com.stay22:sdk`.

   In `android/build.gradle.kts` (or `android/build.gradle` for Groovy):

   ```kotlin
   allprojects {
       repositories {
           google()
           mavenCentral()
           maven { url = uri("https://raw.githubusercontent.com/Stay22/stay22-android-sdk/main/maven") }
       }
   }
   ```

   Nothing is needed for iOS: the framework ships inside the package and CocoaPods
   embeds it.

4. Add the required iOS `Info.plist` keys.
   In `ios/Runner/Info.plist`, so the SDK can route an offer to a booking app the
   user already has installed:

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

   If this key already exists, merge the values into the existing array.

5. Initialize the SDK once, early in app launch.

   ```dart
   import 'package:stay22_flutter/stay22_flutter.dart';

   await Stay22.setEnabled(userHasOptedInToStay22Offers);
   await Stay22.initialize(aid: '<AID>');
   ```

   Every method returns a `Future` and reports failure as a `PlatformException`.
   Calls that require an initialized SDK throw `Stay22ErrorCode.notInitialized`
   if made before `initialize` completes.

   For cold-start notification taps on iOS, prefer declaring the partner ID in
   `ios/Runner/Info.plist` as `Stay22PartnerAID` (and, on Android, as a
   `com.stay22.sdk.PartnerAID` `meta-data` entry in `AndroidManifest.xml`), which
   initializes the SDK during app launch rather than after Dart starts.

6. Guard calls on unsupported platforms.
   The plugin supports Android and iOS only. Importing it on web or desktop is
   safe; calling into it throws `Stay22ErrorCode.unsupportedPlatform`.

   ```dart
   if (Stay22.isSupportedPlatform) {
     await Stay22.initialize(aid: '<AID>');
   }
   ```

7. Add consent and notification permission handling.
   Treat Stay22 notifications as promotional. Do not make them required for the app
   to function.

   When enabling Stay22:
   - consider surfacing opt-in language before enabling Stay22;
   - store the user's choice;
   - provide an in-app opt-out control.

   Wire opt-in and opt-out to:

   ```dart
   await Stay22.setEnabled(userHasOptedInToStay22Offers);
   ```

   `setEnabled` is persisted and may be called before `initialize`, so it works as
   a consent gate. When the user opts in, request permission at a sensible moment:

   ```dart
   final granted = await Stay22.requestNotificationPermission();
   ```

   To check permission without prompting:

   ```dart
   final canNotify = await Stay22.hasNotificationPermission();
   ```

8. Capture explicit travel intent.
   Search the app for screens, view models, routes, blocs/providers, and analytics
   events where the app knows a destination, city, venue, hotel/accommodation search
   term, coordinates, booking, itinerary, event, search result, map place, or travel
   date.

   Add `Stay22.setTravelContext(...)` where the app first has reliable intent:

   ```dart
   await Stay22.setTravelContext(
     TravelContext(
       address: 'Paris, France',
       checkinDate: '2026-03-20',
       checkoutDate: '2026-03-25',
     ),
   );
   ```

   Address-only and coordinates-only are also valid:

   ```dart
   await Stay22.setTravelContext(TravelContext(address: 'Paris, France'));
   await Stay22.setTravelContext(TravelContext(latitude: 48.8566, longitude: 2.3522));
   ```

   Use `hotelName` when the app has hotel or accommodation search text. It does not
   need to be an exact canonical hotel match:

   ```dart
   await Stay22.setTravelContext(
     TravelContext(address: 'Paris, France', hotelName: 'Hotel Example'),
   );
   ```

   Date format: `YYYY-MM-DD`. `MM/DD/YYYY` is also accepted and normalized.

   Important:
   - Notifications are scheduled from explicit travel intent only: address,
     coordinates, or hotel/accommodation search text.
   - `setTravelContext` merges non-empty fields, so destination and dates can be
     provided across multiple screens.
   - Invalid input throws `ArgumentError` before touching the platform channel.
   - Call `Stay22.clearTravelContext()` when a travel/search flow resets, the user
     signs out, or consent is revoked.

9. Optional: customize notification copy.
   Most integrations can use the default copy. If custom copy is needed:

   ```dart
   await Stay22.setNotificationConfig(
     NotificationConfig(
       title: 'Hotels in {destination}',
       message: 'Find stays for {checkin}-{checkout}.',
     ),
   );
   ```

   Supported placeholders: `{destination}`, `{checkin}`, `{checkout}`.

10. Optional: add attribution.

   ```dart
   await Stay22.setCampaignId('flutter-pilot-2026'); // optional
   ```

11. Optional: observe SDK events for QA.

   ```dart
   final subscription = Stay22.events.listen((event) {
     switch (event) {
       case NotificationScheduled(:final destination, :final delay):
         debugPrint('Stay22 scheduled: $destination, delay=$delay');
       case NotificationClicked(:final destination, :final url):
         debugPrint('Stay22 clicked: $destination, $url');
       default:
         break;
     }
   });
   ```

   `Stay22Event` is a sealed class, so a `switch` over it is exhaustive; keep a
   `default` branch so a new event type in a later release does not break the
   build. `delay` is a `Duration`. Event types: `LocationUpdated`,
   `NotificationScheduled`, `NotificationShown`, `NotificationClicked`,
   `NotificationBlocked`, `NotificationSkipped`, `NotificationCancelled`,
   `EnabledChanged`, `TravelContextCleared`.

   A broadcast stream, safe to listen to more than once. Cancel the subscription
   when the listening widget is disposed.

12. Prefer automatic scheduling.
   Automatic scheduling normally runs when fresh travel context exists and the app
   backgrounds. Use this default behavior whenever possible.

   Only use `Stay22.advanced.scheduleNotification()` for special app flows where
   background-based scheduling does not fit, and call it only after confirming the
   timing need with Stay22.

13. If the app owns the iOS notification delegate.
   Most apps need nothing here; the SDK claims the delegate and chains to whatever
   was already set. If the app assigns `UNUserNotificationCenter.delegate` itself,
   forward both callbacks from `AppDelegate.swift`, and present with at least
   `[.banner, .sound, .list]` — omitting `.list` makes the notification vanish with
   its banner:

   ```swift
   import stay22_flutter

   override func userNotificationCenter(
       _ center: UNUserNotificationCenter,
       willPresent notification: UNNotification,
       withCompletionHandler completionHandler:
           @escaping (UNNotificationPresentationOptions) -> Void
   ) {
       if !Stay22FlutterPlugin.ownsNotificationDelegate,
          Stay22FlutterPlugin.handleWillPresentNotification(notification) {
           completionHandler([.banner, .sound, .list])
           return
       }
       super.userNotificationCenter(
           center, willPresent: notification, withCompletionHandler: completionHandler
       )
   }
   ```

14. Development testing only:

   ```dart
   await Stay22.testing.setForce(true);
   await Stay22.testing.setShowLogs(true);
   ```

   Force mode uses a short local notification delay for repeatable QA. Never ship
   production builds with force mode enabled.

   To check an integration end to end:

   ```dart
   final report = await Stay22.diagnostics.logReport();
   if (!report.isHealthy) {
     for (final check in report.failures) {
       debugPrint('Stay22 check failed: ${check.name} — ${check.detail}');
     }
   }
   ```

Public API to use:
- `Stay22.isSupportedPlatform`
- `Stay22.initialize(aid:)`
- `Stay22.isInitialized()`
- `Stay22.setEnabled(bool)` / `Stay22.isEnabled()`
- `Stay22.requestNotificationPermission()`
- `Stay22.hasNotificationPermission()`
- `Stay22.setTravelContext(TravelContext)`
- `Stay22.clearTravelContext()`
- `Stay22.setNotificationConfig(NotificationConfig)`
- `Stay22.setMedium(String)` / `Stay22.setCampaignId(String?)`
- `Stay22.ownsNotificationDelegate()`
- `Stay22.events`
- `Stay22.advanced.scheduleNotification()` only for special scheduling flows after
  discussing with Stay22
- `Stay22.diagnostics.run()` / `Stay22.diagnostics.logReport()`
- `Stay22.testing.setForce(bool)` / `Stay22.testing.setShowLogs(bool)`
- `TravelContext(address:latitude:longitude:checkinDate:checkoutDate:hotelName:adults:children:)`
- `NotificationConfig(title:subtitle:message:...)`
- `Stay22ErrorCode` for the codes a `PlatformException` carries

Use only the APIs listed above. Every call is asynchronous — do not write
`Stay22.initialize('<AID>')`, `Stay22.isEnabled = true`, `Stay22.setLocation(...)`,
`Stay22.testing.force = true`, or any other synchronous or property-style form; they
do not exist in the Dart API.
````
