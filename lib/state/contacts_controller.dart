import 'package:flutter/foundation.dart';

import '../core/utils/app_log.dart';
import '../data/wallet/contact_store.dart';

/// The user's address book: saved recipients with local labels.
class ContactsController extends ChangeNotifier {
  ContactsController({ContactStore? store})
      : _store = store ?? const ContactStore();

  final ContactStore _store;

  List<Contact> _contacts = const <Contact>[];

  /// Saved contacts, sorted by label for a stable list.
  List<Contact> get contacts => _contacts;

  bool get isEmpty => _contacts.isEmpty;

  Future<void> load() async {
    try {
      final List<Contact> loaded = await _store.read();
      _contacts = _sorted(loaded);
      notifyListeners();
    } catch (error, stackTrace) {
      AppLog.warning('Could not load the address book', error, stackTrace);
    }
  }

  /// Contacts saved for [networkId], sorted by label.
  List<Contact> forNetwork(String networkId) => _contacts
      .where((Contact c) => c.networkId == networkId)
      .toList(growable: false);

  /// The saved label for [address] on [networkId], or `null`.
  String? labelFor(String address, String networkId) {
    for (final Contact contact in _contacts) {
      if (contact.matches(address, networkId)) {
        return contact.label;
      }
    }
    return null;
  }

  bool contains(String address, String networkId) =>
      labelFor(address, networkId) != null;

  /// Adds [contact], replacing any existing entry for the same address.
  Future<void> save(Contact contact) async {
    final List<Contact> updated = <Contact>[
      ..._contacts.where(
        (Contact c) => !c.matches(contact.address, contact.networkId),
      ),
      contact,
    ];
    await _commit(updated);
  }

  Future<void> remove(String address, String networkId) async {
    final List<Contact> updated = _contacts
        .where((Contact c) => !c.matches(address, networkId))
        .toList(growable: false);
    await _commit(updated);
  }

  Future<void> _commit(List<Contact> updated) async {
    _contacts = _sorted(updated);
    notifyListeners();
    try {
      await _store.write(_contacts);
    } catch (error, stackTrace) {
      AppLog.warning('Could not save the address book', error, stackTrace);
    }
  }

  static List<Contact> _sorted(List<Contact> contacts) {
    final List<Contact> copy = contacts.toList()
      ..sort(
        (Contact a, Contact b) =>
            a.label.toLowerCase().compareTo(b.label.toLowerCase()),
      );
    return List<Contact>.unmodifiable(copy);
  }
}
