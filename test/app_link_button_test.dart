import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:enclavd/theme/enclavd_theme.dart';
import 'package:enclavd/widgets/ui/app_link_button.dart';

Widget _host(Widget child) => MaterialApp(
      theme: buildEnclavdTheme(),
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  testWidgets('has an invisible 44px hit area and no pressed animation', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      _host(
        AppLinkButton(
          label: 'Forgot password?',
          onPressed: () => taps++,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final button = tester.widget<TextButton>(find.byType(TextButton));
    final style = button.style!;
    expect(
      style.minimumSize!.resolve(<WidgetState>{}),
      const Size(0, 44),
    );
    expect(
      style.overlayColor!.resolve(<WidgetState>{}),
      Colors.transparent,
    );
    expect(style.splashFactory, NoSplash.splashFactory);
    expect(style.animationDuration, Duration.zero);
    expect(
        style.shape!.resolve(<WidgetState>{}), isA<RoundedRectangleBorder>());

    final size = tester.getSize(find.byType(TextButton));
    expect(size.height, greaterThanOrEqualTo(44));

    final rect = tester.getRect(find.byType(TextButton));
    await tester.tapAt(rect.center);
    await tester.pump();
    expect(taps, 1);

    // The invisible overlay catches near-misses outside the TextButton's box.
    await tester.tapAt(Offset(rect.left - 24, rect.center.dy));
    await tester.pump();
    expect(taps, 2);

    await tester.tapAt(Offset(rect.center.dx, rect.top - 8));
    await tester.pump();
    expect(taps, 3);
  });

  testWidgets('nearby links keep their own taps', (tester) async {
    var forgot = 0;
    var register = 0;
    await tester.pumpWidget(
      _host(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppLinkButton(
              label: 'Forgot password?',
              onPressed: () => forgot++,
            ),
            const SizedBox(height: 24),
            AppLinkButton(
              label: 'Create an account',
              onPressed: () => register++,
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    final forgotRect = tester.getRect(
      find.widgetWithText(TextButton, 'Forgot password?'),
    );
    await tester.tapAt(forgotRect.center);
    await tester.pump();

    expect(forgot, 1);
    expect(register, 0);
  });

  testWidgets('a drag starting in the expanded margin still scrolls', (
    tester,
  ) async {
    var taps = 0;
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildEnclavdTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            controller: controller,
            child: SizedBox(
              width: double.infinity,
              child: Column(
                children: [
                  const SizedBox(height: 300),
                  AppLinkButton(
                    label: 'Forgot password?',
                    onPressed: () => taps++,
                  ),
                  const SizedBox(height: 900),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final rect = tester.getRect(find.byType(TextButton));
    await tester.dragFrom(
      Offset(rect.right + 24, rect.center.dy),
      const Offset(0, -120),
    );
    await tester.pumpAndSettle();

    expect(controller.offset, greaterThan(0));
    expect(taps, 0);
  });
}

// TEMP DEBUG
void debugOverlayTest() {}
