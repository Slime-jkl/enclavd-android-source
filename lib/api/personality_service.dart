import 'api_client.dart';


class MemberPersonality {
  const MemberPersonality({
    required this.personalityType,
    required this.traits,
    required this.info,
    required this.compatibility,
    this.profile,
    this.viewer,
  });

  final String personalityType;
  final PersonalityTraits? traits; // null = no valid test row yet
  final PersonalityInfo info;
  final PersonalityCompatibility? compatibility; // null on own profile

  // The member's own header (id/username/rank/avatar)
  final PersonalityIdentity? profile;

  // viewer's header; present only when compatibility is, so the
  /// two identities can sit side by side with the synergy score between.
  final PersonalityIdentity? viewer;

  factory MemberPersonality.fromJson(Map<String, dynamic> json) =>
      MemberPersonality(
        personalityType: json['personality_type'] as String? ?? '',
        traits: json['traits'] is Map<String, dynamic>
            ? PersonalityTraits.fromJson(json['traits'] as Map<String, dynamic>)
            : null,
        info: PersonalityInfo.fromJson(
            json['info'] as Map<String, dynamic>? ?? const {}),
        compatibility: json['compatibility'] is Map<String, dynamic>
            ? PersonalityCompatibility.fromJson(
                json['compatibility'] as Map<String, dynamic>)
            : null,
        profile: json['profile'] is Map<String, dynamic>
            ? PersonalityIdentity.fromJson(json['profile'] as Map<String, dynamic>)
            : null,
        viewer: json['viewer'] is Map<String, dynamic>
            ? PersonalityIdentity.fromJson(json['viewer'] as Map<String, dynamic>)
            : null,
      );
}

// public header of one participant (server sends root-relative avatar)
class PersonalityIdentity {
  const PersonalityIdentity({
    required this.id,
    required this.username,
    required this.rank,
    required this.profilePictureUrl,
  });

  final int id;
  final String username;
  final String rank;
  final String profilePictureUrl;

  factory PersonalityIdentity.fromJson(Map<String, dynamic> json) =>
      PersonalityIdentity(
        id: (json['id'] as num?)?.toInt() ?? 0,
        username: json['username'] as String? ?? '',
        rank: json['rank'] as String? ?? 'Member',
        profilePictureUrl: json['profile_picture_url'] as String? ??
            '/assets/default-avatar.png',
      );
}

// Trait percentages of the member's latest valid test
class PersonalityTraits {
  const PersonalityTraits({
    required this.iePercentage,
    required this.snPercentage,
    required this.tfPercentage,
    required this.jpPercentage,
  });

  final int iePercentage; // introversion - extroversion
  final int snPercentage; // sensing - intuitive
  final int tfPercentage; // thinking - feeling
  final int jpPercentage; // judging - perceifiving

  factory PersonalityTraits.fromJson(Map<String, dynamic> json) =>
      PersonalityTraits(
        iePercentage: (json['ie_percentage'] as num?)?.toInt() ?? 50,
        snPercentage: (json['sn_percentage'] as num?)?.toInt() ?? 50,
        tfPercentage: (json['tf_percentage'] as num?)?.toInt() ?? 50,
        jpPercentage: (json['jp_percentage'] as num?)?.toInt() ?? 50,
      );
}

// The type's core traits + description + strengths / growth areas
class PersonalityInfo {
  const PersonalityInfo({
    required this.title,
    required this.description,
    required this.strengths,
    required this.weaknesses,
  });

  final String title; // core traits "Strategic, Visionary..etc"
  final String description;
  final List<String> strengths;
  final List<String> weaknesses;

  factory PersonalityInfo.fromJson(Map<String, dynamic> json) =>
      PersonalityInfo(
        title: json['title'] as String? ?? '',
        description: json['description'] as String? ?? '',
        strengths: _stringList(json['strengths']),
        weaknesses: _stringList(json['weaknesses']),
      );

  static List<String> _stringList(Object? raw) {
    if (raw is! List) return const [];
    return raw.whereType<String>().toList();
  }
}

// strenghts/challenges reasons between the viewer and the profile
class PersonalityCompatibility {
  const PersonalityCompatibility({
    required this.myType,
    required this.theirType,
    required this.proReason,
    required this.consReason,
    this.percentage,
  });

  final String myType;
  final String theirType;
  final String proReason;
  final String consReason;

  /// 0-100 synergy score
  final int? percentage;

  factory PersonalityCompatibility.fromJson(Map<String, dynamic> json) =>
      PersonalityCompatibility(
        myType: json['my_type'] as String? ?? '',
        theirType: json['their_type'] as String? ?? '',
        proReason: json['pro_reason'] as String? ?? '',
        consReason: json['cons_reason'] as String? ?? '',
        percentage: (json['percentage'] as num?)?.toInt(),
      );
}

// PersonalityService
class PersonalityService {
  PersonalityService(this._api);

  final ApiClient _api;

  /// The member's type results + info + compatibility with the viewer.
  Future<MemberPersonality> fetchPersonality(int userId) async {
    final json =
        await _api.getJson('/api/v1/personality', query: {'user_id': '$userId'});
    final raw = json['personality'];
    if (raw is! Map<String, dynamic>) {
      throw const ApiException('Invalid personality response');
    }
    return MemberPersonality.fromJson(raw);
  }
}
