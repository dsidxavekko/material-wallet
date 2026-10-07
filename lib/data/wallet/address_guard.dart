/// Detects addresses built to impersonate one the user already trusts.
///
/// Address poisoning is a spam pattern, not a protocol bug: an attacker sends
/// a worthless token from `0x71C765…5f6d8976F` — the first and last characters
/// of a popular exchange — and hopes the victim copies that address out of the
/// activity feed and sends real funds to it.
///
/// Wallets shorten addresses exactly as much as needed to be unreadable
/// (`0x71C7…6F`), so the trick works against every honest UI. The defence is to
/// compare the visible parts against the addresses this wallet has actually
/// dealt with and refuse to call a lookalike routine.
class AddressGuard {
  const AddressGuard._();

  /// Characters compared at the start of two addresses.
  static const int headChars = 4;

  /// Characters compared at the end of two addresses.
  static const int tailChars = 4;

  /// The entry of [known] that [candidate] imitates, or `null`.
  ///
  /// A hit needs an identical prefix *and* suffix but a different middle, so a
  /// real match is never the address itself. Both sides must be long enough to
  /// have a middle at all — short labels such as `Coinbase` or `Unknown` are
  /// skipped instead of matching everything.
  static String? impersonates(String candidate, Iterable<String> known) {
    final String? needle = _body(candidate);
    if (needle == null) {
      return null;
    }

    for (final String entry in known) {
      final String? target = _body(entry);
      if (target == null || target == needle) {
        continue;
      }
      if (needle.startsWith(target.substring(0, headChars)) &&
          needle.endsWith(target.substring(target.length - tailChars))) {
        return entry;
      }
    }
    return null;
  }

  /// The comparable characters of [address]: trimmed, lower-cased, and without
  /// the `0x` prefix, which every EVM address shares and which would otherwise
  /// eat two of the four head characters.
  ///
  /// `null` when the string is too short to have a middle at all — a label like
  /// `Unknown` would otherwise match everything.
  static String? _body(String address) {
    final String trimmed = address.trim().toLowerCase();
    final String bare =
        trimmed.startsWith('0x') ? trimmed.substring(2) : trimmed;
    return bare.length >= headChars + tailChars + 4 ? bare : null;
  }
}
