import 'api_client.dart';

/// Result of a like toggle (POST /api/v1/likes).
class LikeResult {
  const LikeResult({required this.action, required this.likeCount});

  final String action; // liked / unliked
  final int likeCount;

  bool get liked => action == 'liked';

  factory LikeResult.fromJson(Map<String, dynamic> json) => LikeResult(
        action: json['action'] as String? ?? 'liked',
        likeCount: (json['like_count'] as num?)?.toInt() ?? 0,
      );
}

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
    this.parentCommentId,
    this.rank = '',
    this.createdAtUtc = '',
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

  /// Reply target id (null = top-level comment). The API emits it for
  /// every item; the server also validates it on create.
  final int? parentCommentId;

  /// raw db time falls back to the server's relative string if created_at_utc missing
  final String createdAtUtc;
  final String rank;

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
        createdAtUtc: (json['created_at_utc'] as String?)?.isNotEmpty == true
            ? json['created_at_utc'] as String
            : json['created_at'] as String? ?? '',
        content: json['content'] as String? ?? '',
        isOwner: json['is_owner'] as bool? ?? false,
        parentCommentId: (json['parent_comment_id'] as num?)?.toInt(),
        rank: (json['rank'] as String?)?.isNotEmpty == true
            ? json['rank'] as String
            : _rankFromNameColor(json['name_color'] as String? ?? ''),
      );
}

/// Reverse of the server's name_color -> rank (the comments API only sent
/// the CSS class until it shipped the raw rank; unknown classes ->
/// Member). Mirrors rankColorFromCssClass in post_card.dart.
String _rankFromNameColor(String cssClass) {
  if (cssClass.contains('purple')) return 'SysOp';
  if (cssClass.contains('red')) return 'Admin';
  if (cssClass.contains('blue')) return 'Officer';
  if (cssClass.contains('yellow')) return 'Founding Member';
  if (cssClass.contains('white')) return 'Labcoat';
  if (cssClass.contains('neutral')) return 'Blocked';
  return 'Member';
}

/// A user who liked a post (GET /api/v1/likes?post_id=N). liked_at is
/// server-formatted ("August 12, 2026 at 10:32 AM").
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

  /// Prod's likers payload predates the raw fields: it sends
  /// `personality_badge` / `rank_styles` as HTML instead of plain
  /// `personality_type` / `rank`. Parse the HTML as a fallback so the
  /// modal colors/pills/badges work against BOTH payload shapes.
  factory Liker.fromJson(Map<String, dynamic> json) {
    final styles = json['rank_styles'];
    final stylesMap =
        styles is Map<String, dynamic> ? styles : const <String, dynamic>{};
    final personalityBadge = json['personality_badge'] as String? ?? '';
    final rankBadge = stylesMap['badge'] as String? ?? '';
    return Liker(
      id: (json['id'] as num?)?.toInt() ?? 0,
      username: json['username'] as String? ?? '',
      profilePictureUrl: json['profile_picture_url'] as String? ??
          '/assets/default-avatar.png',
      personalityType: (json['personality_type'] as String?) ??
          _mbtiFromBadge(personalityBadge),
      rank:
          (json['rank'] as String?) ?? _rankFromBadge(rankBadge) ?? 'Member',
      likedAt: json['liked_at'] as String? ?? '',
    );
  }

  /// `<span ...>INTJ</span>` -> `INTJ` (personality_badge HTML).
  static String? _mbtiFromBadge(String html) {
    if (html.isEmpty) return null;
    final m = RegExp(r'>\s*([A-Z]{4})\s*<').firstMatch(html);
    return m?.group(1);
  }

  /// `<a ...><i ...></i>SysOp</a>` -> `SysOp` (rank_styles.badge HTML).
  static String? _rankFromBadge(String html) {
    if (html.isEmpty) return null;
    final m = RegExp(r'>([^<>]+)</a>').firstMatch(html);
    if (m == null) return null;
    final name = m.group(1)!.trim();
    return name.isEmpty ? null : name;
  }
}

/// One page of comments (GET /api/v1/comments with &limit=&offset=).
/// [total] is the post's FULL comment count (not the page size) and
/// [hasMore] tells the caller whether another page exists.
class CommentPage {
  const CommentPage({
    required this.comments,
    required this.total,
    required this.hasMore,
  });

  final List<Comment> comments;
  final int total;
  final bool hasMore;

  factory CommentPage.fromJson(Map<String, dynamic> json) {
    final raw = json['comments'] as List<dynamic>? ?? const [];
    return CommentPage(
      comments: [
        for (final c in raw)
          if (c is Map<String, dynamic>) Comment.fromJson(c),
      ],
      total: (json['total'] as num?)?.toInt() ?? raw.length,
      hasMore: json['has_more'] as bool? ?? false,
    );
  }
}

/// Depth-1 display tree over a flat comment list (mirrors the site's
/// load.php renderer). Every comment whose ancestor chain resolves to a
/// top-level comment renders under that root; deeper replies collapse
/// into the same group while [parentUsernames] keeps the direct target
/// for "Replying to @user" hints. Comments whose parent is missing from
/// the loaded window (pagination) fall back to root level.
class CommentTree {
  CommentTree({
    required this.roots,
    required this.children,
    required this.rootOf,
    required this.parentUsernames,
  });

  final List<Comment> roots; // display order preserved from the source list
  final Map<int, List<Comment>> children; // rootId -> clamped replies, oldest first
  final Map<int, int> rootOf; // commentId -> rootId (id itself for roots)
  final Map<int, String> parentUsernames; // commentId -> direct parent's name

  factory CommentTree.build(List<Comment> comments) {
    final byId = {for (final c in comments) c.id: c};
    final rootOf = <int, int>{};
    final parentUsernames = <int, String>{};

    for (final c in comments) {
      var cur = c;
      var guard = 0;
      while (cur.parentCommentId != null && byId.containsKey(cur.parentCommentId) && guard++ < 50) {
        final parent = byId[cur.parentCommentId!]!;
        parentUsernames.putIfAbsent(c.id, () => parent.username);
        cur = parent;
      }
      // cur is a root, or the chain broke on a missing parent (orphan).
      rootOf[c.id] = cur.parentCommentId == null ? cur.id : 0;
    }

    final children = <int, List<Comment>>{};
    for (final c in comments) {
      final root = rootOf[c.id] ?? 0;
      if (root != 0 && root != c.id) {
        children.putIfAbsent(root, () => []).add(c);
      }
    }
    for (final list in children.values) {
      list.sort((a, b) {
        final byTime = a.createdAtUtc.compareTo(b.createdAtUtc);
        return byTime != 0 ? byTime : a.id.compareTo(b.id);
      });
    }

    return CommentTree(
      roots: [for (final c in comments) if ((rootOf[c.id] ?? 0) == c.id) c],
      children: children,
      rootOf: rootOf,
      parentUsernames: parentUsernames,
    );
  }
}

/// Likes + comments over api/v1 (JSON + CSRF). Contracts:
///   POST /api/v1/likes    {post_id}          -> {action: liked|unliked, like_count}
///   GET  /api/v1/comments ?post_id=N         -> {comments:[...], total}
///        (optional &limit=N&offset=M&order=asc; total stays the FULL count)
///   POST /api/v1/comments {action:create, post_id, content,
///        parent_comment_id?} -> {comment, comment_count}
///   POST /api/v1/comments {action:delete, comment_id, post_id} -> {comment_count}
///   GET  /api/v1/suggestions -> {suggestions:[...]}
///
/// One follow suggestion: the same cached friend-of-friend list the web
/// sidebar renders (menu_right.php).
class SuggestedUser {
  const SuggestedUser({
    required this.id,
    required this.username,
    required this.profilePictureUrl,
    required this.personalityType,
    required this.rank,
    required this.isActive,
    required this.mutualCount,
    required this.youFollow,
    required this.theyFollow,
  });

  final int id;
  final String username;
  final String profilePictureUrl;
  final String? personalityType;
  final String rank;
  final String isActive;
  final int mutualCount;
  final bool youFollow;
  final bool theyFollow;

  factory SuggestedUser.fromJson(Map<String, dynamic> json) => SuggestedUser(
        id: (json['id'] as num?)?.toInt() ?? 0,
        username: json['username'] as String? ?? '',
        profilePictureUrl: json['profile_picture_url'] as String? ??
            '/assets/default-avatar.png',
        personalityType: json['personality_type'] as String?,
        rank: json['rank'] as String? ?? 'Member',
        isActive: json['is_active'] as String? ?? 'true',
        mutualCount: (json['mutual_count'] as num?)?.toInt() ?? 0,
        youFollow: json['you_follow'] as bool? ?? false,
        theyFollow: json['they_follow'] as bool? ?? false,
      );

  String get followLabel => theyFollow ? 'Follow Back' : 'Follow';
}

class SocialService {
  SocialService(this._api);

  final ApiClient _api;

  /// Comments are fetched 10 at a time in the app (the load-more seam);
  /// the server caps limit at 50 anyway.
  static const int pageSize = 10;

  /// Toggles a like on a post. Returns the server's authoritative state.
  Future<LikeResult> toggleLike(int postId) async {
    final json = await _api.postJson('/api/v1/likes', {'post_id': postId});
    return LikeResult.fromJson(json);
  }

  /// The users who liked a post, newest first (likes.php GET - public).
  Future<List<Liker>> likers(int postId) async {
    final json =
        await _api.getJson('/api/v1/likes', query: {'post_id': '$postId'});
    final raw = json['likers'] as List<dynamic>? ?? const [];
    return [
      for (final l in raw)
        if (l is Map<String, dynamic>) Liker.fromJson(l),
    ];
  }

  /// Follow suggestions for the feed header (GET /api/v1/suggestions).
  /// Server caches the list per user for an hour, same as the web sidebar.
  Future<List<SuggestedUser>> followSuggestions() async {
    final json = await _api.getJson('/api/v1/suggestions');
    final raw = json['suggestions'] as List<dynamic>? ?? const [];
    return [
      for (final s in raw)
        if (s is Map<String, dynamic>) SuggestedUser.fromJson(s),
    ];
  }

  /// One page of comments for a post. Newest first by default (the feed's
  /// inline comments); pass [asc] for forum reading order (the site's
  /// domain thread replies). [limit] defaults to [pageSize] (10); pass
  /// limit 0 for the legacy full list.
  Future<CommentPage> listComments(int postId,
      {bool asc = false, int limit = pageSize, int offset = 0}) async {
    final json = await _api.getJson('/api/v1/comments', query: {
      'post_id': '$postId',
      if (asc) 'order': 'asc',
      if (limit > 0) 'limit': '$limit',
      if (offset > 0) 'offset': '$offset',
    });
    return CommentPage.fromJson(json);
  }

  /// Creates a comment (optionally a reply to [parentCommentId]).
  /// Returns the created comment + the new total.
  Future<(Comment, int)> createComment(int postId, String content,
      {int? parentCommentId}) async {
    final json = await _api.postJson('/api/v1/comments', {
      'action': 'create',
      'post_id': postId,
      'content': content,
      if (parentCommentId != null) 'parent_comment_id': parentCommentId,
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
