package com.stay22.flutter

import android.app.Application
import android.content.Context
import android.content.pm.PackageManager
import android.net.Uri
import android.util.Log
import com.stay22.sdk.NotificationAction
import com.stay22.sdk.NotificationAttachment
import com.stay22.sdk.NotificationConfig
import com.stay22.sdk.NotificationInterruptionLevel
import com.stay22.sdk.Stay22
import com.stay22.sdk.Stay22Diagnostics
import com.stay22.sdk.Stay22Event
import com.stay22.sdk.Stay22EventListener
import com.stay22.sdk.TravelContext
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/**
 * Flutter bridge for the Stay22 Android SDK.
 *
 * Implements [ActivityAware] because the notification permission prompt has to be
 * launched from a resumed Activity; without it the callback overload can never
 * report a real answer.
 */
class Stay22FlutterPlugin : FlutterPlugin, ActivityAware, MethodCallHandler {

    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private lateinit var context: Context

    private var eventSink: EventChannel.EventSink? = null

    /**
     * Events that arrived before Dart subscribed.
     *
     * The SDK replays anything the delayed notification worker raised while the
     * process was dead, but it does so from `onAppForegrounded`, and it *consumes*
     * the stored queue as it goes — `LocalStore.drainPendingEvents` removes the
     * records, and `emitEvent` drops anything raised while no listener is attached.
     * That drain reliably beats Dart's first `listen()`, so without a buffer here a
     * notification shown in a cold process is silently lost every time.
     */
    private val bufferedEvents = ArrayDeque<Map<String, Any?>>()

    private val eventListener = Stay22EventListener { event ->
        val payload = event.toMap()
        val sink = eventSink
        if (sink != null) {
            sink.success(payload)
        } else {
            if (bufferedEvents.size >= MAX_BUFFERED_EVENTS) bufferedEvents.removeFirst()
            bufferedEvents.addLast(payload)
        }
    }

    private val streamHandler = object : EventChannel.StreamHandler {
        override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
            eventSink = events
            // The native listener is already attached (see onAttachedToEngine);
            // all that is left is to hand over whatever arrived in the meantime.
            while (bufferedEvents.isNotEmpty()) {
                events?.success(bufferedEvents.removeFirst())
            }
        }

        override fun onCancel(arguments: Any?) {
            // Keep the native listener attached and go back to buffering. Detaching
            // here would lose events during a hot restart, when Dart briefly has no
            // subscriber.
            eventSink = null
        }
    }

    // --- FlutterPlugin ---

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext

        methodChannel = MethodChannel(binding.binaryMessenger, CHANNEL_METHOD)
        methodChannel.setMethodCallHandler(this)

        eventChannel = EventChannel(binding.binaryMessenger, CHANNEL_EVENTS)
        eventChannel.setStreamHandler(streamHandler)

        // Claim the listener slot now, before any Dart runs and before the manifest
        // initialization below can trigger a replay of queued events. Waiting for
        // Dart to subscribe would be too late — see [bufferedEvents].
        Stay22.advanced.setEventListener(eventListener)

        initializeFromManifest()
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        eventSink = null
        bufferedEvents.clear()
        Stay22.advanced.setEventListener(null)
    }

    // --- ActivityAware ---
    //
    // The SDK finds the current Activity itself, through the lifecycle callbacks it
    // registers on the Application. The plugin tracks the binding only so it can tell
    // "no Activity at all" (a headless or background engine, where a permission prompt
    // is impossible) apart from "the user said no" — the SDK reports both as false.

    private var activityBinding: ActivityPluginBinding? = null

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activityBinding = binding
    }

    override fun onDetachedFromActivity() {
        activityBinding = null
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activityBinding = null
    }

    /**
     * Initializes from a `com.stay22.sdk.PartnerAID` manifest entry when one is present.
     *
     * Runs during engine attach, which is earlier than any Dart code, so lifecycle
     * observers are registered before the first Activity starts. Apps that only learn
     * their partner ID at runtime skip the manifest entry and call `initialize` from Dart
     * instead.
     */
    private fun initializeFromManifest() {
        if (Stay22.isInitialized) return

        val aid = runCatching {
            context.packageManager
                .getApplicationInfo(context.packageName, PackageManager.GET_META_DATA)
                .metaData
                ?.getString(MANIFEST_AID_KEY)
        }.getOrNull()?.trim()

        if (aid.isNullOrEmpty()) return

        val application = context.applicationContext as? Application ?: return
        runCatching { Stay22.initialize(application, aid) }
            .onFailure { Log.w(TAG, "Manifest-declared Stay22 initialization failed", it) }
    }

    // --- MethodCallHandler ---

    override fun onMethodCall(call: MethodCall, result: Result) {
        if (call.method in REQUIRES_INITIALIZATION && !Stay22.isInitialized) {
            result.error(
                "not_initialized",
                "Stay22 is not initialized. Declare $MANIFEST_AID_KEY in " +
                    "AndroidManifest.xml or call Stay22.initialize(aid:) first.",
                null,
            )
            return
        }
        when (call.method) {
            "initialize" -> handle(result) {
                if (Stay22.isInitialized) return@handle null
                val application = context.applicationContext as? Application
                    ?: throw PluginError(
                        "native_failure",
                        "Stay22 needs an Application context to initialize.",
                    )
                Stay22.initialize(application, call.requireString("aid"))
                // The SDK only learns the current Activity from an onActivityResumed
                // it observes *after* this call registers its lifecycle callbacks. A
                // single-Activity Flutter app resumes once, at launch, so initializing
                // this late leaves the SDK with no Activity to show the notification
                // permission prompt from, for the rest of the session. Declaring the
                // partner ID in the manifest initializes early enough to avoid it.
                if (activityBinding != null) {
                    Log.w(
                        TAG,
                        "Stay22 was initialized from Dart, after the host Activity resumed. " +
                            "requestNotificationPermission() may not be able to show a prompt " +
                            "in this session. Declare $MANIFEST_AID_KEY in AndroidManifest.xml " +
                            "to initialize during app launch instead.",
                    )
                }
                null
            }

            "isInitialized" -> handle(result) { Stay22.isInitialized }

            "setEnabled" -> handle(result) {
                Stay22.isEnabled = call.requireBoolean("enabled")
                null
            }

            "isEnabled" -> handle(result) { Stay22.isEnabled }

            "setMedium" -> handle(result) {
                Stay22.medium = call.requireString("medium")
                null
            }

            "setCampaignId" -> handle(result) {
                Stay22.campaignId = call.optionalString("campaignId")
                null
            }

            "hasNotificationPermission" -> handle(result) { Stay22.hasNotificationPermission() }

            // The callback overload, not the synchronous one: the synchronous
            // version answers with the state from *before* the prompt, which is
            // never what a caller awaiting a Future means. The not-initialized
            // case is already handled above, before this `when` runs.
            "requestNotificationPermission" -> {
                if (activityBinding == null) {
                    result.error(
                        "no_activity",
                        "No Activity is attached, so the notification permission prompt " +
                            "cannot be shown. Request permission from a running UI.",
                        null,
                    )
                    return
                }
                // The SDK guarantees exactly-once delivery on the main thread, but a
                // second result.success would tear down the engine, so guard anyway.
                val delivered = java.util.concurrent.atomic.AtomicBoolean(false)
                Stay22.requestNotificationPermission { granted ->
                    if (delivered.compareAndSet(false, true)) result.success(granted)
                }
            }

            "setTravelContext" -> handle(result) {
                Stay22.setTravelContext(
                    TravelContext(
                        address = call.optionalString("address"),
                        latitude = call.optionalDouble("latitude"),
                        longitude = call.optionalDouble("longitude"),
                        checkinDate = call.optionalString("checkinDate"),
                        checkoutDate = call.optionalString("checkoutDate"),
                        hotelName = call.optionalString("hotelName"),
                        adults = call.optionalInt("adults"),
                        children = call.optionalInt("children"),
                    ),
                )
                null
            }

            "clearTravelContext" -> handle(result) {
                Stay22.clearTravelContext()
                null
            }

            "setNotificationConfig" -> handle(result) {
                Stay22.notificationConfig = call.toNotificationConfig()
                null
            }

            // Android has no shared notification delegate, so nothing can take it away.
            "ownsNotificationDelegate" -> handle(result) { true }

            "scheduleNotification" -> handle(result) {
                Stay22.advanced.scheduleNotification(call.optionalBoolean("force") ?: false)
                null
            }

            "setForce" -> handle(result) {
                Stay22.testing.force = call.requireBoolean("enabled")
                null
            }

            "setShowLogs" -> handle(result) {
                Stay22.testing.showLogs = call.requireBoolean("enabled")
                null
            }

            "setBaseURL" -> handle(result) {
                Stay22.testing.baseURL = call.requireString("url")
                null
            }

            "runDiagnostics" -> handle(result) { Stay22.diagnostics.run().toMap() }

            "logDiagnosticsReport" -> handle(result) { Stay22.diagnostics.logReport().toMap() }

            else -> result.notImplemented()
        }
    }

    private inline fun handle(result: Result, block: () -> Any?) {
        try {
            result.success(block())
        } catch (error: PluginError) {
            result.error(error.code, error.message, null)
        } catch (error: IllegalStateException) {
            result.error("not_initialized", error.message, null)
        } catch (error: IllegalArgumentException) {
            result.error("invalid_argument", error.message, null)
        } catch (error: Throwable) {
            result.error("native_failure", error.message ?: "Unexpected native failure.", null)
        }
    }

    // --- Marshalling ---

    private fun MethodCall.toNotificationConfig(): NotificationConfig {
        // Read the SDK's own defaults off a throwaway instance rather than
        // repeating the literals here, where they would quietly go stale.
        val defaults = NotificationConfig()

        return NotificationConfig(
            title = optionalString("title") ?: defaults.title,
            subtitle = optionalString("subtitle"),
            message = optionalString("message") ?: defaults.message,
            categoryId = requireNonBlankOr("categoryId", defaults.categoryId),
            threadId = requireNonBlankOr("threadId", defaults.threadId),
            badge = optionalInt("badge"),
            launchImageName = optionalString("launchImageName"),
            targetContentIdentifier = optionalString("targetContentIdentifier"),
            interruptionLevel = optionalString("interruptionLevel")?.let { raw ->
                NotificationInterruptionLevel.entries.find { it.name == raw }
                    ?: throw PluginError(
                        "invalid_argument",
                        "interruptionLevel must be one of passive, active, timeSensitive.",
                    )
            },
            relevanceScore = optionalDouble("relevanceScore"),
            attachments = optionalList("attachments").mapIndexed { index, entry ->
                val fileUrl = entry.requireNonBlankAt("fileURL", "attachments[$index]")
                val identifier = entry.optionalStringAt("identifier")
                // Accept both a file:// URL and a bare filesystem path; a bare
                // path parsed as a URI would otherwise yield a scheme-less
                // relative reference that resolves to nothing.
                val uri = if (fileUrl.contains("://")) Uri.parse(fileUrl) else Uri.fromFile(java.io.File(fileUrl))
                if (identifier == null) {
                    NotificationAttachment(fileURL = uri)
                } else {
                    NotificationAttachment(identifier = identifier, fileURL = uri)
                }
            },
            actions = optionalList("actions").mapIndexed { index, entry ->
                NotificationAction(
                    identifier = entry.requireNonBlankAt("identifier", "actions[$index]"),
                    title = entry.requireNonBlankAt("title", "actions[$index]"),
                    foreground = entry.optionalBooleanAt("foreground") ?: true,
                    authenticationRequired = entry.optionalBooleanAt("authenticationRequired") ?: false,
                    destructive = entry.optionalBooleanAt("destructive") ?: false,
                )
            },
        )
    }

    private fun Stay22Event.toMap(): Map<String, Any?> = when (this) {
        is Stay22Event.LocationUpdated ->
            mapOf("type" to "locationUpdated", "destination" to destination)
        is Stay22Event.NotificationScheduled ->
            // Seconds, matching the native type. Do not convert.
            mapOf("type" to "notificationScheduled", "destination" to destination, "delay" to delay)
        is Stay22Event.NotificationShown ->
            mapOf("type" to "notificationShown", "destination" to destination)
        is Stay22Event.NotificationClicked ->
            mapOf("type" to "notificationClicked", "destination" to destination, "url" to url)
        is Stay22Event.NotificationBlocked ->
            mapOf("type" to "notificationBlocked", "reason" to reason)
        is Stay22Event.NotificationSkipped ->
            mapOf("type" to "notificationSkipped", "reason" to reason)
        is Stay22Event.NotificationCancelled ->
            mapOf("type" to "notificationCancelled", "reason" to reason)
        is Stay22Event.EnabledChanged ->
            mapOf("type" to "enabledChanged", "isEnabled" to isEnabled)
        is Stay22Event.TravelContextCleared ->
            mapOf("type" to "travelContextCleared")
    }

    private fun Stay22Diagnostics.toMap(): Map<String, Any?> = mapOf(
        "sdkVersion" to sdkVersion,
        "describe" to describe(),
        "checks" to checks.map {
            mapOf("name" to it.name, "status" to it.status.name, "detail" to it.detail)
        },
    )

    // --- Typed argument accessors ---
    //
    // Each returns null for missing-or-null and throws on a type mismatch, so a
    // wrong-typed argument is reported rather than silently dropped.

    private fun MethodCall.raw(key: String): Any? = (arguments as? Map<*, *>)?.get(key)

    private fun MethodCall.optionalString(key: String): String? {
        val value = raw(key) ?: return null
        val string = value as? String
            ?: throw PluginError("invalid_argument", "Argument '$key' must be a string.")
        return string.trim().ifEmpty { null }
    }

    private fun MethodCall.requireString(key: String): String =
        optionalString(key)
            ?: throw PluginError("missing_argument", "Missing required argument '$key'.")

    private fun MethodCall.requireNonBlankOr(key: String, fallback: String): String {
        val value = raw(key) ?: return fallback
        val string = (value as? String)
            ?: throw PluginError("invalid_argument", "Argument '$key' must be a string.")
        return string.trim().ifEmpty {
            throw PluginError("invalid_argument", "Argument '$key' must not be blank when provided.")
        }
    }

    private fun MethodCall.optionalBoolean(key: String): Boolean? {
        val value = raw(key) ?: return null
        return value as? Boolean
            ?: throw PluginError("invalid_argument", "Argument '$key' must be a boolean.")
    }

    private fun MethodCall.requireBoolean(key: String): Boolean =
        optionalBoolean(key)
            ?: throw PluginError("missing_argument", "Missing required argument '$key'.")

    private fun MethodCall.optionalDouble(key: String): Double? {
        val value = raw(key) ?: return null
        return (value as? Number)?.toDouble()
            ?: throw PluginError("invalid_argument", "Argument '$key' must be numeric.")
    }

    private fun MethodCall.optionalInt(key: String): Int? = optionalDouble(key)?.toInt()

    private fun MethodCall.optionalList(key: String): List<Map<*, *>> {
        val value = raw(key) ?: return emptyList()
        val list = value as? List<*>
            ?: throw PluginError("invalid_argument", "Argument '$key' must be a list.")
        return list.mapIndexed { index, entry ->
            entry as? Map<*, *>
                ?: throw PluginError("invalid_argument", "Argument '$key[$index]' must be an object.")
        }
    }

    private fun Map<*, *>.optionalStringAt(key: String): String? =
        (get(key) as? String)?.trim()?.ifEmpty { null }

    private fun Map<*, *>.requireNonBlankAt(key: String, owner: String): String =
        optionalStringAt(key)
            ?: throw PluginError(
                "invalid_argument",
                "$owner requires '$key' to be a non-empty string.",
            )

    private fun Map<*, *>.optionalBooleanAt(key: String): Boolean? = get(key) as? Boolean

    private class PluginError(
        val code: String,
        override val message: String,
    ) : RuntimeException(message)

    private companion object {
        const val TAG = "Stay22Flutter"
        const val CHANNEL_METHOD = "com.stay22/method"
        const val CHANNEL_EVENTS = "com.stay22/events"
        const val MANIFEST_AID_KEY = "com.stay22.sdk.PartnerAID"

        /** Deep enough for a cold-start replay, shallow enough to never be a leak. */
        const val MAX_BUFFERED_EVENTS = 32

        /**
         * Calls that no-op on the native SDK before `initialize()` instead of doing
         * anything observable — the exact set matters, so record why each side sits
         * where it does rather than gating everything that touches `Stay22`.
         *
         * Exempt on purpose, and matched by an identical exemption on iOS
         * (`cross-platform-parity`): `initialize`/`isInitialized` (that is what they
         * answer), `setEnabled`/`isEnabled`/`setMedium`/`setCampaignId`/
         * `setNotificationConfig` (the SDK docs promise these work before or after
         * `initialize`, e.g. to gate behind a consent screen), `ownsNotificationDelegate`
         * (Android has no shared delegate to own), `runDiagnostics`/
         * `logDiagnosticsReport` (diagnostics is documented safe at any time, and a
         * real test asserts running it before `initialize` is how you learn `initialize`
         * was never called), and `setForce`/`setShowLogs`/`setBaseURL` (testing
         * switches with no native guard on either platform).
         *
         * Everything else here silently discarded the call and reported success:
         * `setTravelContext`/`clearTravelContext`/`scheduleNotification` returned null,
         * and `hasNotificationPermission` returned false indistinguishable from "denied".
         * `requestNotificationPermission` already raised `not_initialized` by hand, one
         * idiom ahead of the rest — folded into this shared list instead.
         */
        val REQUIRES_INITIALIZATION = setOf(
            "hasNotificationPermission",
            "requestNotificationPermission",
            "setTravelContext",
            "clearTravelContext",
            "scheduleNotification",
        )
    }
}
