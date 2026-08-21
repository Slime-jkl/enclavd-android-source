import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:enclavd/api/api_client.dart';
import 'package:enclavd/api/reports_service.dart';
import 'package:enclavd/screens/ticket_detail_screen.dart';
import 'package:enclavd/theme/enclavd_theme.dart';

class _FakeReports extends ReportsService {
  _FakeReports({required this.detail})
      : super(ApiClient(
            store: _NoopStore(), apiBaseUrl: 'https://example.com'));

  final ReportDetail detail;

  @override
  Future<ReportDetail> fetchDetail(int id) async => detail;
}

class _NoopStore implements SessionStore {
  @override
  Future<void> clear() async {}

  @override
  Future<List<SessionCookie>> load() async => const [];

  @override
  Future<void> save(List<SessionCookie> cookies) async {}
}

const _openDetail = ReportDetail(
  id: 3,
  type: 'Bug',
  content: 'still broken',
  status: 'Pending',
  date: '2026-08-21 20:17',
  solvedDate: null,
  owner: TicketOwner(
    id: 1,
    username: 'Developer',
    rank: 'SysOp',
    isActive: 'true',
    profilePictureUrl: '/public/avatars/a.jpg',
  ),
  events: [
    TicketEvent(
      type: 'reply',
      date: '2026-08-21 20:17:46',
      content: 'my first reply',
      username: 'Developer',
      profilePictureUrl: '/public/avatars/a.jpg',
      rank: 'SysOp',
    ),
    TicketEvent(
      type: 'log',
      date: '2026-08-21 20:18:00',
      ticketLog: 'Developer changed the status to Closed',
    ),
  ],
);

void main() {
  testWidgets('renders the ticket, timeline, reply box and solve action',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildEnclavdTheme(),
      home: TicketDetailScreen(
        ticketId: 3,
        reports: _FakeReports(detail: _openDetail),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Report #3'), findsNWidgets(2),
        reason: 'appbar + owner header line');
    expect(find.text('Developer'), findsWidgets, reason: 'owner + reply');
    expect(find.text('still broken'), findsOneWidget, reason: 'description');
    expect(find.text('Pending'), findsOneWidget);
    expect(find.text('Mark as solved'), findsOneWidget);
    expect(find.text('my first reply'), findsOneWidget, reason: 'reply bubble');
    expect(find.text('Developer changed the status to Closed'),
        findsOneWidget,
        reason: 'status log chip');
    expect(find.text('Add a reply'), findsOneWidget, reason: 'composer');
    expect(find.text('Send reply'), findsOneWidget);
  });

  testWidgets('sealed tickets hide the reply box and show the lock note',
      (tester) async {
    const sealed = ReportDetail(
      id: 4,
      type: 'Account issue',
      content: 'sealed',
      status: 'Sealed',
      date: '2026-08-20 10:00',
      solvedDate: null,
      owner: null,
      events: [],
    );
    await tester.pumpWidget(MaterialApp(
      theme: buildEnclavdTheme(),
      home: TicketDetailScreen(
        ticketId: 4,
        reports: _FakeReports(detail: sealed),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Sealed'), findsOneWidget);
    expect(find.textContaining('sealed. It cannot be reopened'),
        findsOneWidget);
    expect(find.text('Add a reply'), findsNothing);
    expect(find.text('Mark as solved'), findsNothing);
  });
}
