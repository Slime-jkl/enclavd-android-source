import 'api_client.dart';

/// One support ticket (api/v1/reports.php — user-facing only).
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

/// ReportsService — the viewer's support tickets over api/v1.
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

  /// Submits a new report (type must be one of the allowed types — the
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
}
