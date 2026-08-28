import 'api_client.dart';
import 'messages_service.dart' show parseDbTime;

/// One invitation (api/v1/invitations.php - user-facing only).
class Invitation {
  const Invitation({
    required this.id,
    required this.code,
    required this.status,
    required this.validUntil,
  });

  final int id;
  final String code;
  final String status; // pending / accepted / expired
  final String validUntil; // DB UTC wall-clock

  bool get deletable => status != 'accepted';

  factory Invitation.fromJson(Map<String, dynamic> json) => Invitation(
        id: (json['id'] as num?)?.toInt() ?? 0,
        code: json['code'] as String? ?? '',
        status: json['status'] as String? ?? 'pending',
        validUntil: json['valid_until'] as String? ?? '',
      );
}

/// The invitation list + the user's remaining invite count.
class InvitationList {
  const InvitationList({required this.inviteCount, required this.items});

  final int inviteCount;
  final List<Invitation> items;
}

/// Result of creating an invitation (new code + updated count).
class InvitationCreated {
  const InvitationCreated({required this.inviteCount, required this.item});

  final int inviteCount;
  final Invitation item;
}

/// List/create/delete over api/v1 (the site's invitations.php
/// quick-create/delete, without the admin branches).
class InvitationsService {
  InvitationsService(this._api);

  final ApiClient _api;

  Future<InvitationList> list() async {
    final json = await _api.getJson('/api/v1/invitations');
    final raw = json['invitations'];
    if (raw is! List) {
      throw const ApiException('Invalid invitations response');
    }
    return InvitationList(
      inviteCount: (json['invite_count'] as num?)?.toInt() ?? 0,
      items: raw
          .whereType<Map<String, dynamic>>()
          .map(Invitation.fromJson)
          .toList(),
    );
  }

  /// Creates a 30-day invite (deducts one from the user's count).
  Future<InvitationCreated> create() async {
    final json =
        await _api.postJson('/api/v1/invitations', {'action': 'create'});
    final raw = json['invitation'];
    if (raw is! Map<String, dynamic>) {
      throw const ApiException('Invalid invitation response');
    }
    return InvitationCreated(
      inviteCount: (json['invite_count'] as num?)?.toInt() ?? 0,
      item: Invitation.fromJson(raw),
    );
  }

  /// Deletes an invitation (own, non-accepted only - 403 otherwise);
  /// returns the updated invite count.
  Future<int> delete(int invitationId) async {
    final json = await _api
        .postJson('/api/v1/invitations', {'action': 'delete', 'invitation_id': invitationId});
    return (json['invite_count'] as num?)?.toInt() ?? 0;
  }
}

/// The site's `date('M j, Y H:i', strtotime($valid_until))` - DB UTC
/// wall-clock -> local 'Sep 20, 2026 15:37'. '' on unparseable.
String formatInviteExpiry(String dbDateTime) {
  final t = parseDbTime(dbDateTime)?.toLocal();
  if (t == null) return '';
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final mm = t.minute.toString().padLeft(2, '0');
  final hh = t.hour.toString().padLeft(2, '0');
  return '${months[t.month - 1]} ${t.day}, ${t.year} $hh:$mm';
}
