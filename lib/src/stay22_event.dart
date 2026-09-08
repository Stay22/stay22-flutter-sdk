/// Events the SDK emits.
///
/// Delivered on the platform thread by both native SDKs, so a listener runs on
/// the Dart main isolate without any hop of its own.
///
/// Match on these with a `switch` — the hierarchy is sealed, so the analyzer
/// will tell you when a new case appears rather than letting it fall through
/// silently.
sealed class Stay22Event {
  const Stay22Event();

  /// Decodes one event from the native payload.
  ///
  /// Throws [FormatException] on an unrecognized type, which in practice means
  /// the Dart package and the vendored native SDK are different versions.
  factory Stay22Event.fromMap(Map<Object?, Object?> map) {
    final type = map['type'] as String?;
    String str(String key) => map[key] as String? ?? '';

    return switch (type) {
      'locationUpdated' => LocationUpdated(destination: str('destination')),
      'notificationScheduled' => NotificationScheduled(
          destination: str('destination'),
          // Native sends seconds as a double. Carrying it as a Duration is
          // what stops the unit drifting again — an earlier version of this
          // package called the same field delayMs and was wrong by 1000x.
          delay: _durationFromSeconds(map['delay']),
        ),
      'notificationShown' => NotificationShown(destination: str('destination')),
      'notificationClicked' => NotificationClicked(
          destination: str('destination'),
          url: str('url'),
        ),
      'notificationBlocked' => NotificationBlocked(reason: str('reason')),
      'notificationSkipped' => NotificationSkipped(reason: str('reason')),
      'notificationCancelled' => NotificationCancelled(reason: str('reason')),
      'enabledChanged' =>
        EnabledChanged(isEnabled: map['isEnabled'] as bool? ?? false),
      'travelContextCleared' => const TravelContextCleared(),
      _ => throw FormatException('Unknown Stay22 event type: $type'),
    };
  }

  static Duration _durationFromSeconds(Object? seconds) {
    final value = (seconds as num?)?.toDouble() ?? 0;
    return Duration(
        microseconds: (value * Duration.microsecondsPerSecond).round());
  }
}

/// Explicit travel context changed.
final class LocationUpdated extends Stay22Event {
  final String destination;
  const LocationUpdated({required this.destination});
}

/// A notification was scheduled. [delay] is how long until it fires.
final class NotificationScheduled extends Stay22Event {
  final String destination;
  final Duration delay;
  const NotificationScheduled({required this.destination, required this.delay});
}

/// Delivery of a notification was observed.
final class NotificationShown extends Stay22Event {
  final String destination;
  const NotificationShown({required this.destination});
}

/// The user tapped a Stay22 notification. [url] is the booking link opened.
final class NotificationClicked extends Stay22Event {
  final String destination;
  final String url;
  const NotificationClicked({required this.destination, required this.url});
}

/// A notification could not be shown, e.g. permission was denied.
final class NotificationBlocked extends Stay22Event {
  final String reason;
  const NotificationBlocked({required this.reason});
}

/// Scheduling was skipped, e.g. the destination matched the user's home city.
final class NotificationSkipped extends Stay22Event {
  final String reason;
  const NotificationSkipped({required this.reason});
}

/// A pending notification was cancelled or cleared.
final class NotificationCancelled extends Stay22Event {
  final String reason;
  const NotificationCancelled({required this.reason});
}

/// The SDK was enabled or disabled.
final class EnabledChanged extends Stay22Event {
  final bool isEnabled;
  const EnabledChanged({required this.isEnabled});
}

/// Explicit travel context was cleared.
final class TravelContextCleared extends Stay22Event {
  const TravelContextCleared();
}
