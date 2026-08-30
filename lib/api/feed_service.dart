import 'api_client.dart';
import '../utils/html_entities.dart';

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
    this.lastReplyAt,
    this.lastReplyUsername,
    this.lastReplyRank,
    this.lastReplyActive,
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
  final String isActive;
  final String rank;
  final String? image;
  final bool isOwner;
  final String? lastReplyAt;
  final String? lastReplyUsername;
  final String? lastReplyRank;
  final String? lastReplyActive;

  factory Post.fromJson(Map<String, dynamic> json) => Post(
        id: (json['id'] as num?)?.toInt() ?? 0,
        authorId: (json['author_id'] as num?)?.toInt() ?? 0,
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
        // Domain thread OP payload: last activity line (web parity).
        lastReplyAt: json['last_reply_at'] as String?,
        lastReplyUsername: json['last_reply_username'] as String?,
        lastReplyRank: json['last_reply_rank'] as String?,
        lastReplyActive: json['last_reply_active'] as String?,
      );

  bool get isBlocked => isActive == 'false';
}


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

  /// A single post by id
  Future<Post> fetchPost(int postId) async {
    final json =
        await _api.getJson('/api/v1/posts', query: {'post_id': '$postId'});
    final raw = json['post'];
    if (raw is! Map<String, dynamic>) {
      throw const ApiException('Invalid post response');
    }
    return Post.fromJson(raw);
  }


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
