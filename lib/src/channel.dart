import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Error codes raised by the plugin.
///
/// Both platform bridges use this same set, so a caller never has to branch on
/// [defaultTargetPlatform] to interpret a failure.
abstract final class Stay22ErrorCode {
  /// A call that requires an initialized SDK ran before initialization.
  static const String notInitialized = 'not_initialized';

  /// An argument was present but unusable (wrong type, blank, out of range).
  static const String invalidArgument = 'invalid_argument';

  /// A required argument was absent.
  static const String missingArgument = 'missing_argument';

  /// Called on a platform the plugin does not support.
  static const String unsupportedPlatform = 'unsupported_platform';

  /// The native plugin is not registered on this Flutter engine.
  static const String pluginUnavailable = 'plugin_unavailable';

  /// Anything the native side did not anticipate.
  static const String nativeFailure = 'native_failure';
}

/// Method and event channel plumbing.
///
/// Centralizes three concerns so no call site repeats them: refusing to touch
/// the channel on an unsupported platform, turning a missing registration into
/// a named error instead of Flutter's generic [MissingPluginException], and
/// keeping every failure a [PlatformException].
abstract final class Stay22Channel {
  static const MethodChannel _methods = MethodChannel('com.stay22/method');
  static const EventChannel _events = EventChannel('com.stay22/events');

  /// Whether the plugin can run here. Android and iOS only.
  ///
  /// Importing the package on web or desktop is safe; calling into it is not,
  /// so shared Flutter code should branch on this rather than on the host OS.
  static bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static Future<T?> invoke<T>(String method,
      [Map<String, Object?>? arguments]) async {
    if (!isSupported) {
      throw _unsupportedPlatform();
    }

    try {
      return await _methods.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      throw _pluginUnavailable();
    }
  }

  /// Same as [invoke], but for the many native calls that answer with a bool
  /// and should never leave the caller holding a null.
  static Future<bool> invokeBool(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    return await invoke<bool>(method, arguments) ?? false;
  }

  static Future<Map<Object?, Object?>> invokeMap(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    final result = await invoke<Map<Object?, Object?>>(method, arguments);
    if (result == null) {
      throw PlatformException(
        code: Stay22ErrorCode.nativeFailure,
        message: '$method returned no payload.',
      );
    }
    return result;
  }

  static Stream<Object?>? _eventStream;

  /// The raw event stream.
  ///
  /// Cached deliberately. [EventChannel.receiveBroadcastStream] builds a fresh
  /// controller on every call, so calling it twice would open two independent
  /// subscriptions to one native listener slot — and the second one cancelling
  /// would tear down the first subscriber's feed. Handing every caller the same
  /// broadcast stream is what makes Flutter's own listen/cancel bookkeeping
  /// multiplex correctly.
  ///
  /// Deliberately NOT wrapped in a second `.asBroadcastStream()`: the stream
  /// [receiveBroadcastStream] returns is already broadcast, and wrapping an
  /// already-broadcast stream a second time swallows its `onCancel` — the
  /// underlying controller's listener count never reaches zero, so the native
  /// side is never told the last Dart listener left and its `EventChannel`
  /// stream handler leaks for the life of the engine. No event is lost either
  /// way; the defect was purely that native cleanup never ran. Confirmed with
  /// a standalone probe against a broadcast controller before this change.
  static Stream<Object?> events() {
    if (!isSupported) {
      return Stream<Object?>.error(_unsupportedPlatform()).asBroadcastStream();
    }

    return _eventStream ??= _events.receiveBroadcastStream().handleError(
      (Object error) {
        throw error is MissingPluginException ? _pluginUnavailable() : error;
      },
    );
  }

  /// Drops the cached stream. Tests only.
  @visibleForTesting
  static void resetEventStream() => _eventStream = null;

  static PlatformException _unsupportedPlatform() {
    return PlatformException(
      code: Stay22ErrorCode.unsupportedPlatform,
      message: 'stay22_flutter supports Android and iOS only. Guard calls with '
          'Stay22.isSupportedPlatform before using the plugin.',
      details: _platformName(),
    );
  }

  static PlatformException _pluginUnavailable() {
    return PlatformException(
      code: Stay22ErrorCode.pluginUnavailable,
      message: 'The stay22_flutter native plugin is not registered on this '
          'Flutter engine. Confirm the package is installed and rebuild the app '
          '(a hot restart is not enough).',
    );
  }

  static String _platformName() {
    if (kIsWeb) return 'web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      TargetPlatform.macOS => 'macos',
      TargetPlatform.windows => 'windows',
      TargetPlatform.linux => 'linux',
      TargetPlatform.fuchsia => 'fuchsia',
    };
  }
}
