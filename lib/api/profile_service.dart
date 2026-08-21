import 'api_client.dart';

/// A member's profile header — the "top part" of the site's profile page
/// (GET /api/v1/profile?user_id=N).
///
/// Field contract (profile.php GET): id, username, full_name,
/// profile_picture_url, personality_type, rank, bio, prestige,
/// date_created, is_online, is_active, post_count, warning_count,
/// follower_count, following_count, is_following, is_following_you, is_own.
class Profile {
  const Profile({
    required this.id,
    required this.username,
    required this.fullName,
    required this.profilePictureUrl,
    required this.personalityType,
    required this.rank,
    required this.bio,
    required this.prestige,
    required this.dateCreated,
    required this.isOnline,
    required this.isActive,
    required this.postCount,
    required this.warningCount,
    required this.followerCount,
    required this.followingCount,
    required this.isFollowing,
    required this.isFollowingYou,
    required this.isOwn,
  });

  final int id;
  final String username;
  final String fullName;
  final String profilePictureUrl;
  final String? personalityType;
  final String rank;
  final String bio;
  final int prestige;
  final String dateCreated; // '2024-11-20 21:05:59' (DB format)
  final bool isOnline;
  final String isActive; // 'true' / 'false'
  final int postCount;
  final int warningCount;
  final int followerCount;
  final int followingCount;
  final bool isFollowing;
  final bool isFollowingYou;
  final bool isOwn;

  bool get isBlocked => isActive == 'false';

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
        id: (json['id'] as num?)?.toInt() ?? 0,
        username: json['username'] as String? ?? '',
        fullName: json['full_name'] as String? ?? '',
        profilePictureUrl: json['profile_picture_url'] as String? ??
            '/assets/default-avatar.png',
        personalityType: json['personality_type'] as String?,
        rank: json['rank'] as String? ?? 'Member',
        bio: json['bio'] as String? ?? '',
        prestige: (json['prestige'] as num?)?.toInt() ?? 0,
        dateCreated: json['date_created'] as String? ?? '',
        isOnline: json['is_online'] as bool? ?? false,
        isActive: json['is_active'] as String? ?? 'true',
        postCount: (json['post_count'] as num?)?.toInt() ?? 0,
        warningCount: (json['warning_count'] as num?)?.toInt() ?? 0,
        followerCount: (json['follower_count'] as num?)?.toInt() ?? 0,
        followingCount: (json['following_count'] as num?)?.toInt() ?? 0,
        isFollowing: json['is_following'] as bool? ?? false,
        isFollowingYou: json['is_following_you'] as bool? ?? false,
        isOwn: json['is_own'] as bool? ?? false,
      );
}

/// Result of a follow toggle (POST /api/v1/profile {action:'follow'}).
class FollowResult {
  const FollowResult({
    required this.following,
    required this.followerCount,
    required this.followingCount,
  });

  final bool following; // now following (vs unfollowed)
  final int followerCount;
  final int followingCount;

  factory FollowResult.fromJson(Map<String, dynamic> json) => FollowResult(
        following: (json['action'] as String?) == 'followed',
        followerCount: (json['followers'] as num?)?.toInt() ?? 0,
        followingCount: (json['following'] as num?)?.toInt() ?? 0,
      );
}

/// ProfileService — the profile header + follow toggle over api/v1.
///
/// Contracts (verified against the live handlers):
///   GET  /api/v1/profile ?user_id=N    → {success, profile:{...}}
///   GET  /api/v1/profile ?username=N   → same shape, resolved by username
///        (comment @mention taps; 404 when the name doesn't exist)
///   POST /api/v1/profile {action:'follow', followee_id} (JSON + CSRF)
///                                        → {success, action: followed|
///                                           unfollowed, followers,
///                                           following}
class ProfileService {
  ProfileService(this._api);

  final ApiClient _api;

  Future<Profile> fetchProfile(int userId) async {
    final json =
        await _api.getJson('/api/v1/profile', query: {'user_id': '$userId'});
    return _profileFrom(json);
  }

  /// Resolves a username to its profile (site parity: the comment renderer
  /// linkifies mentions by username → id lookup; the app resolves on tap).
  Future<Profile> fetchProfileByUsername(String username) async {
    final json = await _api
        .getJson('/api/v1/profile', query: {'username': username});
    return _profileFrom(json);
  }

  Profile _profileFrom(Map<String, dynamic> json) {
    final raw = json['profile'];
    if (raw is! Map<String, dynamic>) {
      throw const ApiException('Invalid profile response');
    }
    return Profile.fromJson(raw);
  }

  /// Toggles follow on a member (server rejects self-follow with 400).
  Future<FollowResult> toggleFollow(int followeeId) async {
    final json = await _api.postJson('/api/v1/profile', {
      'action': 'follow',
      'followee_id': followeeId,
    });
    return FollowResult.fromJson(json);
  }
}

/// Port of profile.php's `Joined M j, Y` — '2024-11-20 21:05:59' →
/// 'Nov 20, 2024'. Returns '' on unparseable input.
String formatJoinedDate(String dbDateTime) {
  final parsed = DateTime.tryParse(dbDateTime.replaceFirst(' ', 'T'));
  if (parsed == null) return '';
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final m = months[parsed.month - 1];
  return '$m ${parsed.day}, ${parsed.year}';
}
