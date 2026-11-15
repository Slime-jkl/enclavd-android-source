import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:enclavd/theme/enclavd_theme.dart';
import 'package:enclavd/widgets/ui/app_input_field.dart';

void main() {
  test('form inputs use the recessed page tone, not the card tone', () {
    final theme = buildEnclavdTheme();
    expect(theme.inputDecorationTheme.fillColor, EnclavdPalette.dark.background);
    expect(
      theme.inputDecorationTheme.fillColor,
      isNot(EnclavdPalette.dark.card),
    );
  });

  testWidgets('password toggle flips obscureText', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildEnclavdTheme(),
        home: Scaffold(
          body: AppInputField(
            controller: controller,
            label: 'Password',
            obscureText: true,
            showObscureToggle: true,
          ),
        ),
      ),
    );

    expect(
      tester.widget<EditableText>(find.byType(EditableText)).obscureText,
      isTrue,
    );
    await tester.tap(find.byTooltip('Show password'));
    await tester.pump();
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).obscureText,
      isFalse,
    );
  });
}
