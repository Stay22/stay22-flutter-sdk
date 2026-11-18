package com.stay22.flutter

import com.stay22.sdk.NotificationAllowedWindows
import com.stay22.sdk.NotificationCapabilities
import com.stay22.sdk.NotificationExecution
import com.stay22.sdk.NotificationLocalWindow
import com.stay22.sdk.NotificationMode
import com.stay22.sdk.NotificationNativeQuery
import com.stay22.sdk.NotificationQuery
import com.stay22.sdk.NotificationReceipt
import com.stay22.sdk.NotificationReference
import com.stay22.sdk.NotificationRequest
import com.stay22.sdk.NotificationRequestedTiming
import com.stay22.sdk.NotificationResult
import com.stay22.sdk.NotificationTiming
import com.stay22.sdk.NotificationWindowGuarantee
import com.stay22.sdk.Stay22
import com.stay22.sdk.TravelContext

// Commands and events use one projection. The SDK owns business validation,
// revision matching, and revocation; this boundary only checks transport shapes.
internal object NotificationBridgeCodec {
    fun command(method: String, input: Any?): Map<String, Any?> {
        val args = objectValue(input, "arguments")
        val result = when (method) {
            "ensureNotification" -> Stay22.notifications.ensure(request(args))
            "updateNotification" -> {
                keys(args, setOf("reference", "timing", "allowedWindows", "expiresAtMs", "actionExpiresAtMs"))
                Stay22.notifications.update(reference(args["reference"]), timing(args["timing"]), windows(args["allowedWindows"]),
                    integer(args, "expiresAtMs"), integer(args, "actionExpiresAtMs"))
            }
            "replaceNotification" -> {
                keys(args, setOf("reference", "request"))
                Stay22.notifications.replace(reference(args["reference"]), request(objectValue(args["request"], "request")))
            }
            "cancelNotification" -> {
                keys(args, setOf("reference"))
                Stay22.notifications.cancel(reference(args["reference"]))
            }
            "scheduleDiagnosticNotification" -> {
                keys(args, setOf("trip"))
                Stay22.testing.scheduleNotification(trip(args["trip"]))
            }
            else -> invalid("method")
        }
        return map(result)
    }

    fun request(args: Map<*, *>): NotificationRequest {
        keys(args, setOf("trip", "timing", "allowedWindows", "expiresAtMs", "actionExpiresAtMs"))
        return NotificationRequest(trip(args["trip"]), if (args.containsKey("timing")) timing(args["timing"]) else NotificationTiming.AccountDefault,
            windows(args["allowedWindows"]), integer(args, "expiresAtMs"), integer(args, "actionExpiresAtMs"))
    }

    fun trip(value: Any?): TravelContext {
        val args = objectValue(value, "trip")
        keys(args, setOf("address", "latitude", "longitude", "checkinDate", "checkoutDate", "hotelName", "adults", "children", "context"))
        val context = args["context"]?.let { input ->
            objectValue(input, "context").entries.associate { (key, entry) ->
                (key as? String ?: invalid("context key")) to (entry as? String ?: invalid("context value"))
            }
        }
        return TravelContext(address = string(args, "address"), latitude = number(args, "latitude"), longitude = number(args, "longitude"),
            checkinDate = string(args, "checkinDate"), checkoutDate = string(args, "checkoutDate"), hotelName = string(args, "hotelName"),
            adults = int32(args, "adults"), children = int32(args, "children"), context = context)
    }

    fun reference(value: Any?): NotificationReference {
        val args = objectValue(value, "reference")
        val mode = NotificationMode.entries.find { it.rawValue == requiredString(args, "mode") } ?: invalid("mode")
        return NotificationReference(requiredString(args, "id"), requiredInteger(args, "revision"), mode)
    }

    fun timing(value: Any?): NotificationTiming {
        val args = objectValue(value, "timing")
        return when (requiredString(args, "type")) {
            "accountDefault" -> { keys(args, setOf("type")); NotificationTiming.AccountDefault }
            "after" -> { keys(args, setOf("type", "delayMs")); NotificationTiming.After(requiredInteger(args, "delayMs")) }
            "notBefore" -> { keys(args, setOf("type", "atMs")); NotificationTiming.NotBefore(requiredInteger(args, "atMs")) }
            "at" -> { keys(args, setOf("type", "atMs")); NotificationTiming.At(requiredInteger(args, "atMs")) }
            else -> invalid("timing.type")
        }
    }

    fun windows(value: Any?): NotificationAllowedWindows? {
        if (value == null) return null
        val args = objectValue(value, "allowedWindows")
        keys(args, setOf("timeZone", "periods", "requiredWindowGuarantee"))
        val guarantee = NotificationWindowGuarantee.entries.find { it.rawValue == requiredString(args, "requiredWindowGuarantee") }
            ?: invalid("requiredWindowGuarantee")
        val periods = args["periods"] as? List<*> ?: invalid("periods")
        return NotificationAllowedWindows(requiredString(args, "timeZone"), periods.map { value ->
            val period = objectValue(value, "period")
            keys(period, setOf("weekdays", "startMinute", "endMinute"))
            val weekdays = period["weekdays"]?.let { days ->
                (days as? List<*> ?: invalid("weekdays")).map { day -> int32(mapOf("day" to day), "day") ?: invalid("weekday") }
            }
            NotificationLocalWindow(weekdays, int32(period, "startMinute") ?: invalid("startMinute"),
                int32(period, "endMinute") ?: invalid("endMinute"))
        }, guarantee)
    }

    fun map(result: NotificationResult): Map<String, Any?> = mapOf(
        "outcome" to result.outcome.rawValue, "receipt" to result.receipt?.let(::map), "previousEffect" to result.previousEffect.rawValue,
        "reason" to result.reason, "capabilities" to map(result.capabilities))

    fun map(receipt: NotificationReceipt): Map<String, Any?> = mapOf(
        "id" to receipt.id, "revision" to receipt.revision, "mode" to receipt.mode.rawValue,
        "reference" to mapOf("id" to receipt.id, "revision" to receipt.revision, "mode" to receipt.mode.rawValue),
        "requestStatus" to receipt.requestStatus.rawValue, "requested" to receipt.requested?.let(::map), "execution" to receipt.execution?.let(::map),
        "previousEffect" to receipt.previousEffect.rawValue, "capabilities" to map(receipt.capabilities), "reason" to receipt.reason)

    fun map(query: NotificationQuery): Map<String, Any?> = when (query) {
        is NotificationQuery.Unavailable -> mapOf("status" to "unavailable", "reason" to query.reason)
        is NotificationQuery.Available -> mapOf("status" to "available", "normal" to query.normal?.let(::map),
            "diagnostic" to query.diagnostic?.let(::map), "native" to map(query.native))
    }

    private fun map(query: NotificationNativeQuery): Map<String, Any?> = when (query) {
        is NotificationNativeQuery.Unavailable -> mapOf("status" to "unavailable", "reason" to query.reason)
        is NotificationNativeQuery.Available -> mapOf("status" to "available", "observedAtMs" to query.observedAtMs,
            "entries" to query.entries.map { entry -> mapOf("identifier" to entry.identifier, "attemptId" to entry.attemptId,
                "mode" to entry.mode?.rawValue, "kind" to entry.kind.rawValue, "status" to entry.status, "deliveredAtMs" to entry.deliveredAtMs) })
    }

    private fun map(capabilities: NotificationCapabilities): Map<String, Any?> = mapOf(
        "windowGuarantees" to capabilities.windowGuarantees.map { it.rawValue }, "supportedHorizonMs" to capabilities.supportedHorizonMs)

    private fun map(requested: NotificationRequestedTiming): Map<String, Any?> = mapOf(
        "timing" to map(requested.timing), "submittedAtMs" to requested.submittedAtMs, "expiresAtMs" to requested.expiresAtMs,
        "actionExpiresAtMs" to requested.actionExpiresAtMs, "executionExpirySource" to requested.executionExpirySource.rawValue,
        "actionExpirySource" to requested.actionExpirySource.rawValue, "allowedWindows" to requested.allowedWindows?.let(::map))

    private fun map(timing: NotificationTiming): Map<String, Any?> = when (timing) {
        NotificationTiming.AccountDefault -> mapOf("type" to "accountDefault")
        is NotificationTiming.After -> mapOf("type" to "after", "delayMs" to timing.delayMs)
        is NotificationTiming.NotBefore -> mapOf("type" to "notBefore", "atMs" to timing.atMs)
        is NotificationTiming.At -> mapOf("type" to "at", "atMs" to timing.atMs)
    }

    private fun map(windows: NotificationAllowedWindows): Map<String, Any?> = mapOf(
        "timeZone" to windows.timeZone, "requiredWindowGuarantee" to windows.requiredWindowGuarantee.rawValue,
        "periods" to windows.periods.map { mapOf("weekdays" to it.weekdays, "startMinute" to it.startMinute, "endMinute" to it.endMinute) })

    private fun map(execution: NotificationExecution): Map<String, Any?> = mapOf(
        "revision" to execution.revision, "requested" to map(execution.requested), "acceptedTiming" to mapOf(
            "targetAtMs" to execution.acceptedTiming.targetAtMs, "intervalStartAtMs" to execution.acceptedTiming.intervalStartAtMs,
            "intervalEndAtMs" to execution.acceptedTiming.intervalEndAtMs, "guarantee" to execution.acceptedTiming.guarantee.rawValue),
        "actionExpiresAtMs" to execution.actionExpiresAtMs, "phase" to execution.phase.rawValue, "evidence" to execution.evidence.rawValue,
        "observedAtMs" to execution.observedAtMs, "capabilities" to map(execution.capabilities), "reason" to execution.reason)

    private fun objectValue(value: Any?, field: String): Map<*, *> = value as? Map<*, *> ?: invalid(field)
    private fun keys(value: Map<*, *>, allowed: Set<String>) { require(value.keys.all { it in allowed }) { "Unsupported notification field." } }
    private fun string(value: Map<*, *>, field: String): String? = value[field]?.let { it as? String ?: invalid(field) }
    private fun requiredString(value: Map<*, *>, field: String): String = string(value, field) ?: invalid(field)
    private fun number(value: Map<*, *>, field: String): Double? = value[field]?.let { input ->
        (input as? Number)?.toDouble()?.takeIf { it.isFinite() } ?: invalid(field)
    }
    private fun integer(value: Map<*, *>, field: String): Long? = number(value, field)?.let { input ->
        require(input % 1.0 == 0.0 && kotlin.math.abs(input) <= 9_007_199_254_740_991.0) { "Invalid integer: $field." }
        input.toLong()
    }
    private fun requiredInteger(value: Map<*, *>, field: String): Long = integer(value, field) ?: invalid(field)
    private fun int32(value: Map<*, *>, field: String): Int? = integer(value, field)?.let { input ->
        require(input in Int.MIN_VALUE..Int.MAX_VALUE) { "Invalid integer: $field." }
        input.toInt()
    }
    private fun invalid(field: String): Nothing = throw IllegalArgumentException("Invalid notification argument: $field.")
}
