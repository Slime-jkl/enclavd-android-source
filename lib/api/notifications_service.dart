import 'api_client.dart';

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
  bool get isPostAttached =>
      contentType == 'post-like' ||
      contentType == 'post-comment' ||
      contentType == 'comment-mention';

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

/// The notification drawer over api/v1: GET ?list=1 -> {notifications
/// (newest 5, read = min_read), csrf_token}; GET -> {unread_count}
/// (guests: 0); POST {action:'mark_all_read'} (JSON + CSRF). The list
/// endpoint is READ-ONLY - the user-facing app marks read, never the
/// worker.
class NotificationsService {
  NotificationsService(this._api);

  final ApiClient _api;

  /// The newest notification bundles (LIMIT 5, per-post grouping).
  Future<List<AppNotification>> list() async {
    final json = await _api.getJson('/api/v1/notifications',
        query: <String, String>{'list': '1'});
    final raw = json['notifications'] as List<dynamic>? ?? const [];
    return [
      for (final n in raw)
        if (n is Map<String, dynamic>) AppNotification.fromJson(n),
    ];
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
}
