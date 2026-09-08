# Changelog

All notable changes to the Stay22 Flutter SDK are documented here.
This project adheres to [Semantic Versioning](https://semver.org).

## [Unreleased]

## [1.2.0] - 2026-09-08
### Changed
- The package now ships from its own repository,
  [stay22-flutter-sdk](https://github.com/Stay22/stay22-flutter-sdk), as a git dependency
  pinned to a release tag. Update your `pubspec.yaml` to the form shown in the README.
- Both platforms now use the published native SDK 1.2.0. Earlier versions of this package
  could bundle an iOS build that differed from the released iOS SDK of the same version
  number, so the two platforms did not always behave the same.
- The bundled iOS privacy manifest now declares **Device ID**. Re-check the App Privacy
  answers on your App Store listing: you inherit this manifest into your own disclosure.

### Fixed
- Calls that require an initialized SDK — `setTravelContext`, `clearTravelContext`,
  `scheduleNotification`, `hasNotificationPermission`, `requestNotificationPermission` —
  now throw a `PlatformException` with code `not_initialized` instead of reporting
  success while doing nothing. Both platforms behave identically. Settings you are meant
  to apply before `initialize`, including the `setEnabled` consent gate, are unaffected.
- Cancelling the last `Stay22.events` subscription now releases the underlying native
  listener instead of leaving it attached for the life of the app.
- Offers now reach users who run a system-wide content or ad blocker on both platforms.

### Documentation
- The notification-forwarding example and README now present
  `[.banner, .sound, .list]`, so a foreground notification stays in Notification Centre.
  Copy the updated snippet if your app owns the iOS notification delegate.

## [1.1.0] - 2026-09-02
### Changed
- Complete rewrite. The previous package called native APIs that no longer
  exist and could not compile against any shipping SDK; nothing from it is
  carried forward. The version now tracks the native SDKs, so the Flutter,
  Android and iOS packages share a version number.
- `Stay22.init(aid)` is now `Stay22.initialize(aid: ...)`, matching both native
  SDKs.
- Every method returns a `Future` and reports failures as a `PlatformException`
  with the same error codes on both platforms. Setter errors used to be
  unobservable from Dart.
- `TravelContext` now carries `address`, `latitude`, `longitude`, `checkinDate`,
  `checkoutDate`, `hotelName`, `adults` and `children`, replacing the old
  `destination` / `signalSource` shape.
- `NotificationConfig` now carries `subtitle`, `badge`, `launchImageName`,
  `targetContentIdentifier`, `interruptionLevel`, `relevanceScore`,
  `attachments` and `actions`, replacing the old Android-only channel fields.
- Events are a sealed class hierarchy, so a `switch` over them is checked for
  exhaustiveness.

### Added
- `Stay22.setEnabled` / `isEnabled` — the persisted consent gate, which the
  package previously had no way to reach.
- `Stay22.setMedium` / `setCampaignId` — attribution on the booking link.
- `Stay22.diagnostics.run()` and `logReport()` — the integration self-check.
- `Stay22.ownsNotificationDelegate`, plus Swift forwarding hooks for apps that
  own `UNUserNotificationCenter.delegate` themselves. This matters on iOS for
  any app that also uses `firebase_messaging` or `flutter_local_notifications`.
- The partner ID can be declared in `Info.plist` (`Stay22PartnerAID`) or
  `AndroidManifest.xml` (`com.stay22.sdk.PartnerAID`), which initializes the SDK
  during app launch. On iOS this is what lets a notification tapped from a cold
  start open its booking page at all; initializing from Dart happens after iOS
  has already delivered the tap.
- The iOS framework is bundled in the package, so iOS needs no CocoaPod or Swift
  Package. Android fetches `com.stay22:sdk` from Stay22's Maven repository, which
  a consuming app declares once in `android/build.gradle.kts` — see the README.
  Bundling it the way iOS does is not possible: Flutter's Gradle tooling ignores
  a repository declared by a plugin, and AGP rejects a plugin bundling an `.aar`.
- A runnable example app under `example/`.

### Fixed
- `notificationScheduled` reported its delay as `delayMs` while the SDK sends
  seconds — a 1000x error. It is now a `Duration`.
- `requestNotificationPermission` was never bridged on Android at all. It now
  uses the callback-based native API, so it resolves with the user's real answer
  on both platforms rather than the state from before the prompt appeared.
- Events raised while the app was not running are no longer lost. The SDK
  replays them once and consumes the queue as it does so, which happened before
  Dart could subscribe; the plugin now holds the native listener for the life of
  the engine and buffers.
- `Stay22.events` returned a fresh stream on every access, so a second listener
  silently broke the first.
- An attachment path without a URL scheme is resolved as a file path instead of
  becoming an unusable relative URI.

### Documentation
- README restructured to match the Android and iOS SDK READMEs, and now covers
  the required `LSApplicationQueriesSchemes` entries, the consent gate, and the
  notification delegate.
