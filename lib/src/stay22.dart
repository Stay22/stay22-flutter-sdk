import 'dart:async';

import 'channel.dart';
import 'diagnostics.dart';
import 'notification_config.dart';
import 'stay22_event.dart';
import 'travel_context.dart';
import 'validation.dart';

/// The Stay22 SDK.
///
/// The host app hands over explicit travel intent — where the user is going and
/// when — and the SDK decides whether to schedule a single local notification
/// offering accommodation there, opening a Stay22 booking page when it is
/// tapped.
///
/// Every call returns a `Future` and completes with a [PlatformException] on
/// failure, so a mistake in wiring surfaces at the call site rather than in a
/// native log nobody reads.
///
/// ```dart
/// await Stay22.initialize(aid: 'your-partner-id');
/// await Stay22.setEnabled(userHasOptedIn);
/// await Stay22.requestNotificationPermission();
/// await Stay22.setTravelContext(TravelContext(
///   address: 'Paris, France',
///   checkinDate: '2026-03-20',
///   checkoutDate: '2026-03-25',
/// ));
/// ```
abstract final class Stay22 {
  /// Whether the plugin runs on the current platform (Android and iOS only).
  ///
  /// Importing the package anywhere is safe; calling into it is not. Guard
  /// shared code with this rather than checking the host OS directly.
  static bool get isSupportedPlatform => Stay22Channel.isSupported;

  /// Initializes the SDK with your partner ID.
  ///
  /// Prefer declaring the ID natively instead — `Stay22PartnerAID` in
  /// `Info.plist` and a `com.stay22.sdk.PartnerAID` `<meta-data>` entry in
  /// `AndroidManifest.xml`. Native declaration initializes during app launch,
  /// before Dart runs, which is the only way a notification tapped on a cold
  /// start reliably opens its booking page on iOS. Use this call when the
  /// partner ID is only known at runtime.
  ///
  /// Calling it when the SDK is already initialized is a no-op.
  ///
  /// Partner configuration still loads asynchronously after this completes, so
  /// completion means "the SDK is running", not "the SDK is ready to schedule".
  static Future<void> initialize({required String aid}) async {
    await Stay22Channel.invoke<void>('initialize', {
      'aid': requireNonBlank(aid, 'aid'),
    });
  }

  /// Whether native initialization has happened.
  ///
  /// Not a readiness signal for partner configuration.
  static Future<bool> isInitialized() =>
      Stay22Channel.invokeBool('isInitialized');

  /// Enables or disables the SDK.
  ///
  /// While disabled, nothing is scheduled and any pending notification is
  /// cleared. The value is persisted across launches, so a user's opt-out is
  /// remembered, and it can be set before [initialize] — which is what makes it
  /// usable as the consent gate. Defaults to enabled.
  static Future<void> setEnabled(bool enabled) async {
    await Stay22Channel.invoke<void>('setEnabled', {'enabled': enabled});
  }

  static Future<bool> isEnabled() => Stay22Channel.invokeBool('isEnabled');

  /// Attribution `medium` written onto the booking link the notification opens.
  ///
  /// This is how the resulting booking gets credited. Defaults to `pushnotif`.
  static Future<void> setMedium(String medium) async {
    await Stay22Channel.invoke<void>('setMedium', {
      'medium': requireNonBlank(medium, 'medium'),
    });
  }

  /// Optional attribution `campaign` on the booking link. Pass null to clear.
  static Future<void> setCampaignId(String? campaignId) async {
    await Stay22Channel.invoke<void>('setCampaignId', {
      'campaignId': requireOptionalNonBlank(campaignId, 'campaignId'),
    });
  }

  /// Whether the app may currently post notifications.
  static Future<bool> hasNotificationPermission() =>
      Stay22Channel.invokeBool('hasNotificationPermission');

  /// Shows the system permission prompt and reports what the user chose.
  ///
  /// Completes with the real answer on both platforms, not the state before the
  /// prompt appeared. Resolves immediately with the current state when no
  /// prompt can be shown — Android 12 and below, an already-denied permission,
  /// or a notification channel the user turned off, which only system settings
  /// can undo.
  static Future<bool> requestNotificationPermission() =>
      Stay22Channel.invokeBool('requestNotificationPermission');

  /// Hands the SDK the user's travel intent.
  ///
  /// This replaces any previous context outright. Automatic scheduling is
  /// evaluated when the app next goes to the background.
  static Future<void> setTravelContext(TravelContext context) async {
    await Stay22Channel.invoke<void>('setTravelContext', context.toMap());
  }

  /// Clears the travel context and any pending notification.
  static Future<void> clearTravelContext() async {
    await Stay22Channel.invoke<void>('clearTravelContext');
  }

  /// Sets how the scheduled notification looks.
  ///
  /// Replaces the whole configuration; an omitted field reverts to the SDK
  /// default rather than keeping what a previous call set. Changes affect
  /// future schedules only — a notification already pending keeps its text.
  static Future<void> setNotificationConfig(NotificationConfig config) async {
    await Stay22Channel.invoke<void>('setNotificationConfig', config.toMap());
  }

  /// Whether the SDK currently owns `UNUserNotificationCenter.delegate`.
  ///
  /// Always true on Android, which has no shared delegate. On iOS, false means
  /// taps are reaching something else — commonly `firebase_messaging` or
  /// `flutter_local_notifications` — and Stay22 notifications will open nothing
  /// unless that delegate forwards to Stay22. See the README's notification
  /// delegate section for the forwarding snippet.
  static Future<bool> ownsNotificationDelegate() =>
      Stay22Channel.invokeBool('ownsNotificationDelegate');

  /// SDK events. See [Stay22Event].
  ///
  /// A broadcast stream, safe to listen to more than once and safe to listen to
  /// late: the plugin holds the native listener for the whole life of the engine
  /// and buffers anything that arrives before the first subscriber, so events
  /// raised while the app was not running — a notification shown by the delayed
  /// worker in a dead process, for instance — are replayed rather than dropped.
  ///
  /// The SDK has a single native listener slot and this plugin owns it. An app
  /// that also calls `Stay22.advanced.setEventListener` natively will find one
  /// of the two listeners silently replaced; use this stream instead.
  // No trailing .asBroadcastStream(): Stay22Channel.events() is already
  // broadcast and .map() preserves that, so wrapping it again would repeat
  // the same defect just fixed in channel.dart one layer down -- the native
  // side's onCancel would never fire because this stream's own listener
  // count would never reach zero.
  static Stream<Stay22Event> get events => _events ??= Stay22Channel.events()
      .map((event) => Stay22Event.fromMap(event as Map<Object?, Object?>));

  static Stream<Stay22Event>? _events;

  /// Low-level hooks. Most apps need nothing here.
  static const Stay22Advanced advanced = Stay22Advanced._();

  /// Testing overrides. Never ship an app with these switched on.
  static const Stay22Testing testing = Stay22Testing._();

  /// Integration self-check.
  static const Stay22DiagnosticsApi diagnostics = Stay22DiagnosticsApi._();
}

/// Low-level hooks for advanced integrations.
class Stay22Advanced {
  const Stay22Advanced._();

  /// Runs the scheduling pipeline now instead of waiting for the app to be
  /// backgrounded.
  ///
  /// Only the background trigger is bypassed. Home-city suppression, the local
  /// cooldown, the server decision and the partner kill switch all still apply.
  ///
  /// Set [force] to skip the local gates and the server's per-device cooldown
  /// for this one call and shorten the delay to a few seconds, so the pipeline
  /// can be verified by hand. It writes no cooldown and no server lock, so it
  /// stays repeatable, and it never bypasses the partner kill switch. For
  /// integration testing only.
  Future<void> scheduleNotification({bool force = false}) async {
    await Stay22Channel.invoke<void>('scheduleNotification', {'force': force});
  }

  Future<void> clearTravelContext() async {
    await Stay22Channel.invoke<void>('clearTravelContext');
  }
}

/// Testing-only overrides for local and staging validation.
class Stay22Testing {
  const Stay22Testing._();

  /// Force mode: a few seconds' delay, local gates skipped, repeatable.
  Future<void> setForce(bool enabled) async {
    await Stay22Channel.invoke<void>('setForce', {'enabled': enabled});
  }

  /// Writes SDK activity to the platform log.
  Future<void> setShowLogs(bool enabled) async {
    await Stay22Channel.invoke<void>('setShowLogs', {'enabled': enabled});
  }

  /// Points the SDK at a non-production backend.
  Future<void> setBaseUrl(String url) async {
    await Stay22Channel.invoke<void>('setBaseURL', {
      'url': requireNonBlank(url, 'url'),
    });
  }
}

/// Integration self-check.
class Stay22DiagnosticsApi {
  const Stay22DiagnosticsApi._();

  /// Runs every check and returns a snapshot.
  ///
  /// Safe at any time, including before [Stay22.initialize]. Side-effect free.
  Future<Stay22Diagnostics> run() async {
    return Stay22Diagnostics.fromMap(
        await Stay22Channel.invokeMap('runDiagnostics'));
  }

  /// Runs the checks and writes the report to the platform log, regardless of
  /// [Stay22Testing.setShowLogs].
  Future<Stay22Diagnostics> logReport() async {
    return Stay22Diagnostics.fromMap(
      await Stay22Channel.invokeMap('logDiagnosticsReport'),
    );
  }
}
