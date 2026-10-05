import 'dart:convert';

import 'wallet_storage.dart';

/// A saved recipient: a human label bound to an address on one network.
class Contact {
  const Contact({
    required this.label,
    required this.address,
    required this.networkId,
  });

  final String label;
  final String address;
  final String networkId;

  /// Addresses are compared case-insensitively so `0xAbC…` and `0xabc…` are
  /// not stored twice.
  bool matches(String otherAddress, String otherNetworkId) =>
      networkId == otherNetworkId &&
      address.toLowerCase() == otherAddress.toLowerCase();

  Map<String, Object?> toJson() => <String, Object?>{
        'label': label,
        'address': address,
        'networkId': networkId,
      };

  factory Contact.fromJson(Map<String, Object?> json) => Contact(
        label: json['label'] as String,
        address: json['address'] as String,
        networkId: json['networkId'] as String,
      );
}

/// Persists the address book in `shared_preferences`.
///
/// Contacts are public data (an address plus a local label), so they do not
/// belong in the secure keystore and intentionally outlive `removeWallet` —
/// deleting the seed should not also erase who you send to.
class ContactStore {
  const ContactStore({this._storage = const WalletStorage()});

  final WalletStorage _storage;

  /// The saved contacts, or an empty list when nothing is stored or the
  /// payload is unreadable.
  Future<List<Contact>> read() async {
    final String? raw = await _storage.readContacts();
    if (raw == null || raw.isEmpty) {
      return const <Contact>[];
    }
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! List) {
        return const <Contact>[];
      }
      return <Contact>[
        for (final Object? item in decoded)
          Contact.fromJson((item! as Map<Object?, Object?>).cast<String, Object?>()),
      ];
    } catch (_) {
      // A corrupt address book is treated as empty rather than crashing.
      return const <Contact>[];
    }
  }

  Future<void> write(List<Contact> contacts) async {
    await _storage.writeContacts(
      jsonEncode(contacts.map((Contact c) => c.toJson()).toList()),
    );
  }
}
