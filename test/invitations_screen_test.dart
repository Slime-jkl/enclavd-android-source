import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:enclavd/api/api_client.dart';
import 'package:enclavd/api/invitations_service.dart';
import 'package:enclavd/screens/invitations_screen.dart';
import 'package:enclavd/theme/enclavd_theme.dart';

class _FakeInvitations extends InvitationsService {
  _FakeInvitations({this.data})
      : super(ApiClient(
            store: _NoopStore(), apiBaseUrl: 'https://example.com'));

  final InvitationList? data;

  @override
  Future<InvitationList> list() async => data!;
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
  testWidgets('renders invite count, codes, statuses and expiry',
      (tester) async {
    final fake = _FakeInvitations(
      data: const InvitationList(
        inviteCount: 2,
        items: [
          Invitation(
            id: 66,
            code: 'da67968aa90accc28f0f73c1e16d0c',
            status: 'pending',
            validUntil: '2026-09-20 12:00:00',
          ),
          Invitation(
            id: 65,
            code: 'acceptedcode',
            status: 'accepted',
            validUntil: '2026-08-01 10:00:00',
          ),
        ],
      ),
    );
    await tester.pumpWidget(MaterialApp(
      theme: buildEnclavdTheme(),
      home: InvitationsScreen(invitations: fake),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Create Invite (2 left)'), findsOneWidget);
    expect(find.text('da67968aa90accc28f0f73c1e16d0c'), findsOneWidget);
    expect(find.text('acceptedcode'), findsOneWidget);
    expect(find.text('Pending'), findsOneWidget);
    expect(find.text('Accepted'), findsOneWidget);
    expect(find.textContaining('Expires: Sep 20, 2026'), findsOneWidget);
    // Accepted invites have no delete button; only the pending one does.
    expect(find.byTooltip('Delete'), findsOneWidget);
  });

  testWidgets('empty state + no-invites warning', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildEnclavdTheme(),
      home: InvitationsScreen(
        invitations: _FakeInvitations(
          data: const InvitationList(inviteCount: 0, items: []),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('No Active Invitations'), findsOneWidget);
    expect(find.text("You don't have any invites available"), findsOneWidget);
    expect(find.textContaining('Create Invite'), findsNothing);
  });
}
