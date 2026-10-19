import 'dart:math' as math;

enum PasswordStrength { weak, fair, good, strong }

/// A rough, advisory reading of how hard a password is to guess offline.
///
/// The vault's PBKDF2 slows an attacker who holds the encrypted file, but only
/// the password decides how long that takes (see the README). This is a
/// deliberately simple estimate — character pool × length, discounted for
/// repetition, sequences and the most common passwords — meant to steer people
/// away from `password123`, not a guarantee. It never blocks anything: the hard
/// minimum is [kMinPasswordLength] in the field itself.
class PasswordAssessment {
  const PasswordAssessment(this.strength, this.bits, this.hint);

  final PasswordStrength strength;

  /// Estimated entropy in bits (rough).
  final double bits;

  /// What to change, or `null` when there is nothing to say.
  final String? hint;
}

PasswordAssessment assessPassword(String password) {
  if (password.isEmpty) {
    return const PasswordAssessment(PasswordStrength.weak, 0, null);
  }

  final String lower = password.toLowerCase();
  if (_common.contains(lower) ||
      _common.any((String c) => c.length >= 6 && lower == '$c!' )) {
    return const PasswordAssessment(
      PasswordStrength.weak,
      6,
      'This is one of the most common passwords',
    );
  }

  int pool = 0;
  if (password.contains(RegExp(r'[a-z]'))) pool += 26;
  if (password.contains(RegExp(r'[A-Z]'))) pool += 26;
  if (password.contains(RegExp(r'[0-9]'))) pool += 10;
  if (password.contains(RegExp(r'''[ !"#$%&'()*+,\-./:;<=>?@\[\\\]^_`{|}~]'''))) {
    pool += 33;
  }
  if (password.runes.any((int r) => r > 126)) pool += 100;
  pool = math.max(pool, 10);

  // Repeats add almost nothing: count each distinct character once, and the
  // rest at a small fraction.
  final int distinct = password.runes.toSet().length;
  final int repeats = password.runes.length - distinct;
  double bits = (distinct + repeats * 0.15) * (math.log(pool) / math.ln2);

  // A run like "abcd" or "1234" (or backwards) is predictable.
  final int sequential = _sequentialRun(lower);
  bits -= sequential * 2.5;

  // Only digits, or only one case of letters, is what attackers try first.
  final bool onlyDigits = RegExp(r'^[0-9]+$').hasMatch(password);
  if (onlyDigits) {
    bits = math.min(bits, password.length * 3.3);
  }

  bits = math.max(bits, 0);

  final PasswordStrength strength = bits < 28
      ? PasswordStrength.weak
      : bits < 45
          ? PasswordStrength.fair
          : bits < 60
              ? PasswordStrength.good
              : PasswordStrength.strong;

  String? hint;
  if (strength == PasswordStrength.weak || strength == PasswordStrength.fair) {
    if (onlyDigits) {
      hint = 'Digits alone are guessed quickly — add words or letters';
    } else if (password.length < 12) {
      hint = 'Longer is stronger — try several unrelated words';
    } else if (sequential > 2) {
      hint = 'Avoid runs like abcd or 1234';
    } else {
      hint = 'Add more words or characters';
    }
  }
  return PasswordAssessment(strength, bits, hint);
}

/// The number of characters that sit inside ascending or descending runs of
/// three or more (`abc`, `321`).
int _sequentialRun(String s) {
  final List<int> r = s.runes.toList();
  int counted = 0;
  int i = 0;
  while (i < r.length - 2) {
    final int step = r[i + 1] - r[i];
    if ((step == 1 || step == -1) && r[i + 2] - r[i + 1] == step) {
      int j = i + 2;
      while (j + 1 < r.length && r[j + 1] - r[j] == step) {
        j++;
      }
      counted += j - i + 1;
      i = j + 1;
    } else {
      i++;
    }
  }
  return counted;
}

const Set<String> _common = <String>{
  'password', 'password1', 'password12', 'password123', 'passw0rd', 'qwerty',
  'qwerty123', 'qwertyuiop', '12345678', '123456789', '1234567890',
  '87654321', '11111111', '00000000', 'abc12345', 'iloveyou', 'admin123',
  'welcome1', 'welcome123', 'letmein1', 'monkey123', 'dragon123',
  'football1', 'baseball1', 'sunshine1', 'princess1', 'bitcoin123',
  'bitcoin1', 'ethereum1', 'crypto123', 'wallet123', 'trustno1',
  'qazwsxedc', '1q2w3e4r', '1qaz2wsx', 'zaq12wsx', 'asdfghjkl', 'zxcvbnm1',
  'qwer1234', 'password!', 'p@ssw0rd', 'p@ssword', 'changeme', 'master123',
};
