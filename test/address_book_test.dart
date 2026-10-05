import 'dart:convert';

import 'package:crypto_wallet/data/wallet/contact_store.dart';
import 'package:crypto_wallet/data/wallet/wallet_storage.dart';
import 'package:crypto_wallet/state/contacts_controller.dart';
import 'package:flutter_test/flutter_test.dart';

/// In-memory stand-in for the preferences-backed contact storage.
class _MemoryStorage extends WalletStorage {
  String? raw;

  @override
  Future<String?> readContacts() async => raw;

  @override
  Future<void> writeContacts(String value) async => raw = value;
}

void main() {
  test('Contact survives a JSON round-trip', () {
    const Contact contact = Contact(
      label: 'Savings',
      address: 'bc1qexample',
      networkId: 'bitcoin',
    );

    final Contact restored =
        Contact.fromJson(contact.toJson());

    expect(restored.label, 'Savings');
    expect(restored.address, 'bc1qexample');
    expect(restored.networkId, 'bitcoin');
  });

  test('a corrupt address book reads as empty', () async {
    final _MemoryStorage storage = _MemoryStorage()..raw = 'not json';
    final ContactStore store = ContactStore(storage: storage);

    expect(await store.read(), isEmpty);
  });

  test('save, label lookup and remove round-trip through storage', () async {
    final _MemoryStorage storage = _MemoryStorage();
    final ContactsController contacts =
        ContactsController(store: ContactStore(storage: storage));
    await contacts.load();

    await contacts.save(const Contact(
      label: 'Exchange',
      address: '0xAbC',
      networkId: 'ethereum',
    ));

    // Matching is case-insensitive and scoped to the network.
    expect(contacts.labelFor('0xabc', 'ethereum'), 'Exchange');
    expect(contacts.labelFor('0xabc', 'polygon'), isNull);
    expect(contacts.contains('0XABC', 'ethereum'), isTrue);

    // A reload sees the persisted entry.
    final ContactsController reloaded =
        ContactsController(store: ContactStore(storage: storage));
    await reloaded.load();
    expect(reloaded.contacts, hasLength(1));
    expect(reloaded.contacts.single.label, 'Exchange');

    await reloaded.remove('0xABC', 'ethereum');
    expect(reloaded.contacts, isEmpty);

    final ContactsController afterDelete =
        ContactsController(store: ContactStore(storage: storage));
    await afterDelete.load();
    expect(afterDelete.contacts, isEmpty);
  });

  test('saving the same address replaces the previous label', () async {
    final ContactsController contacts =
        ContactsController(store: ContactStore(storage: _MemoryStorage()));
    await contacts.load();

    await contacts.save(const Contact(
      label: 'Old',
      address: 'bc1qexample',
      networkId: 'bitcoin',
    ));
    await contacts.save(const Contact(
      label: 'New',
      address: 'bc1qexample',
      networkId: 'bitcoin',
    ));

    expect(contacts.contacts, hasLength(1));
    expect(contacts.labelFor('bc1qexample', 'bitcoin'), 'New');
  });

  test('forNetwork filters by network', () async {
    final ContactsController contacts =
        ContactsController(store: ContactStore(storage: _MemoryStorage()));
    await contacts.load();
    await contacts.save(const Contact(
      label: 'A',
      address: 'a',
      networkId: 'bitcoin',
    ));
    await contacts.save(const Contact(
      label: 'B',
      address: 'b',
      networkId: 'ethereum',
    ));

    expect(contacts.forNetwork('bitcoin'), hasLength(1));
    expect(contacts.forNetwork('ethereum').single.label, 'B');
  });

  test('an unreadable stored list is tolerated', () async {
    final _MemoryStorage storage = _MemoryStorage()
      ..raw = jsonEncode(<Object>[
        <String, Object?>{'label': 'ok', 'address': 'a', 'networkId': 'bitcoin'},
        <String, Object?>{'label': 'broken'},
      ]);
    final ContactStore store = ContactStore(storage: storage);

    // The malformed entry makes the whole payload a miss rather than a crash.
    expect(await store.read(), isEmpty);
  });
}
