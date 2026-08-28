import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:enclavd/api/api_client.dart';
import 'package:enclavd/api/reports_service.dart';
import 'package:enclavd/screens/report_issue_screen.dart';
import 'package:enclavd/screens/ticket_detail_screen.dart';
import 'package:enclavd/theme/enclavd_theme.dart';

class _FakeReports extends ReportsService {
  _FakeReports({this.data, this.detail})
      : super(ApiClient(
            store: _NoopStore(), apiBaseUrl: 'https://example.com'));

  final ReportPage? data;
  final ReportDetail? detail;

  @override
  Future<ReportPage> list({int page = 1}) async => data!;

  @override
  Future<ReportDetail> fetchDetail(int id) async => detail!;
}

class _NoopStore implements SessionStore {
  @override
  Future<void> clear() async {}

  @override
  Future<List<SessionCookie>> load() async => const [];

  @override
  Future<void> save(List<SessionCookie> cookies) async {}
}

void main() {
  testWidgets('renders the form and the open/closed report groups',
      (tester) async {
    final fake = _FakeReports(
      data: const ReportPage(
        items: [
          ReportTicket(
            id: 3,
            type: 'Bug',
            content: 'still broken',
            status: 'Open',
            date: '2026-08-20 09:15',
          ),
          ReportTicket(
            id: 2,
            type: 'Account issue',
            content: 'fixed',
            status: 'Closed',
            date: '2026-08-01 10:00',
          ),
        ],
        total: 2,
        page: 1,
        totalPages: 1,
        allowedTypes: ReportsService.fallbackTypes,
      ),
    );
    await tester.pumpWidget(MaterialApp(
      theme: buildEnclavdTheme(),
      home: ReportIssueScreen(reports: fake),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Report an issue'), findsWidgets, reason: 'appbar + form');
    expect(find.text('Describe the issue'), findsOneWidget);
    expect(find.text('Submit report'), findsOneWidget);

    // The reports list sits below the fold. Drag from the LEFT MARGIN: a
    // drag on the textarea is claimed by the text field, so the list never scrolls.
    await tester.dragFrom(const Offset(8, 400), const Offset(0, -400));
    await tester.pump();
    expect(find.text('Your reports'), findsOneWidget);
    expect(find.text('OPEN & PENDING'), findsOneWidget,
        reason: 'group headers render uppercase (site parity)');
    expect(find.text('still broken'), findsOneWidget);
    expect(find.text('Open'), findsOneWidget);
    await tester.dragFrom(const Offset(8, 400), const Offset(0, -300));
    await tester.pump();
    expect(find.text('CLOSED'), findsOneWidget);
    expect(find.text('fixed'), findsOneWidget);
  });

  testWidgets('tapping a report opens its detail screen', (tester) async {
    final fake = _FakeReports(
      data: const ReportPage(
        items: [
          ReportTicket(
            id: 3,
            type: 'Bug',
            content: 'still broken',
            status: 'Open',
            date: '2026-08-20 09:15',
          ),
        ],
        total: 1,
        page: 1,
        totalPages: 1,
        allowedTypes: ReportsService.fallbackTypes,
      ),
      detail: const ReportDetail(
        id: 3,
        type: 'Bug',
        content: 'still broken',
        status: 'Open',
        date: '2026-08-20 09:15',
        solvedDate: null,
        owner: null,
        events: [],
      ),
    );
    await tester.pumpWidget(MaterialApp(
      theme: buildEnclavdTheme(),
      home: ReportIssueScreen(reports: fake),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.dragFrom(const Offset(8, 400), const Offset(0, -400));
    await tester.pump();
    await tester.tap(find.text('still broken'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400)); // route push
    await tester.pump();

    expect(find.byType(TicketDetailScreen), findsOneWidget);
    expect(find.text('Report #3'), findsWidgets, reason: 'detail header');
  });

  testWidgets('empty state when no reports exist', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildEnclavdTheme(),
      home: ReportIssueScreen(
        reports: _FakeReports(
          data: const ReportPage(
            items: [],
            total: 0,
            page: 1,
            totalPages: 1,
            allowedTypes: ReportsService.fallbackTypes,
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('You have not submitted any reports yet.'),
        findsOneWidget);
    expect(find.text('Use the form above to send your first report.'),
        findsOneWidget);
  });
}
