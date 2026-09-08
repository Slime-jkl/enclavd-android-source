import 'api_client.dart';
import 'feed_service.dart';
import 'profile_service.dart';
import '../utils/html_entities.dart';

/// The kinds of interaction the Activity tab shows.
enum ActivityType {
  like('like'),
  comment('comment'),
  follow('follow');

  const ActivityType(this.wire);

  /// The api/v1/activity wire value.
  final String wire;

  static ActivityType fromWire(String? wire) {
    for (final t in values) {
      if (t.wire == wire) return t;
    }
    return ActivityType.like; // unknown rows default to the post opener
  }
}

/// One entry in the viewer's activity feed (GET /api/v1/activity) - a
/// merged, newest-first stream of their own likes, comments and follows.
///
/// like/comment items carry the affected post (same shape as the feed);
/// comment items add the comment text. follow items carry the followed
/// member as a profile-list user row (FollowListItem shape).
class ActivityItem {
  const ActivityItem({
    required this.type,
    required this.id,
    required this.createdAt,
    this.post,
    this.commentContent,
    this.parentCommentId,
    this.user,
  });

  final ActivityType type;

  /// Source row id: the like/comment id, or the followee's account id
  /// for follow rows (the follow table has no id of its own).
  final int id;

  /// DB UTC wall-clock time of the interaction.
  final String createdAt;

  /// The post that was liked or commented on (null for follow rows).
  final Post? post;

  /// The viewer's comment text (comment rows only; entity-decoded).
  final String? commentContent;

  /// Reply target id of the comment, null when it is a top-level comment.
  final int? parentCommentId;

  /// The followed member (follow rows only).
  final FollowListItem? user;

  bool get opensPost => type != ActivityType.follow && post != null;

  factory ActivityItem.fromJson(Map<String, dynamic> json) {
    final type = ActivityType.fromWire(json['type'] as String?);
    final postRaw = json['post'];
    final userRaw = json['user'];
    final content = json['content'] as String?;
    return ActivityItem(
      type: type,
      id: (json['id'] as num?)?.toInt() ?? 0,
      createdAt: json['created_at'] as String? ?? '',
      post: postRaw is Map<String, dynamic> ? Post.fromJson(postRaw) : null,
      commentContent:
          content == null ? null : decodeHtmlEntities(content),
      parentCommentId: (json['parent_comment_id'] as num?)?.toInt(),
      user:
          userRaw is Map<String, dynamic> ? FollowListItem.fromJson(userRaw) : null,
    );
  }
}

/// One page of the activity feed.
class ActivityPage {
  const ActivityPage({required this.items, required this.hasMore});

  final List<ActivityItem> items;
  final bool hasMore;
}

/// The viewer's own interaction history over api/v1 (GET /api/v1/activity).
/// No user_id param exists: the endpoint always returns the signed-in
/// user's activity, so this is only reachable from the own profile.
class ActivityService {
  ActivityService(this._api);

  final ApiClient _api;

  /// One page of the merged feed, newest interaction first (offset
  /// pagination; the server caps limit at 50).
  Future<ActivityPage> fetch({int limit = 20, int offset = 0}) async {
    final json = await _api.getJson('/api/v1/activity', query: {
      'limit': '$limit',
      'offset': '$offset',
    });
    final raw = json['activity'] as List<dynamic>? ?? const [];
    return ActivityPage(
      items: [
        for (final a in raw)
          if (a is Map<String, dynamic>) ActivityItem.fromJson(a),
      ],
      hasMore: json['has_more'] as bool? ?? false,
    );
  }
}
