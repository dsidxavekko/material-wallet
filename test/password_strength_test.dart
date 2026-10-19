import 'package:crypto_wallet/core/utils/password_strength.dart';
import 'package:crypto_wallet/shared/widgets/password_strength_meter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

PasswordStrength _of(String p) => assessPassword(p).strength;

void main() {
  group('password strength', () {
    test('the usual suspects are weak and say why', () {
      for (final String p in <String>['password', '12345678', 'qwerty123', 'Password123']) {
        expect(_of(p), PasswordStrength.weak, reason: p);
      }
      expect(assessPassword('password').hint, contains('common'));
    });

    test('digits alone never rate above weak/fair, however long', () {
      expect(_of('48213976'), PasswordStrength.weak);
      expect(assessPassword('48213976').hint, contains('Digits'));
      expect(_of('482139760918'), isNot(PasswordStrength.strong));
    });

    test('sequences and repeats are discounted', () {
      expect(_of('abcdefgh'), PasswordStrength.weak);
      expect(_of('aaaaaaaaaaaa'), PasswordStrength.weak);
      expect(assessPassword('abcdefghijkl1').bits,
          lessThan(assessPassword('xqjvbnmtrwpl1').bits));
    });

    test('a long mixed password rates strong', () {
      expect(_of('correct horse battery staple 7'), PasswordStrength.strong);
      expect(_of('T7#qLm2!vXz9'), isIn(<PasswordStrength>[
        PasswordStrength.good,
        PasswordStrength.strong,
      ]));
    });

    test('an empty password says nothing', () {
      expect(assessPassword('').hint, isNull);
    });

    test('longer is never rated lower for the same characters', () {
      double previous = -1;
      for (int n = 8; n <= 24; n += 4) {
        final double bits = assessPassword('Tq7!${'xK2m' * (n ~/ 4)}').bits;
        expect(bits, greaterThanOrEqualTo(previous));
        previous = bits;
      }
    });
  });

  testWidgets('the meter shows nothing for an empty field and a label otherwise',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: PasswordStrengthMeter(password: ''))),
    );
    expect(find.byType(LinearProgressIndicator), findsNothing);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: PasswordStrengthMeter(password: 'password')),
      ),
    );
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.textContaining('Weak'), findsOneWidget);
  });
}
