/// Outcome of one diagnostic check.
enum Stay22CheckStatus {
  /// Correct, nothing to do.
  pass,

  /// Legitimate, but nothing will be delivered while it holds — the SDK is
  /// switched off, or a cooldown is running.
  warn,

  /// A misconfiguration or missing prerequisite that blocks delivery.
  fail;

  static Stay22CheckStatus fromWire(String? value) => switch (value) {
        'PASS' => Stay22CheckStatus.pass,
        'WARN' => Stay22CheckStatus.warn,
        'FAIL' => Stay22CheckStatus.fail,
        _ => Stay22CheckStatus.fail,
      };
}

/// A single check and what to do about it.
class Stay22Check {
  /// Stable identifier, safe to match on.
  final String name;

  final Stay22CheckStatus status;

  /// Explanation, and the remedy when [status] is not [Stay22CheckStatus.pass].
  final String? detail;

  const Stay22Check({required this.name, required this.status, this.detail});

  factory Stay22Check.fromMap(Map<Object?, Object?> map) => Stay22Check(
        name: map['name'] as String? ?? 'unknown',
        status: Stay22CheckStatus.fromWire(map['status'] as String?),
        detail: map['detail'] as String?,
      );
}

/// A snapshot of whether the SDK is wired up correctly.
///
/// Exists so an integrator never has to guess whether a missing notification is
/// their wiring or the SDK, and never has to wait out a multi-hour delay to
/// find out. Cheap, synchronous and free of side effects — running it schedules,
/// cancels and posts nothing.
class Stay22Diagnostics {
  final String sdkVersion;

  /// Every check that ran, in evaluation order.
  final List<Stay22Check> checks;

  final String _describe;

  const Stay22Diagnostics({
    required this.sdkVersion,
    required this.checks,
    required String describe,
  }) : _describe = describe;

  factory Stay22Diagnostics.fromMap(Map<Object?, Object?> map) {
    final rawChecks = (map['checks'] as List<Object?>? ?? const <Object?>[])
        .whereType<Map<Object?, Object?>>()
        .map(Stay22Check.fromMap)
        .toList(growable: false);

    return Stay22Diagnostics(
      sdkVersion: map['sdkVersion'] as String? ?? 'unknown',
      checks: rawChecks,
      describe: map['describe'] as String? ?? '',
    );
  }

  /// Checks that block delivery.
  List<Stay22Check> get failures => checks
      .where((c) => c.status == Stay22CheckStatus.fail)
      .toList(growable: false);

  /// Checks that are legitimate but mean nothing will be delivered right now.
  List<Stay22Check> get warnings => checks
      .where((c) => c.status == Stay22CheckStatus.warn)
      .toList(growable: false);

  /// True when nothing failed. Warnings do not make an integration unhealthy.
  bool get isHealthy => failures.isEmpty;

  /// The native SDK's own multi-line report.
  ///
  /// Taken verbatim from the platform rather than rebuilt here, so the wording
  /// has exactly one owner and cannot drift between Dart and native. Meant for
  /// a log, a debug screen or a bug report — not for parsing.
  String describe() => _describe;

  @override
  String toString() => describe();
}
