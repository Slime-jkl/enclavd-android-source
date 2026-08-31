import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:enclavd/api/social_service.dart';
import 'package:enclavd/widgets/suggestion_row.dart';

void main() {
  SuggestedUser user(int id, String name,
          {bool theyFollow = false}) =>
      SuggestedUser(
        id: id,
        username: name,
        profilePictureUrl: '/public/avatars/a.jpg',
        personalityType: 'ENFP',
        rank: 'Member',
        isActive: 'true',
        mutualCount: 2,
        youFollow: false,
        theyFollow: theyFollow,
      );

  testWidgets('renders one card per suggestion with a follow button',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SuggestionRow(
          users: [user(1, 'anna'), user(2, 'bob')],
          onOpenProfile: (_) {},
          onFollow: (_) {},
        ),
      ),
    ));

    expect(find.text('Suggested for you'), findsOneWidget);
    expect(find.text('anna'), findsOneWidget);
    expect(find.text('bob'), findsOneWidget);
    expect(find.text('Follow'), findsNWidgets(2));
  });

  testWidgets('Follow Back label when they follow the viewer',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SuggestionRow(
          users: [user(1, 'anna', theyFollow: true)],
          onOpenProfile: (_) {},
          onFollow: (_) {},
        ),
      ),
    ));

    expect(find.text('Follow Back'), findsOneWidget);
  });

  testWidgets('avatar tap opens the profile, button tap follows',
      (tester) async {
    final opened = <int>[];
    final followed = <int>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SuggestionRow(
          users: [user(1, 'anna')],
          onOpenProfile: opened.add,
          onFollow: (u) => followed.add(u.id),
        ),
      ),
    ));

    await tester.tap(find.text('anna'));
    expect(opened, [1]);

    await tester.tap(find.text('Follow'));
    expect(followed, [1]);
  });

  testWidgets('busy user shows a spinner and disables its button',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SuggestionRow(
          users: [user(1, 'anna'), user(2, 'bob')],
          busyUserId: 1,
          onOpenProfile: (_) {},
          onFollow: (_) {},
        ),
      ),
    ));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    // The busy card's button is disabled; the other still works.
    final buttons =
        tester.widgetList<TextButton>(find.byType(TextButton)).toList();
    expect(buttons[0].onPressed, isNull);
    expect(buttons[1].onPressed, isNotNull);
  });

  testWidgets('empty list renders nothing', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SuggestionRow(
          users: const [],
          onOpenProfile: (_) {},
          onFollow: (_) {},
        ),
      ),
    ));

    expect(find.text('Suggested for you'), findsNothing);
  });
}
