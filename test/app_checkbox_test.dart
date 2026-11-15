import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:enclavd/theme/enclavd_theme.dart';
import 'package:enclavd/widgets/ui/app_checkbox.dart';

Widget _host(Widget child) => MaterialApp(
      theme: buildEnclavdTheme(),
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  testWidgets('centres the check and toggles from the label', (tester) async {
    var value = true;
    await tester.pumpWidget(
      _host(
        StatefulBuilder(
          builder: (context, setState) => AppCheckbox(
            value: value,
            onChanged: (next) => setState(() => value = next),
            label: 'Remember me',
          ),
        ),
      ),
    );

    final box = tester.widget<AnimatedContainer>(
      find.byType(AnimatedContainer),
    );
    expect(box.alignment, Alignment.center);

    final check = tester.widget<FaIcon>(find.byType(FaIcon));
    expect(check.icon?.codePoint, FontAwesomeIcons.check.codePoint);

    await tester.tap(find.text('Remember me'));
    await tester.pumpAndSettle();

    expect(value, isFalse);
    expect(find.byType(FaIcon), findsNothing);
  });

  testWidgets('disabled checkbox is not tappable', (tester) async {
    await tester.pumpWidget(
      _host(
        const AppCheckbox(
          value: false,
          label: 'Remember me',
        ),
      ),
    );

    expect(tester.widget<InkWell>(find.byType(InkWell)).onTap, isNull);
  });
}
