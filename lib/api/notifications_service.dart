import 'api_client.dart';

/// The screen a tapped notification row opens. The screen itself resolves
/// the comment to land on from the notice's own ids.
enum NotificationTarget { none, profile, post, comments, thread }

/// One notification bundle from GET /api/v1/notifications?list=1.
/// Post likes/comments group per (type, post) with the newest actor +
/// distinct actor count ("Alice & 3 others liked your post"); every other
/// type stands alone. `read` is the bundle's min_read; `other` carries
/// extras; post-attached types carry the post's text + image preview.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.message,
    required this.contentType,
    required this.contentId,
    required this.commentId,
    required this.isDomain,
    required this.fromUserId,
    required this.fromUsername,
    required this.fromUserAvatar,
    required this.actorCount,
    required this.read,
    required this.createdAt,
    required this.other,
    required this.postPreviewContent,
    required this.postPreviewImage,
  });

  final int id; // bundle id (the newest notification row in the group)
  final String message; // e.g. "Alice & 3 others liked your post"
  final String contentType; // post-like | post-comment | comment-mention | follow | user-management | ...
  final int contentId; // post id for post-attached types, else 0

  /// The comment this notice is about (0 for a like / follow). A bundle's
  /// row is its NEWEST one, so a bundled "X & 6 others commented" points at
  /// the LAST comment - which is where a tap should land.
  final int commentId;

  /// The post lives in a forum thread: taps open the thread, not the
  /// feed-style comments.
  final bool isDomain;
  final int fromUserId;
  final String fromUsername;
  final String fromUserAvatar; // root-relative ("/public/avatars/...")
  final int actorCount;
  final bool read;
  final String createdAt; // DB UTC wall-clock 'YYYY-MM-DD HH:MM:SS'
  final String other;
  final String postPreviewContent; // htmlspecialchars-encoded; decode once
  final String postPreviewImage; // BARE gallery filename

  /// Post-attached types deep-link to the post; the rest stand alone.
  /// comment-reply and post-activity carry the post id too, so they group
  /// and tap like the others (the server sends one notice per comment at
  /// most).
  bool get isPostAttached =>
      contentType == 'post-like' ||
      contentType == 'post-comment' ||
      contentType == 'post-activity' ||
      contentType == 'comment-reply' ||
      contentType == 'comment-mention';

  /// Whether the notice can be opened ON a comment; a like cannot.
  bool get hasComment => commentId > 0;

  /// Where a tap on this row lands. A comment notice opens the comments
  /// (feed post) or the thread (domain post) ON the comment; a like stops
  /// at the post; anything else the drawer does not route.
  NotificationTarget get tapTarget {
    if (contentType == 'follow') return NotificationTarget.profile;
    if (!isPostAttached) return NotificationTarget.none;
    if (isDomain) return NotificationTarget.thread;
    return hasComment ? NotificationTarget.comments : NotificationTarget.post;
  }

  /// Maps to the Android notification id: the POST id for post-attached
  /// types (a new like on the same post REPLACES the older notification),
  /// the bundle id for standalone types.
  int get groupId => isPostAttached && contentId > 0 ? contentId : id;

  /// Absolute avatar URL (server sends root-relative paths).
  String avatarUrl(String base) => fromUserAvatar.startsWith('/')
      ? '$base$fromUserAvatar'
      : fromUserAvatar;

  /// Absolute gallery image URL. Preview images are BARE filenames -
  /// rendered under /public/gallery/. Null when the post has no image.
  String? previewImageUrl(String base) =>
      postPreviewImage.isEmpty ? null : '$base/public/gallery/$postPreviewImage';

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    final preview = json['post_preview'];
    final previewMap =
        preview is Map<String, dynamic> ? preview : const <String, dynamic>{};
    return AppNotification(
      id: (json['id'] as num?)?.toInt() ?? 0,
      message: json['message'] as String? ?? '',
      contentType: json['content_type'] as String? ?? '',
      contentId: (json['content_id'] as num?)?.toInt() ?? 0,
      commentId: (json['comment_id'] as num?)?.toInt() ?? 0,
      isDomain: json['is_domain'] as bool? ?? false,
      fromUserId: (json['from_user_id'] as num?)?.toInt() ?? 0,
      fromUsername: json['from_username'] as String? ?? '',
      fromUserAvatar: json['from_user_avatar'] as String? ??
          '/assets/default-avatar.png',
      actorCount: (json['actor_count'] as num?)?.toInt() ?? 1,
      read: json['read'] as bool? ?? false,
      createdAt: json['created_at'] as String? ?? '',
      other: json['other'] as String? ?? '',
      postPreviewContent: previewMap['content'] as String? ?? '',
      postPreviewImage: previewMap['image_url'] as String? ?? '',
    );
  }
}

/// One page of notification bundles, newest first. [lastId] is the page's
/// oldest bundle id - the next page's `before_id`. [hasMore] is false once
/// the server runs out (an older server that predates paging sends neither
/// field, so the list simply stops at the first page).
class NotificationPage {
  const NotificationPage({
    required this.items,
    this.hasMore = false,
    this.lastId = 0,
  });

  final List<AppNotification> items;
  final bool hasMore;
  final int lastId;
}

/// The notification drawer over api/v1: GET ?list=1 -> {notifications
/// (paged, read = min_read), has_more, last_id, csrf_token}; GET ->
/// {unread_count} (guests: 0); POST {action:'mark_all_read'} (JSON +
/// CSRF). The list endpoint is READ-ONLY - the user-facing app marks
/// read, never the worker.
class NotificationsService {
  NotificationsService(this._api);

  final ApiClient _api;

  /// The newest bundles the device alerts on (the live ping + background
  /// worker path): 5 is the alert budget - a burst of OS notifications is
  /// not a list. The drawer pages itself with [fetch].
  Future<List<AppNotification>> list({int limit = 5}) async =>
      (await fetch(limit: limit)).items;

  /// One page of bundles, newest first. [beforeId] walks BACKWARDS: pass
  /// the previous page's [NotificationPage.lastId] for the next 20.
  Future<NotificationPage> fetch({int beforeId = 0, int limit = 20}) async {
    final query = <String, String>{'list': '1', 'limit': '$limit'};
    if (beforeId > 0) query['before_id'] = '$beforeId';
    final json = await _api.getJson('/api/v1/notifications', query: query);
    final raw = json['notifications'] as List<dynamic>? ?? const [];
    final items = [
      for (final n in raw)
        if (n is Map<String, dynamic>) AppNotification.fromJson(n),
    ];
    final hasMoreFlag = json['has_more'];
    return NotificationPage(
      items: items,
      hasMore: hasMoreFlag == true || hasMoreFlag == 1,
      lastId: (json['last_id'] as num?)?.toInt() ??
          (items.isEmpty ? 0 : items.last.id),
    );
  }

  /// Total unread notifications (the header badge count).
  Future<int> unreadCount() async {
    final json = await _api.getJson('/api/v1/notifications');
    return (json['unread_count'] as num?)?.toInt() ?? 0;
  }

  /// Marks every notification read (the site does this the moment the
  /// dropdown opens).
  Future<void> markAllRead() async {
    await _api.postJson('/api/v1/notifications', {'action': 'mark_all_read'});
  }

  /// Marks the given BUNDLES read - the tray-swipe path: an alert the user
  /// cleared must not sit unread in the drawer. The ids are the bundle ids
  /// [list] reports; the server resolves each one back to its group, so a
  /// post's bundled likes/comments clear together. Returns the fresh unread
  /// count (null when nothing was sent).
  Future<int?> markRead(List<int> ids) async {
    if (ids.isEmpty) return null;
    final json = await _api.postJson('/api/v1/notifications', <String, dynamic>{
      'action': 'mark_read',
      'ids': ids,
    });
    return (json['unread_count'] as num?)?.toInt();
  }
}
