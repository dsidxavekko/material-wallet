import 'dart:convert';

import 'package:flutter/foundation.dart';

/// One address the background worker looks at.
///
/// Public information only — an address and the network it lives on — which is
/// why it can sit next to the other non-secret preferences. The seed is never
/// available to the background worker: it only ever reads the chain.
@immutable
class BackgroundTarget {
  const BackgroundTarget({
    required this.walletId,
    required this.walletName,
    required this.networkId,
    required this.address,
  });

  final String walletId;
  final String walletName;
  final String networkId;
  final String address;

  String get key => '$networkId|$address';

  Map<String, String> toJson() => <String, String>{
        'w': walletId,
        'n': walletName,
        'net': networkId,
        'a': address,
      };

  static BackgroundTarget? fromJson(Object? raw) {
    if (raw is! Map ||
        raw['w'] is! String ||
        raw['net'] is! String ||
        raw['a'] is! String) {
      return null;
    }
    return BackgroundTarget(
      walletId: raw['w']! as String,
      walletName: raw['n'] is String ? raw['n']! as String : '',
      networkId: raw['net']! as String,
      address: raw['a']! as String,
    );
  }

  static String encode(List<BackgroundTarget> targets) =>
      jsonEncode(<Object>[for (final BackgroundTarget t in targets) t.toJson()]);

  /// Reads a stored list; anything unreadable yields an empty one.
  static List<BackgroundTarget> decode(String? raw) {
    if (raw == null || raw.isEmpty) {
      return const <BackgroundTarget>[];
    }
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! List) {
        return const <BackgroundTarget>[];
      }
      return <BackgroundTarget>[
        for (final Object? item in decoded)
          if (fromJson(item) case final BackgroundTarget t) t,
      ];
    } on FormatException {
      return const <BackgroundTarget>[];
    }
  }
}
