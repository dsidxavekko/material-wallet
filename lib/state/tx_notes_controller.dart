import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/utils/app_log.dart';
import '../data/wallet/wallet_storage.dart';
import 'wallet_identity_controller.dart';

/// The user's private notes on transactions: "rent", "invoice 1042".
///
/// A note is a local label keyed by network and transaction hash. It never
/// leaves the device except when the user exports the activity as CSV, and it
/// is dropped with the wallet it describes.
class TxNotesController extends ChangeNotifier {
  TxNotesController({
    this._storage = const WalletStorage(),
    WalletIdentityController? identity,
  }) : _identity = identity {
    identity?.addListener(_onIdentityChanged);
  }

  final WalletStorage _storage;
  final WalletIdentityController? _identity;

  /// Longest note kept; a note is a label, not a document.
  static const int maxLength = 200;

  Map<String, String> _notes = <String, String>{};

  static String _key(String networkId, String hash) =>
      '$networkId|${hash.toLowerCase()}';

  /// The note on [hash] for [networkId], or `null`.
  String? noteFor(String networkId, String hash) =>
      _notes[_key(networkId, hash)];

  bool get isEmpty => _notes.isEmpty;

  Future<void> load() async {
    try {
      final String? raw = await _storage.readTxNotes();
      if (raw == null || raw.isEmpty) {
        return;
      }
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return;
      }
      _notes = <String, String>{
        for (final MapEntry<Object?, Object?> entry in decoded.entries)
          if (entry.key is String &&
              entry.value is String &&
              (entry.value! as String).trim().isNotEmpty)
            entry.key! as String: entry.value! as String,
      };
      notifyListeners();
    } catch (error, stackTrace) {
      // Notes are conveniences: a damaged blob reads as none.
      AppLog.warning('Could not load transaction notes', error, stackTrace);
    }
  }

  /// Saves [text] as the note on [hash]; blank removes it.
  Future<void> setNote(String networkId, String hash, String text) async {
    final String trimmed = text.trim();
    final Map<String, String> next = Map<String, String>.of(_notes);
    if (trimmed.isEmpty) {
      next.remove(_key(networkId, hash));
    } else {
      next[_key(networkId, hash)] =
          trimmed.length > maxLength ? trimmed.substring(0, maxLength) : trimmed;
    }
    _notes = next;
    notifyListeners();
    try {
      await _storage.writeTxNotes(jsonEncode(_notes));
    } catch (error, stackTrace) {
      AppLog.warning('Could not save the transaction note', error, stackTrace);
    }
  }

  /// Forgets every note held in memory. Called when the wallet is removed; the
  /// persisted copy goes with `WalletStorage.clear`.
  void _onIdentityChanged() {
    if (_identity?.status == WalletStatus.empty && _notes.isNotEmpty) {
      _notes = <String, String>{};
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _identity?.removeListener(_onIdentityChanged);
    super.dispose();
  }
}
