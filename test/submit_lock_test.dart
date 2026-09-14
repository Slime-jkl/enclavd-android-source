import 'package:flutter_test/flutter_test.dart';
import 'package:enclavd/utils/submit_lock.dart';

void main() {
  testWidgets('one attempt at a time, then a cooldown', (tester) async {
    final lock = SubmitLock();

    expect(lock.begin(), isTrue);
    expect(lock.locked, isTrue);
    expect(lock.begin(), isFalse, reason: 'a submit is in flight');

    lock.end(() {});
    expect(lock.busy, isFalse);
    expect(lock.locked, isTrue, reason: 'cooling down after the attempt');
    expect(lock.begin(), isFalse, reason: 'spam tap inside the cooldown');

    await tester.pump(const Duration(seconds: 5));
    expect(lock.locked, isFalse);
    expect(lock.begin(), isTrue);

    lock.dispose();
  });

  testWidgets('a failed attempt still cools down', (tester) async {
    final lock = SubmitLock();
    lock.begin();
    lock.end(() {}); // what the catch/finally path does
    expect(lock.begin(), isFalse,
        reason: 'the text stays in the box after a failure, so the tap '
            'that follows must not resend it');
    await tester.pump(const Duration(seconds: 5));
    expect(lock.begin(), isTrue);
    lock.dispose();
  });
}
