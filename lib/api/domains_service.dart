import 'api_client.dart';
import 'feed_service.dart'; // Post.fromJson: threads share the feed shape


class DomainCategory {
  const DomainCategory({
    required this.id,
    required this.name,
    required this.slug,
    this.parent,
    required this.displayOrder,
    this.description,
    required this.icon,
    required this.color,
    this.iconCode,
    required this.postCount,
    this.lastPostAt,
    this.lastPostAuthor,
    this.lastPostUserId,
    this.children = const [],
  });

  final int id;
  final String name;
  final String slug;
  final int? parent;
  final int displayOrder;
  final String? description;
  final String icon; // fa-* class name (fa-music, fa-folder, ...)
  final String color; // hex '#rrggbb'
  final int? iconCode; // FA6 solid codepoint from the server
  final int postCount;
  final String? lastPostAt; // DB UTC wall-clock
  final String? lastPostAuthor;
  final int? lastPostUserId;
  final List<DomainCategory> children;

  bool get isRoot => parent == null;
  bool get hasChildren => children.isNotEmpty;

  factory DomainCategory.fromJson(Map<String, dynamic> json) =>
      DomainCategory(
        id: (json['id'] as num?)?.toInt() ?? 0,
        name: json['name'] as String? ?? '',
        slug: json['slug'] as String? ?? '',
        parent: (json['parent'] as num?)?.toInt(),
        displayOrder: (json['display_order'] as num?)?.toInt() ?? 0,
        description: json['description'] as String?,
        icon: json['icon'] as String? ?? 'fa-globe',
        color: json['color'] as String? ?? '#60a5fa',
        iconCode: (json['icon_code'] as num?)?.toInt(),
        postCount: (json['post_count'] as num?)?.toInt() ?? 0,
        lastPostAt: json['last_post_at'] as String?,
        lastPostAuthor: json['last_post_author'] as String?,
        lastPostUserId: (json['last_post_user_id'] as num?)?.toInt(),
      );


  static List<DomainCategory> buildTree(List<DomainCategory> flat) {
    final indexed = <int, DomainCategory>{for (final c in flat) c.id: c};
    final childrenOf = <int, List<DomainCategory>>{};
    for (final node in flat) {
      final parent = node.parent;
      if (parent == null || !indexed.containsKey(parent)) continue;
      childrenOf.putIfAbsent(parent, () => []).add(node);
    }
    final roots = <DomainCategory>[];
    for (final node in flat) {
      final parent = node.parent;
      if (parent == null || !indexed.containsKey(parent)) {
        final children = childrenOf[node.id];
        if (children == null) {
          roots.add(node);
        } else {
          roots.add(_withChildren(node, children));
        }
      }
    }
    return roots;
  }

  /// Rebuilds a category with the given children attached.
  static DomainCategory _withChildren(
      DomainCategory parent, List<DomainCategory> children) {
    return DomainCategory(
      id: parent.id,
      name: parent.name,
      slug: parent.slug,
      parent: parent.parent,
      displayOrder: parent.displayOrder,
      description: parent.description,
      icon: parent.icon,
      color: parent.color,
      iconCode: parent.iconCode,
      postCount: parent.postCount,
      lastPostAt: parent.lastPostAt,
      lastPostAuthor: parent.lastPostAuthor,
      lastPostUserId: parent.lastPostUserId,
      children: children,
    );
  }
}


class DomainThread {
  const DomainThread({
    required this.post,
    required this.domainSlug,
    required this.domainName,
    this.domainIcon = 'fa-globe',
    this.domainColor = '#60a5fa',
    this.domainIconCode,
    this.lastReplyAt,
    this.lastReplyUsername,
    this.lastReplyRank,
    this.lastReplyActive,
  });

  final Post post;
  final String domainSlug;
  final String domainName;
  final String domainIcon; // fa-* class name
  final String domainColor; // hex '#rrggbb'
  final int? domainIconCode; // FA6 solid codepoint from the server
  final String? lastReplyAt; // DB UTC wall-clock, newest reply activity
  final String? lastReplyUsername;
  final String? lastReplyRank;
  final String? lastReplyActive; // 'true' / 'false' string

  factory DomainThread.fromJson(Map<String, dynamic> json) => DomainThread(
        post: Post.fromJson(json),
        domainSlug: json['domain_slug'] as String? ?? '',
        domainName: json['domain_name'] as String? ?? '',
        domainIcon: json['domain_icon'] as String? ?? 'fa-globe',
        domainColor: json['domain_color'] as String? ?? '#60a5fa',
        domainIconCode: (json['domain_icon_code'] as num?)?.toInt(),
        lastReplyAt: json['last_reply_at'] as String?,
        lastReplyUsername: json['last_reply_username'] as String?,
        lastReplyRank: json['last_reply_rank'] as String?,
        lastReplyActive: json['last_reply_active'] as String?,
      );
}

/// One page of threads for a category
class DomainThreadPage {
  const DomainThreadPage({
    required this.category,
    required this.threads,
    required this.total,
    required this.hasMore,
  });

  final DomainCategory category;
  final List<DomainThread> threads;
  final int total;
  final bool hasMore;

  factory DomainThreadPage.fromJson(Map<String, dynamic> json) {
    final rawThreads = json['threads'] as List<dynamic>? ?? const [];
    final rawCategory = json['category'];
    return DomainThreadPage(
      category: rawCategory is Map<String, dynamic>
          ? DomainCategory.fromJson(rawCategory)
          : const DomainCategory(
              id: 0,
              name: '',
              slug: '',
              displayOrder: 0,
              icon: '',
              color: '',
              postCount: 0),
      threads: [
        for (final t in rawThreads)
          if (t is Map<String, dynamic>) DomainThread.fromJson(t),
      ],
      total: (json['total'] as num?)?.toInt() ?? 0,
      hasMore: json['has_more'] as bool? ?? false,
    );
  }
}


class DomainFeedPage {
  const DomainFeedPage({
    required this.threads,
    required this.total,
    required this.hasMore,
  });

  final List<DomainThread> threads;
  final int total;
  final bool hasMore;

  factory DomainFeedPage.fromJson(Map<String, dynamic> json) {
    final rawThreads = json['threads'] as List<dynamic>? ?? const [];
    return DomainFeedPage(
      threads: [
        for (final t in rawThreads)
          if (t is Map<String, dynamic>) DomainThread.fromJson(t),
      ],
      total: (json['total'] as num?)?.toInt() ?? 0,
      hasMore: json['has_more'] as bool? ?? false,
    );
  }
}

/// A single thread
class DomainThreadDetail {
  const DomainThreadDetail({required this.post, required this.breadcrumb});

  final Post post;
  final List<DomainCategory> breadcrumb; // root -> leaf

  factory DomainThreadDetail.fromJson(Map<String, dynamic> json) {
    final rawPost = json['post'];
    if (rawPost is! Map<String, dynamic>) {
      throw const ApiException('Invalid thread response');
    }
    final rawTrail = json['breadcrumb'] as List<dynamic>? ?? const [];
    return DomainThreadDetail(
      post: Post.fromJson(rawPost),
      breadcrumb: [
        for (final b in rawTrail)
          if (b is Map<String, dynamic>) DomainCategory.fromJson(b),
      ],
    );
  }
}


class DomainsService {
  DomainsService(this._api);

  final ApiClient _api;

  /// The board: flat category rows (the caller builds the nested tree
  /// with [DomainCategory.buildTree]).
  Future<List<DomainCategory>> board() async {
    final json = await _api.getJson('/api/v1/domains');
    final raw = json['domains'] as List<dynamic>? ?? const [];
    return [
      for (final d in raw)
        if (d is Map<String, dynamic>) DomainCategory.fromJson(d),
    ];
  }


  Future<DomainFeedPage> feed({
    int? domainId,
    int limit = 20,
    int offset = 0,
  }) async {
    final json = await _api.getJson('/api/v1/domains', query: {
      'feed': '1',
      if (domainId != null && domainId > 0) 'domain_id': '$domainId',
      'limit': '$limit',
      'offset': '$offset',
    });
    return DomainFeedPage.fromJson(json);
  }

  /// Threads for a category, newest activity firs
  Future<DomainThreadPage> threads(
    int categoryId, {
    int limit = 20,
    int offset = 0,
  }) async {
    final json = await _api.getJson('/api/v1/domains', query: {
      'category_id': '$categoryId',
      'limit': '$limit',
      'offset': '$offset',
    });
    return DomainThreadPage.fromJson(json);
  }


  Future<DomainThreadDetail> thread(int postId) async {
    final json = await _api.getJson('/api/v1/domains',
        query: {'post_id': '$postId'});
    return DomainThreadDetail.fromJson(json);
  }
}
