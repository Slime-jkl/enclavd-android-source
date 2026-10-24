import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:enclavd/api/profile_service.dart';
import 'package:enclavd/theme/enclavd_theme.dart';
import 'package:enclavd/widgets/invitation_info.dart';

InvitedMember _member(int id,
        {String name = 'member', String isActive = 'true'}) =>
    InvitedMember(
      id: id,
      username: '$name$id',
      rank: 'Member',
      isActive: isActive,
    );

void main() {
  Widget wrap(Widget child) => MaterialApp(
        theme: buildEnclavdTheme(),
        home: Scaffold(body: SingleChildScrollView(child: child)),
      );

  testWidgets('system-created account shows [System] and no members section',
      (tester) async {
    await tester.pumpWidget(wrap(const InvitationInfo(
      invitedById: 0,
      invitedByUsername: '',
      members: [],
    )));

    expect(find.text('Invited by'), findsOneWidget);
    expect(find.text('[System]'), findsOneWidget);
    expect(find.text('Invited members'), findsNothing);
    expect(find.textContaining('See full list'), findsNothing);
  });

  testWidgets('a deleted inviter reads as Unknown', (tester) async {
    await tester.pumpWidget(wrap(const InvitationInfo(
      invitedById: 88,
      invitedByUsername: '',
      members: [],
    )));

    expect(find.text('Unknown'), findsOneWidget);
    expect(find.textContaining('#88'), findsNothing);
  });

  testWidgets('inviter link and the first 8 members, then the full list',
      (tester) async {
    final opened = <int>[];
    final members = [for (var i = 21; i <= 29; i++) _member(i)];

    // Tall surface: the sheet must hold all 9 rows without scrolling.
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap(InvitationInfo(
      invitedById: 1,
      invitedByUsername: 'Slimejkl',
      members: members,
      onOpenProfile: opened.add,
    )));

    expect(find.text('Invited by'), findsOneWidget);
    expect(find.text('Slimejkl#1'), findsOneWidget);
    expect(find.text('Invited members'), findsOneWidget);
    // Preview caps at 8 of 9, in server order (oldest first).
    expect(find.text('member21#21'), findsOneWidget);
    expect(find.text('member28#28'), findsOneWidget);
    expect(find.text('member29#29'), findsNothing);
    expect(find.text('See full list (9)'), findsOneWidget);

    await tester.tap(find.text('Slimejkl#1'));
    await tester.tap(find.text('member22#22'));
    expect(opened, [1, 22]);

    // The sheet holds every member, including the one the preview cut.
    await tester.tap(find.text('See full list (9)'));
    await tester.pumpAndSettle();
    expect(find.text('member29#29'), findsOneWidget);

    await tester.tap(find.text('member29#29'));
    await tester.pumpAndSettle();
    expect(opened.last, 29);
    expect(find.text('See full list (9)'), findsOneWidget); // sheet dismissed
  });

  testWidgets('blocked members are struck through in the barred color',
      (tester) async {
    await tester.pumpWidget(wrap(InvitationInfo(
      invitedById: 1,
      invitedByUsername: 'Slimejkl',
      members: [_member(42, name: 'gone', isActive: 'false')],
      onOpenProfile: (_) {},
    )));

    final text = tester.widget<Text>(find.text('gone42#42'));
    final palette = buildEnclavdTheme().extension<EnclavdPalette>()!;
    expect(text.style!.color, palette.rankName('Blocked'));
    expect(text.style!.decoration, TextDecoration.lineThrough);
  });
}
