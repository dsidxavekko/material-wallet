import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/utils/app_log.dart';
import '../data/networks/chain_models.dart';
import '../data/wallet/wallet_storage.dart';

/// Tokens the user chose to hide from the home list, kept on this device only.
///
/// Keyed by network and contract, so the same token stays hidden when the
/// account changes but a lookalike on another chain does not inherit the flag.
///
/// A hidden token is also left out of the portfolio totals (the home card and
/// the Portfolio screen), so hiding a worthless but priced airdrop does not
/// inflate the number. Its balance stays in the snapshot and in the CSV: hiding
/// is about what the wallet shows and adds up, not about what is on-chain.
class HiddenTokensController extends ChangeNotifier {
  HiddenTokensController({WalletStorage? storage})
    : _storage = storage ?? const WalletStorage();

  final WalletStorage _storage;

  Set<String> _hidden = const <String>{};

  static String keyFor(String networkId, TokenBalance token) =>
      '$networkId:${token.contractAddress.toLowerCase()}';

  bool isHidden(String networkId, TokenBalance token) =>
      _hidden.contains(keyFor(networkId, token));

  /// How many of [tokens] are hidden on [networkId].
  int hiddenCount(String networkId, Iterable<TokenBalance> tokens) =>
      tokens.where((TokenBalance t) => isHidden(networkId, t)).length;

  Future<void> load() async {
    try {
      final String? raw = await _storage.readHiddenTokens();
      if (raw == null || raw.isEmpty) {
        return;
      }
      final Object? decoded = jsonDecode(raw);
      if (decoded is List) {
        _hidden = <String>{
          for (final Object? e in decoded)
            if (e is String) e,
        };
        notifyListeners();
      }
    } catch (error, stackTrace) {
      AppLog.warning('Could not load hidden tokens', error, stackTrace);
    }
  }

  Future<void> setHidden(
    String networkId,
    TokenBalance token,
    bool hidden,
  ) async {
    final Set<String> next = Set<String>.of(_hidden);
    final String key = keyFor(networkId, token);
    if (hidden ? !next.add(key) : !next.remove(key)) {
      return;
    }
    _hidden = next;
    notifyListeners();
    try {
      await _storage.writeHiddenTokens(jsonEncode(next.toList()..sort()));
    } catch (error, stackTrace) {
      AppLog.warning('Could not save hidden tokens', error, stackTrace);
    }
  }
}
