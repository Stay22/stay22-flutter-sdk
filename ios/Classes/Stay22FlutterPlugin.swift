import Flutter
import Stay22SDK
import UIKit

/// Flutter bridge for the Stay22 iOS SDK.
public class Stay22FlutterPlugin: NSObject, FlutterPlugin, Stay22EventListener {

    private static let methodChannelName = "com.stay22/method"
    private static let eventChannelName = "com.stay22/events"

    /// Info.plist key that lets the SDK initialize during app launch.
    private static let plistAidKey = "Stay22PartnerAID"

    /// Deep enough for a cold-start replay, shallow enough to never be a leak.
    private static let maxBufferedEvents = 32

    /// Calls that no-op on the native SDK before `initialize()` instead of doing
    /// anything observable — the exact set matters, so see the Android bridge's
    /// companion-object comment (`cross-platform-parity`) for why each call sits
    /// where it does. `initialize`/`isInitialized`, the pre-init-safe setters
    /// (`setEnabled`/`isEnabled`/`setMedium`/`setCampaignId`/`setNotificationConfig`),
    /// `ownsNotificationDelegate`, diagnostics, and the testing switches are exempt
    /// on both platforms; everything in this set used to silently discard the call.
    private static let requiresInitialization: Set<String> = [
        "hasNotificationPermission",
        "requestNotificationPermission",
        "setTravelContext",
        "clearTravelContext",
        "scheduleNotification",
    ]

    /// The SDK holds its event listener weakly, so without this the plugin is
    /// deallocated and events stop arriving with no error anywhere.
    private static var retained: Stay22FlutterPlugin?

    private var eventSink: FlutterEventSink?

    /// Events that arrived before Dart subscribed. See the Android bridge for why
    /// the listener is claimed at registration rather than on first subscription.
    private var bufferedEvents: [[String: Any]] = []

    // MARK: - Registration

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = Stay22FlutterPlugin()
        retained = instance

        let methodChannel = FlutterMethodChannel(
            name: methodChannelName,
            binaryMessenger: registrar.messenger()
        )
        registrar.addMethodCallDelegate(instance, channel: methodChannel)

        let eventChannel = FlutterEventChannel(
            name: eventChannelName,
            binaryMessenger: registrar.messenger()
        )
        eventChannel.setStreamHandler(instance)

        Stay22.advanced.setEventListener(instance)
        instance.initializeFromPlist()
    }

    /// Initializes from a `Stay22PartnerAID` Info.plist entry when one is present.
    ///
    /// This runs from `GeneratedPluginRegistrant` inside
    /// `didFinishLaunchingWithOptions`, which is the last moment at which the SDK can
    /// still claim `UNUserNotificationCenter.delegate` before iOS delivers a
    /// launch-time notification tap. Initializing from Dart is too late for that, so an
    /// app that wants cold-start taps to open their booking page declares the ID here.
    private func initializeFromPlist() {
        guard !Stay22.isInitialized else { return }
        guard
            let aid = (Bundle.main.object(forInfoDictionaryKey: Self.plistAidKey) as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !aid.isEmpty
        else { return }

        Stay22.initialize(aid: aid)
    }

    // MARK: - Method calls

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any]

        if Self.requiresInitialization.contains(call.method), !Stay22.isInitialized {
            result(
                FlutterError(
                    code: "not_initialized",
                    message: "Stay22 is not initialized. Declare \(Self.plistAidKey) in "
                        + "Info.plist or call Stay22.initialize(aid:) first.",
                    details: nil
                )
            )
            return
        }

        switch call.method {
        case "initialize":
            respond(result) {
                guard !Stay22.isInitialized else { return nil }
                let aid = try self.requireString(args, "aid")
                Stay22.initialize(aid: aid)
                // iOS logs and returns on a bad aid where Android throws. Checking
                // here is what makes the two platforms fail the same way.
                guard Stay22.isInitialized else {
                    throw PluginError(
                        "native_failure",
                        "Stay22 did not initialize. Check that the partner ID is valid."
                    )
                }
                return nil
            }

        case "isInitialized":
            result(Stay22.isInitialized)

        case "setEnabled":
            respond(result) {
                Stay22.isEnabled = try self.requireBool(args, "enabled")
                return nil
            }

        case "isEnabled":
            result(Stay22.isEnabled)

        case "setMedium":
            respond(result) {
                Stay22.medium = try self.requireString(args, "medium")
                return nil
            }

        case "setCampaignId":
            respond(result) {
                Stay22.campaignId = self.optionalString(args, "campaignId")
                return nil
            }

        case "hasNotificationPermission":
            Task {
                let value = await Stay22.hasNotificationPermission()
                await MainActor.run { result(value) }
            }

        case "requestNotificationPermission":
            Task {
                let granted = await Stay22.requestNotificationPermission()
                await MainActor.run { result(granted) }
            }

        case "setTravelContext":
            respond(result) {
                Stay22.setTravelContext(
                    TravelContext(
                        address: self.optionalString(args, "address"),
                        latitude: (args?["latitude"] as? NSNumber)?.doubleValue,
                        longitude: (args?["longitude"] as? NSNumber)?.doubleValue,
                        checkinDate: self.optionalString(args, "checkinDate"),
                        checkoutDate: self.optionalString(args, "checkoutDate"),
                        hotelName: self.optionalString(args, "hotelName"),
                        adults: (args?["adults"] as? NSNumber)?.intValue,
                        children: (args?["children"] as? NSNumber)?.intValue
                    )
                )
                return nil
            }

        case "clearTravelContext":
            respond(result) {
                Stay22.clearTravelContext()
                return nil
            }

        case "setNotificationConfig":
            respond(result) {
                Stay22.notificationConfig = try self.notificationConfig(from: args)
                return nil
            }

        case "ownsNotificationDelegate":
            result(Stay22.ownsNotificationDelegate)

        case "scheduleNotification":
            respond(result) {
                Stay22.advanced.scheduleNotification(force: (args?["force"] as? Bool) ?? false)
                return nil
            }

        case "setForce":
            respond(result) {
                Stay22.testing.force = try self.requireBool(args, "enabled")
                return nil
            }

        case "setShowLogs":
            respond(result) {
                Stay22.testing.showLogs = try self.requireBool(args, "enabled")
                return nil
            }

        case "setBaseURL":
            respond(result) {
                Stay22.testing.baseURL = try self.requireString(args, "url")
                return nil
            }

        case "runDiagnostics":
            Task {
                let report = await Stay22.diagnostics.run()
                await MainActor.run { result(Self.map(report)) }
            }

        case "logDiagnosticsReport":
            Task {
                let report = await Stay22.diagnostics.logReport()
                await MainActor.run { result(Self.map(report)) }
            }

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func respond(_ result: @escaping FlutterResult, _ block: () throws -> Any?) {
        do {
            result(try block())
        } catch let error as PluginError {
            result(FlutterError(code: error.code, message: error.message, details: nil))
        } catch {
            result(
                FlutterError(
                    code: "native_failure",
                    message: error.localizedDescription,
                    details: nil
                )
            )
        }
    }

    // MARK: - Marshalling

    private func notificationConfig(from args: [String: Any]?) throws -> NotificationConfig {
        // Read the SDK's own defaults off a throwaway instance rather than
        // repeating the literals here, where they would quietly go stale.
        let defaults = NotificationConfig()

        var interruptionLevel: NotificationInterruptionLevel?
        if let raw = optionalString(args, "interruptionLevel") {
            guard let parsed = NotificationInterruptionLevel(rawValue: raw) else {
                throw PluginError(
                    "invalid_argument",
                    "interruptionLevel must be one of passive, active, timeSensitive."
                )
            }
            interruptionLevel = parsed
        }

        return NotificationConfig(
            title: optionalString(args, "title") ?? defaults.title,
            subtitle: optionalString(args, "subtitle"),
            message: optionalString(args, "message") ?? defaults.message,
            categoryId: try nonBlank(args, "categoryId") ?? defaults.categoryId,
            threadId: try nonBlank(args, "threadId") ?? defaults.threadId,
            badge: (args?["badge"] as? NSNumber)?.intValue,
            launchImageName: optionalString(args, "launchImageName"),
            targetContentIdentifier: optionalString(args, "targetContentIdentifier"),
            interruptionLevel: interruptionLevel,
            relevanceScore: (args?["relevanceScore"] as? NSNumber)?.doubleValue,
            attachments: try attachments(args?["attachments"]),
            actions: try actions(args?["actions"])
        )
    }

    private func attachments(_ value: Any?) throws -> [NotificationAttachment] {
        guard let entries = try objectArray(value, "attachments") else { return [] }
        return try entries.enumerated().map { index, entry in
            guard
                let raw = (entry["fileURL"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                !raw.isEmpty
            else {
                throw PluginError(
                    "invalid_argument",
                    "attachments[\(index)] requires fileURL to be a non-empty string."
                )
            }
            // Attachments must be local files. Accept both a file:// URL and a
            // bare path; a bare path run through URL(string:) would produce a
            // relative reference that resolves to nothing.
            let url = raw.contains("://") ? URL(string: raw) : URL(fileURLWithPath: raw)
            guard let url else {
                throw PluginError(
                    "invalid_argument",
                    "attachments[\(index)].fileURL is not a valid file URL."
                )
            }
            if let identifier = (entry["identifier"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !identifier.isEmpty {
                return NotificationAttachment(identifier: identifier, fileURL: url)
            }
            return NotificationAttachment(fileURL: url)
        }
    }

    private func actions(_ value: Any?) throws -> [NotificationAction] {
        guard let entries = try objectArray(value, "actions") else { return [] }
        let defaults = NotificationAction(identifier: "placeholder", title: "placeholder")
        return try entries.enumerated().map { index, entry in
            guard
                let identifier = (entry["identifier"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines), !identifier.isEmpty,
                let title = (entry["title"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty
            else {
                throw PluginError(
                    "invalid_argument",
                    "actions[\(index)] requires identifier and title to be non-empty strings."
                )
            }
            return NotificationAction(
                identifier: identifier,
                title: title,
                foreground: (entry["foreground"] as? Bool) ?? defaults.foreground,
                authenticationRequired: (entry["authenticationRequired"] as? Bool)
                    ?? defaults.authenticationRequired,
                destructive: (entry["destructive"] as? Bool) ?? defaults.destructive
            )
        }
    }

    private func objectArray(_ value: Any?, _ key: String) throws -> [[String: Any]]? {
        // JS-style null arrives as NSNull, which is not nil.
        guard let value, !(value is NSNull) else { return nil }
        guard let entries = value as? [[String: Any]] else {
            throw PluginError("invalid_argument", "\(key) must be a list of objects.")
        }
        return entries
    }

    private func optionalString(_ args: [String: Any]?, _ key: String) -> String? {
        guard let raw = args?[key] as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func requireString(_ args: [String: Any]?, _ key: String) throws -> String {
        guard let value = optionalString(args, key) else {
            throw PluginError("missing_argument", "Missing required argument '\(key)'.")
        }
        return value
    }

    private func nonBlank(_ args: [String: Any]?, _ key: String) throws -> String? {
        guard let raw = args?[key] as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw PluginError(
                "invalid_argument",
                "Argument '\(key)' must not be blank when provided."
            )
        }
        return trimmed
    }

    private func requireBool(_ args: [String: Any]?, _ key: String) throws -> Bool {
        guard let value = args?[key] as? Bool else {
            throw PluginError("missing_argument", "Missing required argument '\(key)'.")
        }
        return value
    }

    private static func map(_ report: Stay22Diagnostics) -> [String: Any] {
        [
            "sdkVersion": report.sdkVersion,
            "describe": report.describe(),
            "checks": report.checks.map { check in
                [
                    "name": check.name,
                    "status": check.status.rawValue,
                    "detail": check.detail as Any,
                ]
            },
        ]
    }

    // MARK: - Stay22EventListener

    public func onEvent(_ event: Stay22Event) {
        var body: [String: Any] = [:]
        switch event {
        case .locationUpdated(let destination):
            body = ["type": "locationUpdated", "destination": destination]
        case .notificationScheduled(let destination, let delay):
            // Seconds, matching the native type. Do not convert.
            body = ["type": "notificationScheduled", "destination": destination, "delay": delay]
        case .notificationShown(let destination):
            body = ["type": "notificationShown", "destination": destination]
        case .notificationClicked(let destination, let url):
            body = ["type": "notificationClicked", "destination": destination, "url": url]
        case .notificationBlocked(let reason):
            body = ["type": "notificationBlocked", "reason": reason]
        case .notificationSkipped(let reason):
            body = ["type": "notificationSkipped", "reason": reason]
        case .notificationCancelled(let reason):
            body = ["type": "notificationCancelled", "reason": reason]
        case .enabledChanged(let isEnabled):
            body = ["type": "enabledChanged", "isEnabled": isEnabled]
        case .travelContextCleared:
            body = ["type": "travelContextCleared"]
        }

        if let sink = eventSink {
            sink(body)
        } else {
            if bufferedEvents.count >= Self.maxBufferedEvents {
                bufferedEvents.removeFirst()
            }
            bufferedEvents.append(body)
        }
    }

    private struct PluginError: Error {
        let code: String
        let message: String

        init(_ code: String, _ message: String) {
            self.code = code
            self.message = message
        }
    }
}

// MARK: - FlutterStreamHandler

extension Stay22FlutterPlugin: FlutterStreamHandler {
    public func onListen(
        withArguments arguments: Any?,
        eventSink events: @escaping FlutterEventSink
    ) -> FlutterError? {
        eventSink = events
        // The native listener was claimed at registration; hand over whatever
        // arrived before Dart got here.
        let pending = bufferedEvents
        bufferedEvents.removeAll()
        for event in pending {
            events(event)
        }
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        // Keep the native listener and go back to buffering, so a hot restart
        // does not drop events while Dart briefly has no subscriber.
        eventSink = nil
        return nil
    }
}
