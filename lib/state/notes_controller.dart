import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/utils/app_log.dart';
import '../data/wallet/wallet_storage.dart';

/// Private notes attached to transactions, kept on this device only.
///
/// Keyed by transaction hash (case-insensitive), so a note follows the
/// transaction wherever it shows up.
class NotesController extends ChangeNotifier {
  NotesController({WalletStorage? storage})
      : _storage = storage ?? const WalletStorage();

  final WalletStorage _storage;

  Map<String, String> _notes = const <String, String>{};

  Map<String, String> get all => _notes;

  /// The note for [hash], or `null`.
  String? noteFor(String hash) => _notes[hash.toLowerCase()];

  Future<void> load() async {
    try {
      final String? raw = await _storage.readTxNotes();
      if (raw == null || raw.isEmpty) {
        return;
      }
      final Object? decoded = jsonDecode(raw);
      if (decoded is Map) {
        _notes = <String, String>{
          for (final MapEntry<Object?, Object?> e in decoded.entries)
            if (e.value is String) '${e.key}'.toLowerCase(): e.value! as String,
        };
        notifyListeners();
      }
    } catch (error, stackTrace) {
      AppLog.warning('Could not load transaction notes', error, stackTrace);
    }
  }

  /// Saves [text] for [hash]; empty text removes the note.
  Future<void> setNote(String hash, String text) async {
    final String clean = text.trim();
    final Map<String, String> next = Map<String, String>.of(_notes);
    if (clean.isEmpty) {
      next.remove(hash.toLowerCase());
    } else {
      next[hash.toLowerCase()] = clean.length > 200 ? clean.substring(0, 200) : clean;
    }
    _notes = next;
    notifyListeners();
    try {
      await _storage.writeTxNotes(jsonEncode(next));
    } catch (error, stackTrace) {
      AppLog.warning('Could not save the transaction note', error, stackTrace);
    }
  }
}
