import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/utils/feedback.dart';
import '../../core/utils/formatters.dart';
import '../../data/networks/network_config.dart';
import '../../data/wallet/address_validator.dart';
import '../../data/wallet/contact_store.dart';
import '../../shared/widgets/coin_avatar.dart';
import '../../shared/widgets/empty_state.dart';
import '../../state/contacts_controller.dart';
import '../../state/settings_controller.dart';

/// Manage the saved recipients shown when composing a transfer.
class AddressBookScreen extends StatelessWidget {
  const AddressBookScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ContactsController contacts = context.watch<ContactsController>();

    return Scaffold(
      appBar: AppBar(title: const Text('Address book')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _add(context),
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Add'),
      ),
      body: contacts.isEmpty
          ? const EmptyState(
              icon: Icons.contacts_rounded,
              title: 'No saved recipients',
              message:
                  'Save the addresses you send to often and they will appear '
                  'here and in the send flow.',
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
              itemCount: contacts.contacts.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (BuildContext context, int index) {
                final Contact contact = contacts.contacts[index];
                final NetworkConfig network =
                    NetworkCatalog.byId(contact.networkId);
                return Card(
                  margin: EdgeInsets.zero,
                  child: ListTile(
                    leading: CoinAvatar(
                      symbol: network.symbol,
                      color: network.color,
                      size: 40,
                    ),
                    title: Text(contact.label),
                    subtitle: Text(
                      '${network.name} · '
                      '${AppFormat.shortAddress(contact.address)}',
                    ),
                    trailing: IconButton(
                      tooltip: 'Remove',
                      icon: const Icon(Icons.delete_outline_rounded),
                      onPressed: () =>
                          contacts.remove(contact.address, contact.networkId),
                    ),
                  ),
                );
              },
            ),
    );
  }

  Future<void> _add(BuildContext context) async {
    final ContactsController contacts = context.read<ContactsController>();
    final NetworkConfig initial =
        context.read<SettingsController>().network;

    final Contact? contact = await showModalBottomSheet<Contact>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _ContactForm(initialNetwork: initial),
    );
    if (contact == null) {
      return;
    }
    await contacts.save(contact);
    if (context.mounted) {
      showAppSnackBar(
        context,
        'Saved “${contact.label}”.',
        icon: Icons.check_circle_outline_rounded,
      );
    }
  }
}

/// Bottom sheet that collects a label, address and network for a new contact.
class _ContactForm extends StatefulWidget {
  const _ContactForm({required this.initialNetwork});

  final NetworkConfig initialNetwork;

  @override
  State<_ContactForm> createState() => _ContactFormState();
}

class _ContactFormState extends State<_ContactForm> {
  final TextEditingController _label = TextEditingController();
  final TextEditingController _address = TextEditingController();
  late NetworkConfig _network = widget.initialNetwork;
  String? _addressError;

  @override
  void dispose() {
    _label.dispose();
    _address.dispose();
    super.dispose();
  }

  AddressValidation get _validation =>
      AddressValidator.validate(_network, _address.text);

  bool get _canSave =>
      _label.text.trim().isNotEmpty && _validation.valid;

  void _save() {
    if (!_validation.valid) {
      setState(() => _addressError = _validation.reason);
      return;
    }
    Navigator.of(context).pop(
      Contact(
        label: _label.text.trim(),
        address: _address.text.trim(),
        networkId: _network.id,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 4,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'New recipient',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _label,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Label',
              hintText: 'e.g. Savings',
            ),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<NetworkConfig>(
            initialValue: _network,
            items: <DropdownMenuItem<NetworkConfig>>[
              for (final NetworkConfig network in NetworkCatalog.all)
                DropdownMenuItem<NetworkConfig>(
                  value: network,
                  child: Text(network.name),
                ),
            ],
            onChanged: (NetworkConfig? value) {
              if (value == null) {
                return;
              }
              setState(() {
                _network = value;
                _addressError = null;
              });
            },
            decoration: const InputDecoration(labelText: 'Network'),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _address,
            autocorrect: false,
            enableSuggestions: false,
            onChanged: (_) => setState(() => _addressError = null),
            decoration: InputDecoration(
              labelText: 'Address',
              errorText: _addressError,
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _canSave ? _save : null,
            icon: const Icon(Icons.check_rounded),
            label: const Text('Save recipient'),
          ),
        ],
      ),
    );
  }
}
