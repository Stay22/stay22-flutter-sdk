import CoreFoundation
import Foundation
import Stay22SDK

// Both bridge commands and events use this projection so receipts never acquire
// wrapper-owned state. Business validation and revocation remain in the SDK.
enum NotificationBridgeCodec {
    struct InvalidInput: LocalizedError {
        let field: String
        var errorDescription: String? { "Invalid notification argument: \(field)." }
    }

    @MainActor static func command(_ method: String, _ input: Any?) throws -> [String: Any] {
        let args = try object(input, "arguments")
        let result: NotificationResult
        switch method {
        case "ensureNotification": result = Stay22.notifications.ensure(try request(args))
        case "updateNotification":
            try keys(args, ["reference", "timing", "allowedWindows", "expiresAtMs", "actionExpiresAtMs"])
            result = try Stay22.notifications.update(reference(args["reference"]), timing: timing(args["timing"]),
                allowedWindows: windows(args["allowedWindows"]), expiresAtMs: integer(args, "expiresAtMs"),
                actionExpiresAtMs: integer(args, "actionExpiresAtMs"))
        case "replaceNotification":
            try keys(args, ["reference", "request"])
            result = try Stay22.notifications.replace(reference(args["reference"]), with: request(object(args["request"], "request")))
        case "cancelNotification":
            try keys(args, ["reference"])
            result = Stay22.notifications.cancel(try reference(args["reference"]))
        case "scheduleDiagnosticNotification":
            try keys(args, ["trip"])
            result = Stay22.testing.scheduleNotification(try trip(args["trip"]))
        default: throw InvalidInput(field: "method")
        }
        return map(result)
    }

    static func request(_ args: [String: Any]) throws -> NotificationRequest {
        try keys(args, ["trip", "timing", "allowedWindows", "expiresAtMs", "actionExpiresAtMs"])
        return try NotificationRequest(trip: trip(args["trip"]),
            timing: args.keys.contains("timing") ? timing(args["timing"]) : .accountDefault,
            allowedWindows: windows(args["allowedWindows"]), expiresAtMs: integer(args, "expiresAtMs"),
            actionExpiresAtMs: integer(args, "actionExpiresAtMs"))
    }

    static func trip(_ value: Any?) throws -> TravelContext {
        let args = try object(value, "trip")
        try keys(args, ["address", "latitude", "longitude", "checkinDate", "checkoutDate", "hotelName", "adults", "children", "context"])
        var context: [String: String]?
        if !absent(args["context"]) {
            let values = try object(args["context"], "context")
            context = try values.mapValues { value in
                guard let string = value as? String else { throw InvalidInput(field: "context value") }
                return string
            }
        }
        return try TravelContext(address: string(args, "address"), latitude: number(args, "latitude"),
            longitude: number(args, "longitude"), checkinDate: string(args, "checkinDate"),
            checkoutDate: string(args, "checkoutDate"), hotelName: string(args, "hotelName"),
            adults: int32(args, "adults"), children: int32(args, "children"), context: context)
    }

    static func reference(_ value: Any?) throws -> NotificationReference {
        let args = try object(value, "reference")
        let raw = try requiredString(args, "mode")
        guard let mode = NotificationMode(rawValue: raw) else { throw InvalidInput(field: "mode") }
        return try NotificationReference(id: requiredString(args, "id"), revision: requiredInteger(args, "revision"), mode: mode)
    }

    static func timing(_ value: Any?) throws -> NotificationTiming {
        let args = try object(value, "timing")
        switch try requiredString(args, "type") {
        case "accountDefault":
            try keys(args, ["type"])
            return .accountDefault
        case "after":
            try keys(args, ["type", "delayMs"])
            return .after(delayMs: try requiredInteger(args, "delayMs"))
        case "notBefore":
            try keys(args, ["type", "atMs"])
            return .notBefore(atMs: try requiredInteger(args, "atMs"))
        case "at":
            try keys(args, ["type", "atMs"])
            return .at(atMs: try requiredInteger(args, "atMs"))
        default: throw InvalidInput(field: "timing.type")
        }
    }

    static func windows(_ value: Any?) throws -> NotificationAllowedWindows? {
        if absent(value) { return nil }
        let args = try object(value, "allowedWindows")
        try keys(args, ["timeZone", "periods", "requiredWindowGuarantee"])
        let raw = try requiredString(args, "requiredWindowGuarantee")
        guard let guarantee = NotificationWindowGuarantee(rawValue: raw), let periods = args["periods"] as? [Any] else {
            throw InvalidInput(field: "allowedWindows")
        }
        return try NotificationAllowedWindows(timeZone: requiredString(args, "timeZone"), periods: periods.map { value in
            let period = try object(value, "period")
            try keys(period, ["weekdays", "startMinute", "endMinute"])
            var weekdays: [Int]?
            if !absent(period["weekdays"]) {
                guard let days = period["weekdays"] as? [Any] else { throw InvalidInput(field: "weekdays") }
                weekdays = try days.map { value in
                    guard let day = try int32(["day": value], "day") else { throw InvalidInput(field: "weekday") }
                    return day
                }
            }
            guard let start = try int32(period, "startMinute"), let end = try int32(period, "endMinute") else {
                throw InvalidInput(field: "period minutes")
            }
            return NotificationLocalWindow(weekdays: weekdays, startMinute: start, endMinute: end)
        }, requiredWindowGuarantee: guarantee)
    }

    static func map(_ result: NotificationResult) -> [String: Any] {
        ["outcome": result.outcome.rawValue, "receipt": nullable(result.receipt.map(map)),
         "previousEffect": result.previousEffect.rawValue, "reason": nullable(result.reason), "capabilities": map(result.capabilities)]
    }

    static func map(_ receipt: NotificationReceipt) -> [String: Any] {
        ["id": receipt.id, "revision": receipt.revision, "mode": receipt.mode.rawValue,
         "reference": ["id": receipt.id, "revision": receipt.revision, "mode": receipt.mode.rawValue],
         "requestStatus": receipt.requestStatus.rawValue, "requested": nullable(receipt.requested.map(map)),
         "execution": nullable(receipt.execution.map(map)), "previousEffect": receipt.previousEffect.rawValue,
         "capabilities": map(receipt.capabilities), "reason": nullable(receipt.reason)]
    }

    static func map(_ query: NotificationQuery) -> [String: Any] {
        switch query {
        case .unavailable(let reason): return ["status": "unavailable", "reason": reason]
        case .available(let normal, let diagnostic, let native):
            return ["status": "available", "normal": nullable(normal.map(map)), "diagnostic": nullable(diagnostic.map(map)), "native": map(native)]
        @unknown default: return ["status": "unavailable", "reason": "unsupported_native_state"]
        }
    }

    private static func map(_ query: NotificationNativeQuery) -> [String: Any] {
        switch query {
        case .unavailable(let reason): return ["status": "unavailable", "reason": reason]
        case .available(let observedAtMs, let entries):
            return ["status": "available", "observedAtMs": observedAtMs, "entries": entries.map { entry in
                ["identifier": entry.identifier, "attemptId": nullable(entry.attemptId), "mode": nullable(entry.mode?.rawValue),
                 "kind": entry.kind.rawValue, "status": entry.status, "deliveredAtMs": nullable(entry.deliveredAtMs)]
            }]
        @unknown default: return ["status": "unavailable", "reason": "unsupported_native_state"]
        }
    }

    private static func map(_ capabilities: NotificationCapabilities) -> [String: Any] {
        ["windowGuarantees": capabilities.windowGuarantees.map(\.rawValue), "supportedHorizonMs": nullable(capabilities.supportedHorizonMs)]
    }

    private static func map(_ requested: NotificationRequestedTiming) -> [String: Any] {
        ["timing": map(requested.timing), "submittedAtMs": requested.submittedAtMs, "expiresAtMs": requested.expiresAtMs,
         "actionExpiresAtMs": requested.actionExpiresAtMs, "executionExpirySource": requested.executionExpirySource.rawValue,
         "actionExpirySource": requested.actionExpirySource.rawValue, "allowedWindows": nullable(requested.allowedWindows.map(map))]
    }

    private static func map(_ timing: NotificationTiming) -> [String: Any] {
        switch timing {
        case .accountDefault: return ["type": "accountDefault"]
        case .after(let delay): return ["type": "after", "delayMs": delay]
        case .notBefore(let instant): return ["type": "notBefore", "atMs": instant]
        case .at(let instant): return ["type": "at", "atMs": instant]
        @unknown default: return ["type": "unsupported_native_timing"]
        }
    }

    private static func map(_ windows: NotificationAllowedWindows) -> [String: Any] {
        ["timeZone": windows.timeZone, "requiredWindowGuarantee": windows.requiredWindowGuarantee.rawValue,
         "periods": windows.periods.map { ["weekdays": nullable($0.weekdays), "startMinute": $0.startMinute, "endMinute": $0.endMinute] }]
    }

    private static func map(_ execution: NotificationExecution) -> [String: Any] {
        ["revision": execution.revision, "requested": map(execution.requested), "acceptedTiming": [
            "targetAtMs": execution.acceptedTiming.targetAtMs, "intervalStartAtMs": execution.acceptedTiming.intervalStartAtMs,
            "intervalEndAtMs": execution.acceptedTiming.intervalEndAtMs, "guarantee": execution.acceptedTiming.guarantee.rawValue],
         "actionExpiresAtMs": execution.actionExpiresAtMs, "phase": execution.phase.rawValue, "evidence": execution.evidence.rawValue,
         "observedAtMs": nullable(execution.observedAtMs), "capabilities": map(execution.capabilities), "reason": nullable(execution.reason)]
    }

    private static func nullable<T>(_ value: T?) -> Any { value.map { $0 as Any } ?? NSNull() }
    private static func absent(_ value: Any?) -> Bool { value == nil || value is NSNull }
    private static func object(_ value: Any?, _ field: String) throws -> [String: Any] {
        guard let object = value as? [String: Any] else { throw InvalidInput(field: field) }
        return object
    }
    private static func keys(_ object: [String: Any], _ allowed: Set<String>) throws {
        guard Set(object.keys).isSubset(of: allowed) else { throw InvalidInput(field: "unsupported field") }
    }
    private static func string(_ object: [String: Any], _ key: String) throws -> String? {
        if absent(object[key]) { return nil }
        guard let string = object[key] as? String else { throw InvalidInput(field: key) }
        return string
    }
    private static func requiredString(_ object: [String: Any], _ key: String) throws -> String {
        guard let value = try string(object, key) else { throw InvalidInput(field: key) }
        return value
    }
    private static func number(_ object: [String: Any], _ key: String) throws -> Double? {
        if absent(object[key]) { return nil }
        guard let number = object[key] as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite else {
            throw InvalidInput(field: key)
        }
        return number.doubleValue
    }
    private static func integer(_ object: [String: Any], _ key: String) throws -> Int64? {
        guard let value = try number(object, key) else { return nil }
        guard value.rounded(.towardZero) == value, abs(value) <= 9_007_199_254_740_991 else { throw InvalidInput(field: key) }
        return Int64(value)
    }
    private static func requiredInteger(_ object: [String: Any], _ key: String) throws -> Int64 {
        guard let value = try integer(object, key) else { throw InvalidInput(field: key) }
        return value
    }
    private static func int32(_ object: [String: Any], _ key: String) throws -> Int? {
        guard let value = try integer(object, key) else { return nil }
        guard value >= Int32.min, value <= Int32.max else { throw InvalidInput(field: key) }
        return Int(value)
    }
}
