import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:enclavd/theme/enclavd_theme.dart';
import 'package:enclavd/widgets/ui/app_button.dart';
import 'package:enclavd/widgets/ui/app_motion.dart';

Widget _host(Widget child) => MaterialApp(
      theme: buildEnclavdTheme(),
      home: Scaffold(body: Center(child: child)),
    );

Color? _buttonColor(WidgetTester tester) {
  final container = tester.widget<AnimatedContainer>(
    find.descendant(
      of: find.byType(AppButton),
      matching: find.byType(AnimatedContainer),
    ),
  );
  return (container.decoration as BoxDecoration).color;
}

double _scale(WidgetTester tester) {
  return tester
      .widget<AnimatedScale>(
        find.descendant(
          of: find.byType(AppButton),
          matching: find.byType(AnimatedScale),
        ),
      )
      .scale;
}

void main() {
  testWidgets('press darkens, shrinks and fires light haptic feedback', (
    tester,
  ) async {
    var taps = 0;
    final haptics = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') haptics.add(call);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(
      _host(AppButton(label: 'Sign in', onPressed: () => taps++)),
    );
    final initial = _buttonColor(tester);
    expect(initial, EnclavdPalette.dark.primaryButton);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(AppButton)),
    );
    await tester.pump();
    await tester.pump(AppMotion.fast);

    expect(_buttonColor(tester), isNot(initial));
    expect(_scale(tester), 0.985);

    await gesture.up();
    await tester.pumpAndSettle();

    expect(taps, 1);
    expect(_scale(tester), 1);
    expect(haptics, hasLength(1));
    expect(haptics.single.arguments, 'HapticFeedbackType.lightImpact');
  });

  testWidgets('mouse hover uses the palette hover colour', (tester) async {
    await tester.pumpWidget(
      _host(AppButton(label: 'Sign in', onPressed: () {})),
    );

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await tester.pump();

    await mouse.moveTo(tester.getCenter(find.byType(AppButton)));
    await tester.pumpAndSettle();

    expect(_buttonColor(tester), EnclavdPalette.dark.primaryButtonHover);
  });

  testWidgets('disabled button ignores taps', (tester) async {
    await tester.pumpWidget(_host(const AppButton(label: 'Sign in')));

    await tester.tap(find.byType(AppButton));
    await tester.pump();

    expect(_buttonColor(tester), isNotNull);
  });
}
