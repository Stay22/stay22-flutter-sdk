import 'validation.dart';

/// How prominently the system should deliver an SDK notification.
///
/// iOS's `critical` level is deliberately absent: it needs a special Apple
/// entitlement and is not appropriate for promotional notifications.
enum NotificationInterruptionLevel {
  passive,
  active,
  timeSensitive;

  /// The wire value. Matches the native enum names on both platforms exactly,
  /// so nothing case-converts anywhere along the chain.
  String get wireName => name;
}

/// A local image shown with the notification where the platform supports it.
///
/// The file must be local. For a remote image, download it first and pass the
/// resulting path.
class NotificationAttachment {
  final String? identifier;

  /// A `file://` URL or a plain filesystem path. Both are accepted.
  final String fileUrl;

  NotificationAttachment({
    String? identifier,
    required String fileUrl,
  })  : identifier =
            requireOptionalNonBlank(identifier, 'attachment.identifier'),
        fileUrl = requireNonBlank(fileUrl, 'attachment.fileUrl');

  Map<String, Object?> toMap() => <String, Object?>{
        if (identifier != null) 'identifier': identifier,
        'fileURL': fileUrl,
      };
}

/// A button the system draws on the notification.
///
/// Stay22 treats a tap on any configured action exactly like a tap on the
/// notification body: it opens the generated booking URL and emits the usual
/// click event.
class NotificationAction {
  final String identifier;
  final String title;
  final bool foreground;
  final bool authenticationRequired;
  final bool destructive;

  NotificationAction({
    required String identifier,
    required String title,
    this.foreground = true,
    this.authenticationRequired = false,
    this.destructive = false,
  })  : identifier = requireNonBlank(identifier, 'action.identifier'),
        title = requireNonBlank(title, 'action.title');

  Map<String, Object?> toMap() => <String, Object?>{
        'identifier': identifier,
        'title': title,
        'foreground': foreground,
        'authenticationRequired': authenticationRequired,
        'destructive': destructive,
      };
}

/// Appearance of the notification the SDK schedules.
///
/// Text fields support the `{destination}`, `{checkin}` and `{checkout}`
/// placeholders, which the SDK fills from the current travel context when the
/// notification is scheduled. `{checkin}` and `{checkout}` resolve to empty
/// when no dates are set.
///
/// Setting a config replaces it entirely — an omitted field falls back to the
/// SDK default, it does not retain what a previous call set.
class NotificationConfig {
  /// Native default: `"Hotels in {destination}"`.
  final String? title;

  final String? subtitle;

  /// Native default: `"Tap to find the best deals nearby"`.
  final String? message;

  /// Native default: `"stay22_destinations"`.
  final String? categoryId;

  /// Native default: `"stay22"`.
  final String? threadId;

  final int? badge;
  final String? launchImageName;
  final String? targetContentIdentifier;
  final NotificationInterruptionLevel? interruptionLevel;

  /// 0.0 to 1.0.
  final double? relevanceScore;

  final List<NotificationAttachment> attachments;
  final List<NotificationAction> actions;

  NotificationConfig({
    String? title,
    String? subtitle,
    String? message,
    String? categoryId,
    String? threadId,
    int? badge,
    String? launchImageName,
    String? targetContentIdentifier,
    this.interruptionLevel,
    double? relevanceScore,
    this.attachments = const <NotificationAttachment>[],
    this.actions = const <NotificationAction>[],
  })  : title = normalizeOptional(title, 'title'),
        subtitle = normalizeOptional(subtitle, 'subtitle'),
        message = normalizeOptional(message, 'message'),
        // Unlike the free text above, a blank identifier is an error rather
        // than "use the default" — an empty categoryId silently breaks action
        // button registration, which is very hard to notice later.
        categoryId = requireOptionalNonBlank(categoryId, 'categoryId'),
        threadId = requireOptionalNonBlank(threadId, 'threadId'),
        badge = normalizeNonNegativeInt(badge, 'badge'),
        launchImageName = normalizeOptional(launchImageName, 'launchImageName'),
        targetContentIdentifier = normalizeOptional(
            targetContentIdentifier, 'targetContentIdentifier'),
        relevanceScore = normalizeRelevanceScore(relevanceScore);

  Map<String, Object?> toMap() => <String, Object?>{
        if (title != null) 'title': title,
        if (subtitle != null) 'subtitle': subtitle,
        if (message != null) 'message': message,
        if (categoryId != null) 'categoryId': categoryId,
        if (threadId != null) 'threadId': threadId,
        if (badge != null) 'badge': badge,
        if (launchImageName != null) 'launchImageName': launchImageName,
        if (targetContentIdentifier != null)
          'targetContentIdentifier': targetContentIdentifier,
        if (interruptionLevel != null)
          'interruptionLevel': interruptionLevel!.wireName,
        if (relevanceScore != null) 'relevanceScore': relevanceScore,
        if (attachments.isNotEmpty)
          'attachments': attachments.map((a) => a.toMap()).toList(),
        if (actions.isNotEmpty)
          'actions': actions.map((a) => a.toMap()).toList(),
      };
}
