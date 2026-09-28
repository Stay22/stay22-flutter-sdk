import Stay22SDK
import UserNotifications

/// Forwarding hooks for apps that own `UNUserNotificationCenter.delegate`.
///
/// **Most apps need none of this.** The SDK installs itself as the notification
/// delegate and chains to whatever was already there, and it re-claims the slot
/// every time the app becomes active. Reach for these only when
/// `Stay22.diagnostics` reports the delegate check as failing.
///
/// They live on the plugin rather than on `Stay22SDK` because the Runner target
/// depends on `stay22_flutter` directly, so `import stay22_flutter` always
/// resolves; `import Stay22SDK` only works when CocoaPods happens to expose the
/// transitive framework search path.
public extension Stay22FlutterPlugin {

    /// Whether Stay22 currently owns `UNUserNotificationCenter.delegate`.
    ///
    /// Guard the two forwarding calls below with this. When Stay22 owns the
    /// delegate it has *already* handled the notification before calling your
    /// method, and handling it again opens the booking page twice and records
    /// two clicks.
    static var ownsNotificationDelegate: Bool {
        Stay22.ownsNotificationDelegate
    }

    /// Hands a notification tap to Stay22.
    ///
    /// - Returns: true when the notification was Stay22's and has been handled.
    ///   Return from your delegate method immediately when true.
    @discardableResult
    static func handleNotificationResponse(_ response: UNNotificationResponse) -> Bool {
        Stay22.handleNotificationResponse(response)
    }

    /// Identifies Stay22 requests, including ones retired after consent or context changed.
    static func isStay22Notification(_ notification: UNNotification) -> Bool {
        Stay22.isStay22Notification(notification)
    }

    /// Tells Stay22 one of its notifications is about to appear while the app is
    /// in the foreground.
    ///
    /// First check `isStay22Notification(_:)`. Present a Stay22 request with
    /// `[.banner, .sound, .list]` only when this method returns true; use `[]`
    /// when it returns false. Retired requests return false in the updated native SDK.
    @discardableResult
    static func handleWillPresentNotification(_ notification: UNNotification) -> Bool {
        Stay22.handleWillPresentNotification(notification)
    }
}
