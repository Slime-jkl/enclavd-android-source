import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:enclavd/widgets/onscreen_ticker.dart';

void main() {
  bool enabled(WidgetTester tester) => tester
      .widget<TickerMode>(find.descendant(
        of: find.byType(OnscreenTicker),
        matching: find.byType(TickerMode),
      ))
      .enabled;

  testWidgets('tickers stop when the child leaves the screen', (tester) async {
    final controller = ScrollController();

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          controller: controller,
          child: const Column(
            children: [
              OnscreenTicker(child: Text('emoji')),
              SizedBox(height: 4000),
            ],
          ),
        ),
      ),
    ));
    await tester.pump();
    expect(enabled(tester), isTrue);

    controller.jumpTo(3000);
    await tester.pump();
    await tester.pump();
    expect(enabled(tester), isFalse);

    controller.jumpTo(0);
    await tester.pump();
    await tester.pump();
    expect(enabled(tester), isTrue);
  });

  testWidgets('a child without a scrollable stays enabled', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Center(child: OnscreenTicker(child: Text('x')))),
    ));
    await tester.pump();
    expect(enabled(tester), isTrue);
  });
}
