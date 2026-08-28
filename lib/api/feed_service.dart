import 'api_client.dart';
import '../utils/html_entities.dart';

/// A single post card from GET /api/v1/posts (posts.php $map_post
/// contract: id, author_id, content, created_at, feed_score, like_count,
/// comment_count, user_liked, warning_count, username,
/// profile_picture_url, personality_type, is_active, rank, image).
class Post {
  const Post({
    required this.id,
    this.authorId = 0,
    required this.content,
    required this.createdAt,
    required this.feedScore,
    required this.likeCount,
    required this.commentCount,
    required this.userLiked,
    required this.warningCount,
    required this.username,
    required this.profilePictureUrl,
    required this.personalityType,
    required this.isActive,
    required this.rank,
    required this.image,
    this.isOwner = false,
  });

  final int id;
  final int authorId;
  final String content;
  final String createdAt;
  final double? feedScore;
  final int likeCount;
  final int commentCount;
  final bool userLiked;
  final int warningCount;
  final String username;
  final String profilePictureUrl;
  final String? personalityType;
  final String isActive; // 'true' / 'false' (string from the DB)
  final String rank;
  final String? image; // BARE gallery filename when present
  final bool isOwner;

  factory Post.fromJson(Map<String, dynamic> json) => Post(
        id: (json['id'] as num?)?.toInt() ?? 0,
        authorId: (json['author_id'] as num?)?.toInt() ?? 0,
        // Content arrives htmlspecialchars-encoded (apostrophes are &#039;
        // etc.); decode exactly once so the tokenizer runs on clean text.
        content:
            decodeHtmlEntities(json['content'] as String? ?? ''),
        createdAt: json['created_at'] as String? ?? '',
        feedScore: (json['feed_score'] as num?)?.toDouble(),
        likeCount: (json['like_count'] as num?)?.toInt() ?? 0,
        commentCount: (json['comment_count'] as num?)?.toInt() ?? 0,
        userLiked: json['user_liked'] as bool? ?? false,
        warningCount: (json['warning_count'] as num?)?.toInt() ?? 0,
        username: json['username'] as String? ?? '',
        profilePictureUrl: json['profile_picture_url'] as String? ??
            '/assets/default-avatar.png',
        personalityType: json['personality_type'] as String?,
        isActive: json['is_active'] as String? ?? 'true',
        rank: json['rank'] as String? ?? 'Member',
        image: json['image'] as String?,
        isOwner: json['is_owner'] as bool? ?? false,
      );

  bool get isBlocked => isActive == 'false';
}

/// One page of posts + the keyset cursor for the next page.
///
/// The ranked feed pages on (last_score, last_id); a user's profile posts
/// and a hashtag page page on (last_created_at, last_id) - only one of the
/// two cursors is set. [total] is only populated by the hashtag branch
/// (every post carrying the tag, for the page header count).
class FeedPage {
  const FeedPage({
    required this.posts,
    required this.hasMore,
    required this.lastScore,
    required this.lastId,
    this.lastCreatedAt,
    this.total,
  });

  final List<Post> posts;
  final bool hasMore;
  final double? lastScore;
  final int? lastId;
  final String? lastCreatedAt;
  final int? total;

  bool get isEmpty => posts.isEmpty;

  factory FeedPage.fromJson(Map<String, dynamic> json) {
    final rawPosts = json['posts'] as List<dynamic>? ?? const [];
    return FeedPage(
      posts: [
        for (final p in rawPosts)
          if (p is Map<String, dynamic>) Post.fromJson(p),
      ],
      hasMore: json['has_more'] as bool? ?? false,
      lastScore: (json['last_score'] as num?)?.toDouble(),
      lastId: (json['last_id'] as num?)?.toInt(),
      lastCreatedAt: json['last_created_at'] as String?,
      total: (json['total'] as num?)?.toInt(),
    );
  }
}

/// GET /api/v1/posts with keyset pagination (posts.php contract):
/// ?limit=N (1-50, default 10), ?last_score&last_id (next page),
/// ?after_id=N (delta), ?post_id=N (single). Response: {success, posts,
/// has_more, last_score, last_id}. Guests -> 401; auth = the session
/// cookies in the jar.
class FeedService {
  FeedService(this._api);

  final ApiClient _api;

  Future<FeedPage> firstPage({int limit = 10}) => _fetch(limit: limit);

  Future<FeedPage> nextPage(FeedPage previous, {int limit = 10}) {
    if (!previous.hasMore ||
        previous.lastScore == null ||
        previous.lastId == null) {
      throw const ApiException('No more posts');
    }
    return _fetch(
      limit: limit,
      lastScore: previous.lastScore!,
      lastId: previous.lastId!,
    );
  }

  /// A single author's posts (profile screen) - newest first, keyset on
  /// (last_created_at, last_id).
  Future<FeedPage> userPosts(
    int userId, {
    int limit = 10,
    String? lastCreatedAt,
    int? lastId,
  }) async {
    final json = await _api.getJson('/api/v1/posts', query: {
      'user_id': '$userId',
      'limit': '$limit',
      if (lastCreatedAt != null) 'last_created_at': lastCreatedAt,
      if (lastId != null) 'last_id': '$lastId',
    });
    return FeedPage.fromJson(json);
  }

  /// Posts carrying a hashtag (hashtag page) - newest first, keyset as
  /// userPosts; carries [FeedPage.total] (every post with the tag, for
  /// the header count).
  Future<FeedPage> tagPosts(
    String tag, {
    int limit = 10,
    String? lastCreatedAt,
    int? lastId,
  }) async {
    final json = await _api.getJson('/api/v1/posts', query: {
      'tag': tag,
      'limit': '$limit',
      if (lastCreatedAt != null) 'last_created_at': lastCreatedAt,
      if (lastId != null) 'last_id': '$lastId',
    });
    return FeedPage.fromJson(json);
  }

  /// A single post by id (posts.php ?post_id=N).
  Future<Post> fetchPost(int postId) async {
    final json =
        await _api.getJson('/api/v1/posts', query: {'post_id': '$postId'});
    final raw = json['post'];
    if (raw is! Map<String, dynamic>) {
      throw const ApiException('Invalid post response');
    }
    return Post.fromJson(raw);
  }

  /// Delta of posts newer than [afterId] (posts.php ?after_id=N) - the
  /// "new posts" check used by pull-to-refresh; still score-ranked among
  /// themselves.
  Future<FeedPage> newerThan(int afterId, {int limit = 10}) async {
    final json = await _api.getJson('/api/v1/posts', query: {
      'after_id': '$afterId',
      'limit': '$limit',
    });
    return FeedPage.fromJson(json);
  }

  Future<FeedPage> _fetch({
    int limit = 10,
    double? lastScore,
    int? lastId,
  }) async {
    final json = await _api.getJson('/api/v1/posts', query: {
      'limit': '$limit',
      if (lastScore != null) 'last_score': '$lastScore',
      if (lastId != null) 'last_id': '$lastId',
    });
    return FeedPage.fromJson(json);
  }
}
