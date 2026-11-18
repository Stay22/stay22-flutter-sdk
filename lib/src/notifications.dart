import 'travel_context.dart';

/// Original one-shot timing intent. Native code captures an omitted relative anchor once.
final class NotificationTiming {
  final String type;
  final int? atMs;
  final int? delayMs;

  const NotificationTiming.accountDefault()
      : type = 'accountDefault',
        atMs = null,
        delayMs = null;
  const NotificationTiming.after({required int this.delayMs})
      : type = 'after',
        atMs = null;
  const NotificationTiming.notBefore({required int this.atMs})
      : type = 'notBefore',
        delayMs = null;
  const NotificationTiming.at({required int this.atMs})
      : type = 'at',
        delayMs = null;

  Map<String, Object?> toMap() => {
        'type': type,
        if (atMs != null) 'atMs': atMs,
        if (delayMs != null) 'delayMs': delayMs,
      };

  factory NotificationTiming.fromMap(Map<Object?, Object?> map) =>
      switch (_string(map, 'type')) {
        'accountDefault' => const NotificationTiming.accountDefault(),
        'after' => NotificationTiming.after(delayMs: _integer(map, 'delayMs')),
        'notBefore' =>
          NotificationTiming.notBefore(atMs: _integer(map, 'atMs')),
        'at' => NotificationTiming.at(atMs: _integer(map, 'atMs')),
        final value => throw FormatException('Unknown timing type: $value'),
      };
}

enum NotificationMode { normal, diagnostic }

enum NotificationWindowGuarantee {
  targetSelection,
  prePostCheck,
  visiblePresentation
}

enum NotificationOutcome {
  submitted,
  kept,
  replaced,
  cancelled,
  conflict,
  rejected
}

enum NotificationPreviousEffect {
  none,
  unchanged,
  revoked,
  cancellationRequested,
  uncertain
}

enum NotificationRequestStatus {
  preparing,
  awaitingAuthorization,
  applied,
  rejected,
  cancelled,
  expired
}

enum NotificationExecutionPhase {
  queueing,
  queued,
  posting,
  completed,
  revoking,
  revoked,
  blocked,
  expired
}

enum NotificationExpirySource {
  explicitDeadline,
  accountPolicy,
  diagnosticPolicy
}

enum NotificationEvidence {
  none,
  osAccepted,
  androidPosted,
  iosObserved,
  unknown
}

enum NotificationNativeKind { work, pendingNotification, deliveredNotification }

/// ISO weekdays are Monday=1 through Sunday=7; null means every day. End is exclusive.
final class NotificationLocalWindow {
  final List<int>? weekdays;
  final int startMinute;
  final int endMinute;

  NotificationLocalWindow(
      {List<int>? weekdays, required this.startMinute, required this.endMinute})
      : weekdays = weekdays == null ? null : List.unmodifiable(weekdays);

  Map<String, Object?> toMap() => {
        if (weekdays != null) 'weekdays': weekdays,
        'startMinute': startMinute,
        'endMinute': endMinute,
      };

  factory NotificationLocalWindow.fromMap(Map<Object?, Object?> map) =>
      NotificationLocalWindow(
        weekdays: map['weekdays'] == null
            ? null
            : _list(map, 'weekdays')
                .map((value) => _integerValue(value, 'weekdays'))
                .toList(),
        startMinute: _integer(map, 'startMinute'),
        endMinute: _integer(map, 'endMinute'),
      );
}

/// Named-zone restrictions. Empty periods permit no notification; a guarantee is required.
final class NotificationAllowedWindows {
  final String timeZone;
  final List<NotificationLocalWindow> periods;
  final NotificationWindowGuarantee requiredWindowGuarantee;

  NotificationAllowedWindows(
      {required this.timeZone,
      required List<NotificationLocalWindow> periods,
      required this.requiredWindowGuarantee})
      : periods = List.unmodifiable(periods);

  Map<String, Object?> toMap() => {
        'timeZone': timeZone,
        'periods': periods.map((period) => period.toMap()).toList(),
        'requiredWindowGuarantee': requiredWindowGuarantee.name,
      };

  factory NotificationAllowedWindows.fromMap(Map<Object?, Object?> map) =>
      NotificationAllowedWindows(
        timeZone: _string(map, 'timeZone'),
        periods: _list(map, 'periods')
            .map((value) => NotificationLocalWindow.fromMap(_object(value)))
            .toList(),
        requiredWindowGuarantee: _enum(
            map, 'requiredWindowGuarantee', NotificationWindowGuarantee.values),
      );
}

/// A complete immutable trip and timing intent; omitted fields never inherit an earlier trip.
final class NotificationRequest {
  final TravelContext trip;
  final NotificationTiming timing;
  final NotificationAllowedWindows? allowedWindows;
  final int? expiresAtMs;
  final int? actionExpiresAtMs;

  const NotificationRequest(
      {required this.trip,
      this.timing = const NotificationTiming.accountDefault(),
      this.allowedWindows,
      this.expiresAtMs,
      this.actionExpiresAtMs});

  Map<String, Object?> toMap() => {
        'trip': trip.toMap(),
        'timing': timing.toMap(),
        if (allowedWindows != null) 'allowedWindows': allowedWindows!.toMap(),
        if (expiresAtMs != null) 'expiresAtMs': expiresAtMs,
        if (actionExpiresAtMs != null) 'actionExpiresAtMs': actionExpiresAtMs,
      };
}

/// Persist these fields with original command arguments before a mutation.
/// Reconstruct them after restart; a newer queried revision must not rebase a retry.
final class NotificationReference {
  final String id;
  final int revision;
  final NotificationMode mode;
  const NotificationReference(
      {required this.id, required this.revision, required this.mode});

  Map<String, Object?> toMap() =>
      {'id': id, 'revision': revision, 'mode': mode.name};
  factory NotificationReference.fromMap(Map<Object?, Object?> map) =>
      NotificationReference(
        id: _string(map, 'id'),
        revision: _integer(map, 'revision'),
        mode: _enum(map, 'mode', NotificationMode.values),
      );
}

final class NotificationCapabilities {
  final List<NotificationWindowGuarantee> windowGuarantees;
  final int? supportedHorizonMs;
  NotificationCapabilities._(this.windowGuarantees, this.supportedHorizonMs);
  factory NotificationCapabilities.fromMap(Map<Object?, Object?> map) =>
      NotificationCapabilities._(
        List.unmodifiable(_list(map, 'windowGuarantees').map(
            (value) => _enumValue(value, NotificationWindowGuarantee.values))),
        _optionalInteger(map, 'supportedHorizonMs'),
      );
}

/// Requested timing and its original captured anchor and independent validity cutoffs.
final class NotificationRequestedTiming {
  final NotificationTiming timing;
  final int submittedAtMs;
  final int expiresAtMs;
  final int actionExpiresAtMs;
  final NotificationExpirySource executionExpirySource;
  final NotificationExpirySource actionExpirySource;
  final NotificationAllowedWindows? allowedWindows;
  const NotificationRequestedTiming._(
      this.timing,
      this.submittedAtMs,
      this.expiresAtMs,
      this.actionExpiresAtMs,
      this.executionExpirySource,
      this.actionExpirySource,
      this.allowedWindows);

  factory NotificationRequestedTiming.fromMap(Map<Object?, Object?> map) =>
      NotificationRequestedTiming._(
        NotificationTiming.fromMap(_object(map['timing'])),
        _integer(map, 'submittedAtMs'),
        _integer(map, 'expiresAtMs'),
        _integer(map, 'actionExpiresAtMs'),
        _enum(map, 'executionExpirySource', NotificationExpirySource.values),
        _enum(map, 'actionExpirySource', NotificationExpirySource.values),
        map['allowedWindows'] == null
            ? null
            : NotificationAllowedWindows.fromMap(
                _object(map['allowedWindows'])),
      );
}

final class NotificationAcceptedTiming {
  final int targetAtMs;
  final int intervalStartAtMs;
  final int intervalEndAtMs;
  final NotificationWindowGuarantee guarantee;
  const NotificationAcceptedTiming._(this.targetAtMs, this.intervalStartAtMs,
      this.intervalEndAtMs, this.guarantee);
  factory NotificationAcceptedTiming.fromMap(Map<Object?, Object?> map) =>
      NotificationAcceptedTiming._(
        _integer(map, 'targetAtMs'),
        _integer(map, 'intervalStartAtMs'),
        _integer(map, 'intervalEndAtMs'),
        _enum(map, 'guarantee', NotificationWindowGuarantee.values),
      );
}

/// One accepted execution; its revision may precede the receipt's latest control revision.
final class NotificationExecution {
  final int revision;
  final NotificationRequestedTiming requested;
  final NotificationAcceptedTiming acceptedTiming;
  final int actionExpiresAtMs;
  final NotificationExecutionPhase phase;
  final NotificationEvidence evidence;
  final int? observedAtMs;
  final NotificationCapabilities capabilities;
  final String? reason;
  const NotificationExecution._(
      this.revision,
      this.requested,
      this.acceptedTiming,
      this.actionExpiresAtMs,
      this.phase,
      this.evidence,
      this.observedAtMs,
      this.capabilities,
      this.reason);
  factory NotificationExecution.fromMap(Map<Object?, Object?> map) =>
      NotificationExecution._(
        _integer(map, 'revision'),
        NotificationRequestedTiming.fromMap(_object(map['requested'])),
        NotificationAcceptedTiming.fromMap(_object(map['acceptedTiming'])),
        _integer(map, 'actionExpiresAtMs'),
        _enum(map, 'phase', NotificationExecutionPhase.values),
        _enum(map, 'evidence', NotificationEvidence.values),
        _optionalInteger(map, 'observedAtMs'),
        NotificationCapabilities.fromMap(_object(map['capabilities'])),
        _optionalString(map, 'reason'),
      );
}

/// A snapshot of SDK facts. Submission acknowledges storage, not OS acceptance or visibility.
final class NotificationReceipt {
  final String id;
  final int revision;
  final NotificationMode mode;
  final NotificationRequestStatus requestStatus;
  final NotificationRequestedTiming? requested;
  final NotificationExecution? execution;
  final NotificationPreviousEffect previousEffect;
  final NotificationCapabilities capabilities;
  final String? reason;
  const NotificationReceipt._(
      this.id,
      this.revision,
      this.mode,
      this.requestStatus,
      this.requested,
      this.execution,
      this.previousEffect,
      this.capabilities,
      this.reason);

  NotificationReference get reference =>
      NotificationReference(id: id, revision: revision, mode: mode);
  factory NotificationReceipt.fromMap(Map<Object?, Object?> map) =>
      NotificationReceipt._(
        _string(map, 'id'),
        _integer(map, 'revision'),
        _enum(map, 'mode', NotificationMode.values),
        _enum(map, 'requestStatus', NotificationRequestStatus.values),
        _field(map, 'requested') == null
            ? null
            : NotificationRequestedTiming.fromMap(_object(map['requested'])),
        _field(map, 'execution') == null
            ? null
            : NotificationExecution.fromMap(_object(map['execution'])),
        _enum(map, 'previousEffect', NotificationPreviousEffect.values),
        NotificationCapabilities.fromMap(_object(map['capabilities'])),
        _optionalString(map, 'reason'),
      );
}

final class NotificationResult {
  final NotificationOutcome outcome;
  final NotificationReceipt? receipt;
  final NotificationPreviousEffect previousEffect;
  final String? reason;
  final NotificationCapabilities capabilities;
  const NotificationResult._(this.outcome, this.receipt, this.previousEffect,
      this.reason, this.capabilities);
  factory NotificationResult.fromMap(Map<Object?, Object?> map) =>
      NotificationResult._(
        _enum(map, 'outcome', NotificationOutcome.values),
        _field(map, 'receipt') == null
            ? null
            : NotificationReceipt.fromMap(_object(map['receipt'])),
        _enum(map, 'previousEffect', NotificationPreviousEffect.values),
        _optionalString(map, 'reason'),
        NotificationCapabilities.fromMap(_object(map['capabilities'])),
      );
}

final class NotificationNativeEntry {
  final String identifier;
  final String? attemptId;
  final NotificationMode? mode;
  final NotificationNativeKind kind;
  final String status;
  final int? deliveredAtMs;
  const NotificationNativeEntry._(this.identifier, this.attemptId, this.mode,
      this.kind, this.status, this.deliveredAtMs);
  factory NotificationNativeEntry.fromMap(Map<Object?, Object?> map) =>
      NotificationNativeEntry._(
        _string(map, 'identifier'),
        _optionalString(map, 'attemptId'),
        _field(map, 'mode') == null
            ? null
            : _enum(map, 'mode', NotificationMode.values),
        _enum(map, 'kind', NotificationNativeKind.values),
        _string(map, 'status'),
        _optionalInteger(map, 'deliveredAtMs'),
      );
}

/// Native observations are read independently from saved receipts. Failure erases neither.
sealed class NotificationNativeQuery {
  const NotificationNativeQuery();
  factory NotificationNativeQuery.fromMap(Map<Object?, Object?> map) =>
      switch (_string(map, 'status')) {
        'available' => NotificationNativeQueryAvailable._(
            _integer(map, 'observedAtMs'),
            List.unmodifiable(_list(map, 'entries').map(
                (value) => NotificationNativeEntry.fromMap(_object(value))))),
        'unavailable' =>
          NotificationNativeQueryUnavailable._(_string(map, 'reason')),
        final value =>
          throw FormatException('Unknown native query status: $value'),
      };
}

final class NotificationNativeQueryAvailable extends NotificationNativeQuery {
  final int observedAtMs;
  final List<NotificationNativeEntry> entries;
  const NotificationNativeQueryAvailable._(this.observedAtMs, this.entries);
}

final class NotificationNativeQueryUnavailable extends NotificationNativeQuery {
  final String reason;
  const NotificationNativeQueryUnavailable._(this.reason);
}

/// Only an available query with null records establishes that no offer is retained.
sealed class NotificationQuery {
  const NotificationQuery();
  factory NotificationQuery.fromMap(Map<Object?, Object?> map) =>
      switch (_string(map, 'status')) {
        'available' => NotificationQueryAvailable._(
            _field(map, 'normal') == null
                ? null
                : NotificationReceipt.fromMap(_object(map['normal'])),
            _field(map, 'diagnostic') == null
                ? null
                : NotificationReceipt.fromMap(_object(map['diagnostic'])),
            NotificationNativeQuery.fromMap(_object(map['native']))),
        'unavailable' => NotificationQueryUnavailable._(_string(map, 'reason')),
        final value =>
          throw FormatException('Unknown notification query status: $value'),
      };
}

final class NotificationQueryAvailable extends NotificationQuery {
  final NotificationReceipt? normal;
  final NotificationReceipt? diagnostic;
  final NotificationNativeQuery native;
  const NotificationQueryAvailable._(this.normal, this.diagnostic, this.native);
}

final class NotificationQueryUnavailable extends NotificationQuery {
  final String reason;
  const NotificationQueryUnavailable._(this.reason);
}

Object? _field(Map<Object?, Object?> map, String key) {
  if (!map.containsKey(key)) {
    throw FormatException('Missing notification $key');
  }
  return map[key];
}

Map<Object?, Object?> _object(Object? value) {
  if (value is! Map) {
    throw const FormatException('Expected a notification object');
  }
  return value.cast<Object?, Object?>();
}

String _string(Map<Object?, Object?> map, String key) {
  final value = map[key];
  if (value is! String) {
    throw FormatException('Expected notification $key string');
  }
  return value;
}

String? _optionalString(Map<Object?, Object?> map, String key) =>
    _field(map, key) == null ? null : _string(map, key);
int _integerValue(Object? value, String key) {
  if (value is! int || value.abs() > 9007199254740991) {
    throw FormatException('Expected exact notification $key integer');
  }
  return value;
}

int _integer(Map<Object?, Object?> map, String key) =>
    _integerValue(map[key], key);
int? _optionalInteger(Map<Object?, Object?> map, String key) =>
    _field(map, key) == null ? null : _integer(map, key);
List<Object?> _list(Map<Object?, Object?> map, String key) {
  final value = map[key];
  if (value is! List) throw FormatException('Expected notification $key array');
  return value.cast<Object?>();
}

T _enumValue<T extends Enum>(Object? value, List<T> values) =>
    values.firstWhere((entry) => entry.name == value,
        orElse: () =>
            throw FormatException('Unknown notification value: $value'));
T _enum<T extends Enum>(
        Map<Object?, Object?> map, String key, List<T> values) =>
    _enumValue(map[key], values);
