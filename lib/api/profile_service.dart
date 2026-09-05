import 'api_client.dart';

/// Max bio length the server accepts (accounts.bio is varchar(250); the
/// api rejects anything longer with 422 "Bio must be 250 characters or
/// fewer" - match it, counting code points like mb_strlen does).
const int kMaxBioChars = 250;

/// A member's profile header - the "top part" of the site's profile page
/// (GET /api/v1/profile?user_id=N). Fields: id, username, full_name,
/// profile_picture_url, personality_type, rank, bio, prestige,
/// date_created, is_online, is_active, block_reason, post_count,
/// warning_count, warnings:[...], follower_count, following_count,
/// is_following, is_following_you, is_own.
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
    required this.blockReason,
    required this.postCount,
    required this.warningCount,
    required this.warnings,
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
  final String blockReason; // '' when not blocked
  final int postCount;
  final int warningCount;
  final List<UserWarning> warnings; // ACTIVE warnings, newest first
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
        blockReason: json['block_reason'] as String? ?? '',
        postCount: (json['post_count'] as num?)?.toInt() ?? 0,
        warningCount: (json['warning_count'] as num?)?.toInt() ?? 0,
        warnings: [
          for (final w in (json['warnings'] as List? ?? const []))
            if (w is Map<String, dynamic>) UserWarning.fromJson(w),
        ],
        followerCount: (json['follower_count'] as num?)?.toInt() ?? 0,
        followingCount: (json['following_count'] as num?)?.toInt() ?? 0,
        isFollowing: json['is_following'] as bool? ?? false,
        isFollowingYou: json['is_following_you'] as bool? ?? false,
        isOwn: json['is_own'] as bool? ?? false,
      );
}

/// One ACTIVE warning on a profile - the site's profile.php warnings list.
class UserWarning {
  const UserWarning({
    required this.id,
    required this.reason,
    required this.adminId,
    required this.adminUsername,
    required this.secondsLeft,
  });

  final int id;
  final String reason;
  final int adminId;
  final String adminUsername;
  final int secondsLeft;

  /// Site formula: ceil(max(0, seconds_left) / 86400).
  int get daysLeft => (secondsLeft > 0 ? (secondsLeft / 86400).ceil() : 0);

  factory UserWarning.fromJson(Map<String, dynamic> json) => UserWarning(
        id: (json['id'] as num?)?.toInt() ?? 0,
        reason: json['reason'] as String? ?? '',
        adminId: (json['admin_id'] as num?)?.toInt() ?? 0,
        adminUsername: json['admin_username'] as String? ?? '',
        secondsLeft: (json['seconds_left'] as num?)?.toInt() ?? 0,
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

/// Which relation list a request targets (the ?list= wire value).
enum FollowListKind {
  followers('followers'),
  following('following');

  const FollowListKind(this.wire);
  final String wire;
}

/// One member row in a followers/following list (GET /api/v1/profile
/// ?user_id=N&list=...): account fields + the viewer's relation state.
class FollowListItem {
  const FollowListItem({
    required this.id,
    required this.username,
    required this.fullName,
    required this.profilePictureUrl,
    required this.personalityType,
    required this.rank,
    required this.bio,
    required this.isActive,
    required this.isOnline,
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
  final String isActive; // 'true' / 'false'
  final bool isOnline;
  final bool isFollowing; // the viewer follows this row user
  final bool isFollowingYou; // this row user follows the viewer
  final bool isOwn; // this row user IS the viewer

  bool get isBlocked => isActive == 'false';

  FollowListItem copyWith({bool? isFollowing}) => FollowListItem(
        id: id,
        username: username,
        fullName: fullName,
        profilePictureUrl: profilePictureUrl,
        personalityType: personalityType,
        rank: rank,
        bio: bio,
        isActive: isActive,
        isOnline: isOnline,
        isFollowing: isFollowing ?? this.isFollowing,
        isFollowingYou: isFollowingYou,
        isOwn: isOwn,
      );

  factory FollowListItem.fromJson(Map<String, dynamic> json) =>
      FollowListItem(
        id: (json['id'] as num?)?.toInt() ?? 0,
        username: json['username'] as String? ?? '',
        fullName: json['full_name'] as String? ?? '',
        profilePictureUrl: json['profile_picture_url'] as String? ??
            '/assets/default-avatar.png',
        personalityType: json['personality_type'] as String?,
        rank: json['rank'] as String? ?? 'Member',
        bio: json['bio'] as String? ?? '',
        isActive: json['is_active'] as String? ?? 'true',
        isOnline: json['is_online'] as bool? ?? false,
        isFollowing: json['is_following'] as bool? ?? false,
        isFollowingYou: json['is_following_you'] as bool? ?? false,
        isOwn: json['is_own'] as bool? ?? false,
      );
}

/// One page of a relation list, with the server's total for the header.
class FollowListPage {
  const FollowListPage({
    required this.users,
    required this.total,
    required this.hasMore,
  });

  final List<FollowListItem> users;
  final int total;
  final bool hasMore;
}

/// The viewer's OWN account row (GET /api/v1/profile?self=1) - the
/// edit-profile prefill; the public profile header omits email, gender,
/// birthdate and the geo ids.
class AccountSettings {
  const AccountSettings({
    required this.id,
    required this.username,
    required this.email,
    required this.fullName,
    required this.profilePictureUrl,
    required this.personalityType,
    required this.rank,
    required this.bio,
    required this.birthdate,
    required this.gender,
    required this.geoCountry,
    required this.geoRegion,
    required this.geoCity,
  });

  final int id;
  final String username;
  final String email;
  final String fullName;
  final String profilePictureUrl;
  final String? personalityType;
  final String rank;
  final String bio;
  final String? birthdate; // 'Y-m-d' or null
  final String gender; // NONE / MALE / FEMALE
  final int? geoCountry;
  final int? geoRegion;
  final int? geoCity;

  factory AccountSettings.fromJson(Map<String, dynamic> json) =>
      AccountSettings(
        id: (json['id'] as num?)?.toInt() ?? 0,
        username: json['username'] as String? ?? '',
        email: json['email'] as String? ?? '',
        fullName: json['full_name'] as String? ?? '',
        profilePictureUrl: json['profile_picture_url'] as String? ??
            '/assets/default-avatar.png',
        personalityType: json['personality_type'] as String?,
        rank: json['rank'] as String? ?? 'Member',
        bio: json['bio'] as String? ?? '',
        birthdate: json['birthdate'] as String?,
        gender: json['gender'] as String? ?? 'NONE',
        geoCountry: (json['geo_country'] as num?)?.toInt(),
        geoRegion: (json['geo_region'] as num?)?.toInt(),
        geoCity: (json['geo_city'] as num?)?.toInt(),
      );
}

/// Profile header + account editing over api/v1 (JSON + CSRF).
/// GET ?user_id=N / ?username=N -> {profile}; ?self=1 -> {account};
/// GET ?user_id=N&list=followers|following -> {users, total, has_more};
/// POST actions: follow, update_profile, change_password, upload_avatar.
class ProfileService {
  ProfileService(this._api);

  final ApiClient _api;

  Future<Profile> fetchProfile(int userId) async {
    final json =
        await _api.getJson('/api/v1/profile', query: {'user_id': '$userId'});
    return _profileFrom(json);
  }

  /// Resolves a username to its profile (comment @mention taps; 404 when
  /// the name doesn't exist).
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

  /// One page of a member's followers/following, newest relation first
  /// (offset pagination; the server caps limit at 50).
  Future<FollowListPage> listFollows({
    required int userId,
    required FollowListKind kind,
    int limit = 20,
    int offset = 0,
  }) async {
    final json = await _api.getJson('/api/v1/profile', query: {
      'user_id': '$userId',
      'list': kind.wire,
      'limit': '$limit',
      'offset': '$offset',
    });
    final raw = json['users'] as List<dynamic>? ?? const [];
    return FollowListPage(
      users: [
        for (final u in raw)
          if (u is Map<String, dynamic>) FollowListItem.fromJson(u),
      ],
      total: (json['total'] as num?)?.toInt() ?? 0,
      hasMore: json['has_more'] as bool? ?? false,
    );
  }

  /// The viewer's own account row - the edit-profile prefill.
  Future<AccountSettings> fetchSelf() async {
    final json =
        await _api.getJson('/api/v1/profile', query: const {'self': '1'});
    final raw = json['account'];
    if (raw is! Map<String, dynamic>) {
      throw const ApiException('Invalid account response');
    }
    return AccountSettings.fromJson(raw);
  }

  /// Saves the edit-profile fields; null optional values CLEAR the field
  /// server-side (profile-edit.php parity).
  Future<void> updateProfile({
    required String fullName,
    required String bio,
    String? birthdate,
    String? gender,
    int? geoCountry,
    int? geoRegion,
    int? geoCity,
  }) async {
    await _api.postJson('/api/v1/profile', {
      'action': 'update_profile',
      'full_name': fullName,
      'bio': bio,
      'birthdate': birthdate,
      'gender': gender ?? 'NONE',
      'geo_country': geoCountry,
      'geo_region': geoRegion,
      'geo_city': geoCity,
    });
  }

  /// Changes the password (server validates current + match + length).
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
    required String confirmPassword,
  }) async {
    await _api.postJson('/api/v1/profile', {
      'action': 'change_password',
      'current_password': currentPassword,
      'new_password': newPassword,
      'confirm_password': confirmPassword,
    });
  }

  /// Uploads a new avatar (data URL, same wire format as post images);
  /// returns the NEW root-relative profile_picture_url.
  Future<String> uploadAvatar(String dataUrl) async {
    final json = await _api.postJson('/api/v1/profile', {
      'action': 'upload_avatar',
      'image_data': dataUrl,
    });
    return json['profile_picture_url'] as String? ??
        '/assets/default-avatar.png';
  }
}

/// Port of profile.php's `Joined M j, Y` - '2024-11-20 21:05:59' ->
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
