import 'api_client.dart';

/// One support ticket (api/v1/reports.php - user-facing only).
class ReportTicket {
  const ReportTicket({
    required this.id,
    required this.type,
    required this.content,
    required this.status,
    required this.date,
  });

  final int id;
  final String type;
  final String content;
  final String status; // Open / Pending / Closed / Sealed
  final String date; // 'Y-m-d H:i' (server-local display format)

  bool get isClosed => status == 'Closed' || status == 'Sealed';

  factory ReportTicket.fromJson(Map<String, dynamic> json) => ReportTicket(
        id: (json['id'] as num?)?.toInt() ?? 0,
        type: json['submission_type'] as String? ?? 'Issue',
        content: json['submission_content'] as String? ?? '',
        status: json['submission_status'] as String? ?? 'Open',
        date: json['submission_date'] as String? ?? '',
      );
}

/// One page of tickets + the allowed issue types (the site's select).
class ReportPage {
  const ReportPage({
    required this.items,
    required this.total,
    required this.page,
    required this.totalPages,
    required this.allowedTypes,
  });

  final List<ReportTicket> items;
  final int total;
  final int page;
  final int totalPages;
  final List<String> allowedTypes;

  /// Split the site way: open/pending first, then closed/sealed.
  List<ReportTicket> get open =>
      items.where((t) => !t.isClosed).toList(growable: false);
  List<ReportTicket> get closed =>
      items.where((t) => t.isClosed).toList(growable: false);
}

/// Ticket owner identity (the detail header - ticket.php's avatar row).
class TicketOwner {
  const TicketOwner({
    required this.id,
    required this.username,
    required this.rank,
    required this.isActive,
    required this.profilePictureUrl,
  });

  final int id;
  final String username;
  final String rank;
  final String isActive; // 'true' / 'false'
  final String profilePictureUrl;

  factory TicketOwner.fromJson(Map<String, dynamic> json) => TicketOwner(
        id: (json['id'] as num?)?.toInt() ?? 0,
        username: json['username'] as String? ?? '',
        rank: json['rank'] as String? ?? 'Member',
        isActive: json['is_active'] as String? ?? 'true',
        profilePictureUrl: json['profile_picture_url'] as String? ??
            '/assets/default-avatar.png',
      );
}

/// One activity event on a ticket: a reply ('reply') or a status log
/// ('log') - ticket.php merges both into one oldest-first timeline.
class TicketEvent {
  const TicketEvent({
    required this.type,
    required this.date,
    this.content = '',
    this.username = '',
    this.profilePictureUrl = '',
    this.rank = 'Member',
    this.ticketLog = '',
  });

  final String type; // 'reply' | 'log'
  final String date; // DB UTC wall-clock
  final String content; // reply text ('' for logs)
  final String username;
  final String profilePictureUrl;
  final String rank;
  final String ticketLog; // log text ('' for replies)

  bool get isLog => type == 'log';

  factory TicketEvent.fromJson(Map<String, dynamic> json) => TicketEvent(
        type: json['type'] as String? ?? 'log',
        date: json['date'] as String? ?? '',
        content: json['content'] as String? ?? '',
        username: json['username'] as String? ?? '',
        profilePictureUrl: json['profile_picture_url'] as String? ?? '',
        rank: json['rank'] as String? ?? 'Member',
        ticketLog: json['ticket_log'] as String? ?? '',
      );
}

/// The ticket detail (GET /api/v1/reports?id=N).
class ReportDetail {
  const ReportDetail({
    required this.id,
    required this.type,
    required this.content,
    required this.status,
    required this.date,
    required this.solvedDate,
    required this.owner,
    required this.events,
  });

  final int id;
  final String type;
  final String content;
  final String status; // Open / Pending / Closed / Sealed
  final String date; // 'Y-m-d H:i'
  final String? solvedDate; // 'Y-m-d H:i' or null
  final TicketOwner? owner;
  final List<TicketEvent> events;

  bool get isClosed => status == 'Closed' || status == 'Sealed';
  bool get sealed => status == 'Sealed';

  factory ReportDetail.fromJson(
    Map<String, dynamic> json, {
    Object? owner,
    Object? events,
  }) =>
      ReportDetail(
        id: (json['id'] as num?)?.toInt() ?? 0,
        type: json['submission_type'] as String? ?? 'Issue',
        content: json['submission_content'] as String? ?? '',
        status: json['submission_status'] as String? ?? 'Open',
        date: json['submission_date'] as String? ?? '',
        solvedDate: json['submission_solved_date'] as String?,
        owner: owner is Map<String, dynamic>
            ? TicketOwner.fromJson(owner)
            : null,
        events: events is List
            ? events
                .whereType<Map<String, dynamic>>()
                .map(TicketEvent.fromJson)
                .toList()
            : const [],
      );
}

/// ReportsService - the viewer's support tickets over api/v1.
class ReportsService {
  ReportsService(this._api);

  final ApiClient _api;

  static const List<String> fallbackTypes = [
    'Bug',
    'Account issue',
    'Abuse / report user',
    'Feedback',
    'Feature request',
    'Other',
  ];

  Future<ReportPage> list({int page = 1}) async {
    final json = await _api
        .getJson('/api/v1/reports', query: {'page': '$page'});
    final raw = json['reports'];
    if (raw is! List) {
      throw const ApiException('Invalid reports response');
    }
    final types = json['allowed_types'];
    return ReportPage(
      items: raw
          .whereType<Map<String, dynamic>>()
          .map(ReportTicket.fromJson)
          .toList(),
      total: (json['total'] as num?)?.toInt() ?? 0,
      page: (json['page'] as num?)?.toInt() ?? 1,
      totalPages: (json['total_pages'] as num?)?.toInt() ?? 1,
      allowedTypes: types is List
          ? types.whereType<String>().toList()
          : fallbackTypes,
    );
  }

  /// Submits a new report (type must be one of the allowed types; the
  /// server falls back to 'Other' for anything else).
  Future<ReportTicket> create({
    required String type,
    required String content,
  }) async {
    final json = await _api.postJson('/api/v1/reports', {
      'action': 'create',
      'submission_type': type,
      'submission_content': content,
    });
    final raw = json['report'];
    if (raw is! Map<String, dynamic>) {
      throw const ApiException('Invalid report response');
    }
    return ReportTicket.fromJson(raw);
  }

  /// The ticket + its activity timeline (own tickets only).
  Future<ReportDetail> fetchDetail(int id) async {
    final json =
        await _api.getJson('/api/v1/reports', query: {'id': '$id'});
    final ticket = json['ticket'];
    if (ticket is! Map<String, dynamic>) {
      throw const ApiException('Invalid report response');
    }
    return ReportDetail.fromJson(ticket,
        owner: json['owner'], events: json['events']);
  }

  /// Adds a reply - the ticket flips to Pending server-side.
  Future<void> addReply({
    required int ticketId,
    required String content,
  }) async {
    await _api.postJson('/api/v1/reports', {
      'action': 'reply',
      'ticket_id': ticketId,
      'reply_content': content,
    });
  }

  /// Closes the ticket (solved fields + a status log row server-side).
  Future<void> markSolved(int ticketId) async {
    await _api
        .postJson('/api/v1/reports', {'action': 'mark_solved', 'ticket_id': ticketId});
  }
}
