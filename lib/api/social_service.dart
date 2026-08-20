import 'api_client.dart';

/// Result of a like toggle (POST /api/v1/likes).
class LikeResult {
  const LikeResult({required this.action, required this.likeCount});

  final String action; // 'liked' | 'unliked'
  final int likeCount;

  bool get liked => action == 'liked';

  factory LikeResult.fromJson(Map<String, dynamic> json) => LikeResult(
        action: json['action'] as String? ?? 'liked',
        likeCount: (json['like_count'] as num?)?.toInt() ?? 0,
      );
}

/// A single comment from GET/POST /api/v1/comments.
/// Field contract (comments.php api_comment_item): id, post_id, user_id,
/// username, profile_picture_url, personality_type, name_color,
/// warning_count, has_warnings, created_at (ALREADY relative-formatted by
/// format_date — 'now', '5m', '3h'...), edited, content, is_owner,
/// can_moderate.
class Comment {
  const Comment({
    required this.id,
    required this.postId,
    required this.userId,
    required this.username,
    required this.profilePictureUrl,
    required this.personalityType,
    required this.nameColor,
    required this.hasWarnings,
    required this.createdAt,
    required this.content,
    required this.isOwner,
  });

  final int id;
  final int postId;
  final int userId;
  final String username;
  final String profilePictureUrl;
  final String? personalityType;
  final String nameColor;
  final bool hasWarnings;
  final String createdAt; // relative string, server-formatted
  final String content;
  final bool isOwner;

  factory Comment.fromJson(Map<String, dynamic> json) => Comment(
        id: (json['id'] as num?)?.toInt() ?? 0,
        postId: (json['post_id'] as num?)?.toInt() ?? 0,
        userId: (json['user_id'] as num?)?.toInt() ?? 0,
        username: json['username'] as String? ?? '',
        profilePictureUrl: json['profile_picture_url'] as String? ??
            '/assets/default-avatar.png',
        personalityType: json['personality_type'] as String?,
        nameColor: json['name_color'] as String? ?? 'text-gray-400',
        hasWarnings: json['has_warnings'] as bool? ?? false,
        createdAt: json['created_at'] as String? ?? '',
        content: json['content'] as String? ?? '',
        isOwner: json['is_owner'] as bool? ?? false,
      );
}

/// A user who liked a post (GET /api/v1/likes?post_id=N).
///
/// Field contract (likes.php GET): id, username, profile_picture_url,
/// personality_type, rank, personality_badge (HTML — unused here),
/// liked_at (server-formatted "August 12, 2026 at 10:32 AM"),
/// rank_styles (HTML — unused here).
class Liker {
  const Liker({
    required this.id,
    required this.username,
    required this.profilePictureUrl,
    required this.personalityType,
    required this.rank,
    required this.likedAt,
  });

  final int id;
  final String username;
  final String profilePictureUrl;
  final String? personalityType;
  final String rank;
  final String likedAt;

  factory Liker.fromJson(Map<String, dynamic> json) => Liker(
        id: (json['id'] as num?)?.toInt() ?? 0,
        username: json['username'] as String? ?? '',
        profilePictureUrl: json['profile_picture_url'] as String? ??
            '/assets/default-avatar.png',
        personalityType: json['personality_type'] as String?,
        rank: json['rank'] as String? ?? 'Member',
        likedAt: json['liked_at'] as String? ?? '',
      );
}

/// SocialService — likes + comments over api/v1 (JSON + CSRF).
///
/// Contracts (both verified against the live handlers):
///   POST /api/v1/likes    {post_id}       → {success, action: liked|unliked,
///                                            like_count}
///   GET  /api/v1/comments ?post_id=N      → {success, comments:[...], total}
///   POST /api/v1/comments {action:create, post_id, content}
///                                           → {success, comment:{...},
///                                              comment_count}
///   POST /api/v1/comments {action:delete, comment_id, post_id}
///                                           → {success, comment_count}
class SocialService {
  SocialService(this._api);

  final ApiClient _api;

  /// Toggles a like on a post. Returns the server's authoritative state.
  Future<LikeResult> toggleLike(int postId) async {
    final json = await _api.postJson('/api/v1/likes', {'post_id': postId});
    return LikeResult.fromJson(json);
  }

  /// The users who liked a post, newest first (likes.php GET — public).
  Future<List<Liker>> likers(int postId) async {
    final json =
        await _api.getJson('/api/v1/likes', query: {'post_id': '$postId'});
    final raw = json['likers'] as List<dynamic>? ?? const [];
    return [
      for (final l in raw)
        if (l is Map<String, dynamic>) Liker.fromJson(l),
    ];
  }

  /// Fetches the comment list for a post (newest first — server sorts
  /// created_at DESC).
  Future<List<Comment>> listComments(int postId) async {
    final json =
        await _api.getJson('/api/v1/comments', query: {'post_id': '$postId'});
    final raw = json['comments'] as List<dynamic>? ?? const [];
    return [
      for (final c in raw)
        if (c is Map<String, dynamic>) Comment.fromJson(c),
    ];
  }

  /// Creates a comment. Returns the created comment + the new total.
  Future<(Comment, int)> createComment(int postId, String content) async {
    final json = await _api.postJson('/api/v1/comments', {
      'action': 'create',
      'post_id': postId,
      'content': content,
    });
    final rawComment = json['comment'];
    if (rawComment is! Map<String, dynamic>) {
      throw const ApiException('Invalid comment response');
    }
    return (
      Comment.fromJson(rawComment),
      (json['comment_count'] as num?)?.toInt() ?? 0,
    );
  }

  /// Deletes a comment (owner or moderator). Returns the new total.
  Future<int> deleteComment(int commentId, int postId) async {
    final json = await _api.postJson('/api/v1/comments', {
      'action': 'delete',
      'comment_id': commentId,
      'post_id': postId,
    });
    return (json['comment_count'] as num?)?.toInt() ?? 0;
  }
}
