import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../api/notifications_service.dart';

/// "Swiped away counts as read": turns a dismissed tray notification back
/// into the alert it announced and marks that alert read.
///
/// The plugin reports a swipe on a BACKGROUND isolate (AndroidNotificationDetails
/// .dismissIsolate), because clearing the tray has to work with the app
/// terminated - there are no live services there, so this builds its own
/// client from prefs exactly like the drawer-reply path.
///
/// Payload contract (the notification's own payload):
///   'n:<bundle id>' - a social alert. The id is the bundle from
///                     GET ?list=1, which the server resolves back to its
///                     group (a post's bundled likes/comments clear
///                     together). Marked read.
///   'c:<conversation id>' - a message. Swiping one away is NOT a read
///                     receipt for the conversation, so nothing is marked:
///                     the sender must not see "seen" for a DM the user
///                     never opened.
///   anything else - ignored.
class DismissedNotifications {
  DismissedNotifications._();

  /// Prefix of a social alert's payload (see SocialNotificationSource).
  static const String socialPrefix = 'n:';

  /// The bundle id inside a notification payload, or null when the payload
  /// is not a social alert (messages and unknown payloads are not ours).
  static int? bundleIdFromPayload(String? payload) {
    if (payload == null || !payload.startsWith(socialPrefix)) return null;
    final id = int.tryParse(payload.substring(socialPrefix.length));
    return (id != null && id > 0) ? id : null;
  }

  /// Marks the dismissed alert read. Never throws: a swipe must not be
  /// able to kill the background isolate.
  static Future<void> markRead(String? payload, {ApiClient? api}) async {
    final bundleId = bundleIdFromPayload(payload);
    if (bundleId == null) return;
    try {
      var client = api;
      if (client == null) {
        final prefs = await SharedPreferences.getInstance();
        client = ApiClient(store: PrefsSessionStore(prefs));
        await client.restoreSession();
        if (!client.hasSession) {
          debugPrint('dismissed: no session, nothing marked');
          return;
        }
      }
      await NotificationsService(client).markRead(<int>[bundleId]);
    } catch (e) {
      // Offline, or a server without mark_read yet: the alert just stays
      // unread and the next swipe/refresh can settle it.
      debugPrint('dismissed: mark read failed: $e');
    }
  }
}
