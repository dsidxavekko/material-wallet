import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/utils/explorer.dart';
import '../../core/utils/feedback.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/units.dart';
import '../../data/models/chain_kind.dart';
import '../../data/networks/chain_models.dart';
import '../../data/networks/network_config.dart';
import '../../data/wallet/address_validator.dart';
import '../../data/wallet/contact_store.dart';
import '../../data/wallet/seed_vault.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/pin_confirm_dialog.dart';
import '../../state/contacts_controller.dart';
import '../../state/send_controller.dart';
import '../../state/settings_controller.dart';
import '../../state/wallet_controller.dart';
import '../../state/wallet_identity_controller.dart';
import '../scan/scan_screen.dart';

/// Sends the native currency of the active network.
///
/// EVM networks are signed on-device and broadcast for real; every other chain
/// still stops at a validated, copyable summary.
class SendScreen extends StatefulWidget {
  const SendScreen({super.key});

  @override
  State<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends State<SendScreen> {
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();

  /// The gas price and limit that will actually be signed.
  ///
  /// Captured once, right before the confirmation sheet opens, and reused for
  /// the signature — so the total the user approves is exactly the total that
  /// leaves the account.
  ({BigInt gasPrice, BigInt gasLimit})? _quote;
  BigInt? _estimate;
  bool _loadingFee = true;

  @override
  void initState() {
    super.initState();
    _loadFee();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  NetworkConfig get _network => context.read<SettingsController>().network;

  BigInt get _balance =>
      context.read<WalletController>().snapshot?.balance ?? BigInt.zero;

  BigInt get _enteredAmount =>
      Units.parse(_amountController.text, _network.decimals) ?? BigInt.zero;

  BigInt get _effectiveFee {
    final ({BigInt gasPrice, BigInt gasLimit})? quote = _quote;
    if (quote != null) {
      return quote.gasPrice * quote.gasLimit;
    }
    return _estimate ?? BigInt.zero;
  }

  BigInt get _total =>
      _enteredAmount + (_enteredAmount > BigInt.zero ? _effectiveFee : BigInt.zero);

  bool get _hasEnoughFunds => _total <= _balance;

  AddressValidation get _addressValidation =>
      AddressValidator.validate(_network, _addressController.text);

  bool get _isValid =>
      _enteredAmount > BigInt.zero &&
      _hasEnoughFunds &&
      _addressValidation.valid;

  /// Whether the network fee is known well enough to sign with.
  ///
  /// On a chain the wallet can broadcast, an unavailable quote blocks sending:
  /// guessing a fee risks a transaction the user never approved.
  bool get _feeKnown => _quote != null || (_estimate != null && !_network.canSign);

  String get _availableLabel => Units.formatWithSymbol(
        _balance,
        _network.decimals,
        _network.symbol,
        maxDecimals: 8,
      );

  /// Fetches a fresh quote for the amount and recipient currently entered.
  ///
  /// Safe to call on every keystroke: it only reads `_quote` when complete.
  Future<void> _refreshQuote() async {
    if (!_network.canSign) {
      return;
    }
    final NetworkConfig network = _network;
    final String recipient = _extractAddress(_addressController.text.trim());
    if (recipient.isEmpty ||
        !AddressValidator.validate(network, recipient).valid) {
      return;
    }

    final SendController controller = SendController(
      identity: context.read<WalletIdentityController>(),
      network: network,
      address: context.read<WalletController>().address ?? '',
    );
    final ({BigInt gasPrice, BigInt gasLimit})? quote =
        await controller.prepare(to: recipient, value: _enteredAmount);
    controller.dispose();
    if (!mounted) {
      return;
    }
    setState(() {
      _quote = quote;
      _loadingFee = false;
    });
  }

  Future<void> _loadFee() async {
    final BigInt? fee = await context.read<WalletController>().estimateFee();
    if (!mounted) {
      return;
    }
    setState(() {
      _estimate = fee;
      _loadingFee = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final WalletController wallet = context.watch<WalletController>();
    final NetworkConfig network =
        context.select<SettingsController, NetworkConfig>((s) => s.network);
    final AppCurrency currency =
        context.select<SettingsController, AppCurrency>((s) => s.currency);
    final AccountSnapshot? snapshot = wallet.snapshot;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final AddressValidation addressCheck =
        AddressValidator.validate(network, _addressController.text);

    if (snapshot == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Send')),
        body: const EmptyState(
          icon: Icons.cloud_off_rounded,
          title: 'Account data unavailable',
          message: 'The balance is still loading. Go back and try again.',
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text('Send ${network.symbol}')),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                children: <Widget>[
                  Card(
                    child: ListTile(
                      leading: Icon(
                        Icons.account_balance_wallet_outlined,
                        color: scheme.primary,
                      ),
                      title: const Text('Available'),
                      subtitle: Text(_availableLabel),
                      trailing: Text(
                        network.name,
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    controller: _amountController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: 'Amount',
                      hintText: '0.00',
                      suffixText: network.symbol,
                      errorText: _enteredAmount > BigInt.zero && !_hasEnoughFunds
                          ? 'Not enough funds for amount + fee'
                          : null,
                      suffixIcon: TextButton(
                        onPressed: _setMax,
                        child: const Text('MAX'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _addressController,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: 'Recipient address',
                      hintText: switch (network.chain) {
                        ChainKind.bitcoin => 'bc1q… / tb1q…',
                        ChainKind.evm => '0x…',
                        ChainKind.solana => 'Base58 address',
                        ChainKind.aptos => '0x… (64 hex chars)',
                      },
                      errorText: _addressController.text.trim().isEmpty ||
                              addressCheck.valid
                          ? null
                          : addressCheck.reason,
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          IconButton(
                            tooltip: 'Address book',
                            icon: const Icon(Icons.contacts_rounded),
                            onPressed: _openAddressBook,
                          ),
                          IconButton(
                            tooltip: 'Scan QR code',
                            icon: const Icon(Icons.qr_code_scanner_rounded),
                            onPressed: _scanAddress,
                          ),
                          IconButton(
                            tooltip: 'Paste',
                            icon: const Icon(Icons.content_paste_rounded),
                            onPressed: _pasteAddress,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _SummaryCard(
                    network: network,
                    currency: currency,
                    amount: _enteredAmount,
                    fee: _feeKnown ? _effectiveFee : null,
                    loadingFee: _loadingFee,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
              child: FilledButton.icon(
                onPressed: _isValid ? _prepare : null,
                icon: const Icon(Icons.send_rounded),
                label: const Text('Review transfer'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _setMax() {
    final BigInt fee = _effectiveFee;
    final BigInt max = _balance > fee ? _balance - fee : BigInt.zero;
    _amountController.text = Units.format(
      max,
      _network.decimals,
      maxDecimals: _network.decimals,
      group: false,
    );
    setState(() {});
  }

  Future<void> _pasteAddress() async {
    final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
    final String? text = data?.text?.trim();
    if (text == null || text.isEmpty) {
      if (mounted) {
        showAppSnackBar(
          context,
          'Clipboard is empty.',
          icon: Icons.content_paste_off_rounded,
        );
      }
      return;
    }
    _addressController.text = _extractAddress(text);
    setState(() {});
  }

  /// Opens the camera and fills the recipient from the decoded QR code.
  Future<void> _scanAddress() async {
    final String? scanned = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(builder: (_) => const ScanScreen()),
    );
    if (scanned == null || !mounted) {
      return;
    }
    _addressController.text = _extractAddress(scanned);
    setState(() {});
  }

  /// Strips an optional URI scheme so `bitcoin:bc1…?amount=1` becomes `bc1…`.
  String _extractAddress(String value) {
    final Uri? uri = Uri.tryParse(value);
    if (uri != null && uri.hasScheme && uri.path.isNotEmpty) {
      return uri.path;
    }
    return value;
  }

  Future<void> _prepare() async {
    final NetworkConfig network = _network;

    // Re-quote immediately before review: the gas price moves, and the number
    // shown here is the one that gets signed.
    if (network.canSign) {
      setState(() => _loadingFee = true);
      await _refreshQuote();
      if (!mounted) {
        return;
      }
      if (_quote == null) {
        showAppSnackBar(
          context,
          'Could not reach ${network.name} to price this transfer. '
          'Nothing was sent.',
          icon: Icons.cloud_off_rounded,
        );
        return;
      }
    }

    final ContactsController contacts = context.read<ContactsController>();
    final String recipient = _extractAddress(_addressController.text.trim());
    final bool alreadySaved = contacts.contains(recipient, network.id);
    final ({BigInt gasPrice, BigInt gasLimit})? quote = _quote;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _PreparedSheet(
        network: network,
        recipient: recipient,
        amount: _enteredAmount,
        fee: _effectiveFee,
        explorerUrl: network.explorerAddress(recipient),
        alreadySaved: alreadySaved,
        onSave: () => _saveRecipient(recipient, network),
        // Signing is only offered with a quote that will actually be used.
        onSend: network.canSign && quote != null
            ? () => _signAndSend(recipient, quote)
            : null,
      ),
    );
  }

  /// Confirms with the PIN, signs on-device and broadcasts.
  ///
  /// The sheet is popped first so the progress dialog owns the screen, then the
  /// balance is refreshed so the UI reflects what actually left the account.
  Future<void> _signAndSend(
    String recipient,
    ({BigInt gasPrice, BigInt gasLimit}) quote,
  ) async {
    final NetworkConfig network = _network;
    final WalletIdentityController identity =
        context.read<WalletIdentityController>();
    final String? address = identity.addressFor(network);
    if (address == null) {
      return;
    }

    final String? pin = await PinConfirmDialog.show(
      context,
      title: 'Confirm transfer',
      confirmLabel: 'Send',
      icon: Icons.key_rounded,
    );
    if (pin == null || !mounted) {
      return;
    }

    try {
      await identity.verifyPin(pin);
    } on SeedVaultException catch (error) {
      if (mounted) {
        showAppSnackBar(context, error.message, icon: Icons.lock_outline_rounded);
      }
      return;
    }
    if (!mounted) {
      return;
    }

    final NavigatorState navigator = Navigator.of(context);
    navigator.pop(); // close the summary sheet

    final SendController controller = SendController(
      identity: identity,
      network: network,
      address: address,
    );

    unawaited(
      _runTransfer(controller, recipient, network, quote),
    );
  }

  /// Signs and broadcasts the already-reviewed quote behind a progress dialog,
  /// then shows the outcome. The balance is refreshed so the UI matches the
  /// chain.
  Future<void> _runTransfer(
    SendController controller,
    String recipient,
    NetworkConfig network,
    ({BigInt gasPrice, BigInt gasLimit}) quote,
  ) async {
    final BigInt amount = _enteredAmount;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ChangeNotifierProvider<SendController>.value(
        value: controller,
        child: _TransferProgressDialog(
          recipient: recipient,
          amount: amount,
          gasPrice: quote.gasPrice,
          gasLimit: quote.gasLimit,
        ),
      ),
    );
    final String? hash = controller.txHash;
    final bool confirmed = controller.stage == SendStage.confirmed;
    final String? error = controller.error;
    controller.dispose();

    if (!mounted) {
      return;
    }

    if (hash == null) {
      showAppSnackBar(
        context,
        error ?? 'The transfer failed. Nothing was sent.',
        icon: Icons.error_outline_rounded,
      );
      return;
    }

    await context.read<WalletController>().refresh();
    if (!mounted) {
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (_) => _TransferResultDialog(
        network: network,
        hash: hash,
        confirmed: confirmed,
        explorerUrl: network.explorerTx(hash),
      ),
    );
  }

  /// Lets the user pick a saved recipient for the active network.
  Future<void> _openAddressBook() async {
    final NetworkConfig network = _network;
    final ContactsController contacts = context.read<ContactsController>();
    final Contact? picked = await showModalBottomSheet<Contact>(
      context: context,
      showDragHandle: true,
      builder: (_) => _AddressBookSheet(
        contacts: contacts.forNetwork(network.id),
        network: network,
      ),
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() => _addressController.text = picked.address);
  }

  /// Prompts for a label and stores [address] in the address book.
  Future<void> _saveRecipient(String address, NetworkConfig network) async {
    final String? label = await showDialog<String>(
      context: context,
      builder: (_) => const _LabelDialog(),
    );
    if (label == null || label.isEmpty || !mounted) {
      return;
    }
    await context
        .read<ContactsController>()
        .save(Contact(label: label, address: address, networkId: network.id));
    if (mounted) {
      showAppSnackBar(
        context,
        'Saved “$label”.',
        icon: Icons.check_circle_outline_rounded,
      );
    }
  }
}

/// Bottom sheet listing the saved recipients for a network.
class _AddressBookSheet extends StatelessWidget {
  const _AddressBookSheet({required this.contacts, required this.network});

  final List<Contact> contacts;
  final NetworkConfig network;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: contacts.isEmpty
          ? EmptyState(
              icon: Icons.contacts_rounded,
              title: 'No saved recipients',
              message:
                  'Save a recipient from the transfer summary and it will '
                  'show up here.',
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                  child: Text(
                    '${network.name} recipients',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: contacts.length,
                    itemBuilder: (BuildContext context, int index) {
                      final Contact contact = contacts[index];
                      return ListTile(
                        leading: const Icon(Icons.person_outline_rounded),
                        title: Text(contact.label),
                        subtitle: Text(
                          AppFormat.shortAddress(contact.address),
                        ),
                        onTap: () => Navigator.of(context).pop(contact),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
    );
  }
}

/// Simple single-field dialog that owns and disposes its controller.
class _LabelDialog extends StatefulWidget {
  const _LabelDialog();

  @override
  State<_LabelDialog> createState() => _LabelDialogState();
}

class _LabelDialogState extends State<_LabelDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text.trim());

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.person_add_alt_1_rounded),
      title: const Text('Save recipient'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          labelText: 'Label',
          hintText: 'e.g. Exchange',
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// Breakdown of the transfer: amount, real network fee and total.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.network,
    required this.currency,
    required this.amount,
    required this.fee,
    required this.loadingFee,
  });

  final NetworkConfig network;
  final AppCurrency currency;
  final BigInt amount;
  final BigInt? fee;
  final bool loadingFee;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final CoinPrice? price =
        context.select<WalletController, CoinPrice?>((s) => s.snapshot?.price);

    final BigInt effectiveFee = fee ?? BigInt.zero;
    final BigInt total =
        amount + (amount > BigInt.zero ? effectiveFee : BigInt.zero);

    final String feeText;
    if (loadingFee) {
      feeText = 'Estimating…';
    } else if (fee == null) {
      feeText = 'Unavailable';
    } else {
      feeText = Units.formatWithSymbol(
        fee!,
        network.decimals,
        network.symbol,
        maxDecimals: 8,
      );
    }

    String fiatOf(BigInt raw) {
      if (price == null) {
        return '';
      }
      return AppFormat.fiat(
        Units.toDouble(raw, network.decimals) * price.usd,
        currency,
      );
    }

    return Card(
      color: scheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: <Widget>[
            _row(
              context,
              'Amount',
              Units.formatWithSymbol(
                amount,
                network.decimals,
                network.symbol,
                maxDecimals: 8,
              ),
              fiatOf(amount),
            ),
            const SizedBox(height: 12),
            _row(context, 'Network fee', feeText, fiatOf(effectiveFee)),
            const SizedBox(height: 14),
            Divider(color: scheme.outlineVariant, height: 1),
            const SizedBox(height: 14),
            Row(
              children: <Widget>[
                Text(
                  'Total',
                  style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    Text(
                      Units.formatWithSymbol(
                        total,
                        network.decimals,
                        network.symbol,
                        maxDecimals: 8,
                      ),
                      style: text.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    if (price != null)
                      Text(
                        fiatOf(total),
                        style: text.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(
    BuildContext context,
    String label,
    String value,
    String fiat,
  ) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;
    return Row(
      children: <Widget>[
        Text(
          label,
          style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const Spacer(),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Text(
              value,
              style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            if (fiat.isNotEmpty)
              Text(
                fiat,
                style:
                    text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
          ],
        ),
      ],
    );
  }
}

/// Confirmation sheet shown once the transfer has been validated.
///
/// On a chain the wallet can sign for, [onSend] is wired to a real broadcast;
/// elsewhere it stays `null` and the sheet is copy-only.
class _PreparedSheet extends StatelessWidget {
  const _PreparedSheet({
    required this.network,
    required this.recipient,
    required this.amount,
    required this.fee,
    required this.explorerUrl,
    required this.alreadySaved,
    required this.onSave,
    this.onSend,
  });

  final NetworkConfig network;
  final String recipient;
  final BigInt amount;
  final BigInt? fee;
  final String explorerUrl;
  final bool alreadySaved;
  final VoidCallback onSave;

  /// Starts the PIN-confirmed transfer; `null` when signing is unsupported.
  final VoidCallback? onSend;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final BigInt total = amount + (fee ?? BigInt.zero);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Transfer prepared',
              style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              'Validated against the live balance on ${network.name}.',
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 18),
            _line(context, 'To', recipient),
            _line(
              context,
              'Amount',
              Units.formatWithSymbol(
                amount,
                network.decimals,
                network.symbol,
                maxDecimals: 8,
              ),
            ),
            _line(
              context,
              'Network fee',
              fee == null
                  ? 'Unavailable'
                  : Units.formatWithSymbol(
                      fee!,
                      network.decimals,
                      network.symbol,
                      maxDecimals: 8,
                    ),
            ),
            _line(
              context,
              'Total',
              Units.formatWithSymbol(
                total,
                network.decimals,
                network.symbol,
                maxDecimals: 8,
              ),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: scheme.tertiaryContainer,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.info_outline_rounded,
                    color: scheme.onTertiaryContainer,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      onSend == null
                        ? 'Sending is not supported on ${network.name} yet. '
                            'Restore your recovery phrase in a signing wallet '
                            'to move funds.'
                        : 'The transfer is signed on this device and sent '
                            'straight to ${network.name}. It cannot be undone.',
                    style: text.bodySmall?.copyWith(
                      color: scheme.onTertiaryContainer,
                      height: 1.45,
                    ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            if (onSend != null) ...<Widget>[
              FilledButton.icon(
                onPressed: onSend,
                icon: const Icon(Icons.lock_rounded),
                label: Text('Send ${network.symbol}'),
              ),
              const SizedBox(height: 10),
            ],
            OutlinedButton.icon(
              onPressed: () => _copy(context),
              icon: const Icon(Icons.copy_rounded),
              label: const Text('Copy details'),
            ),
            if (!alreadySaved) ...<Widget>[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: onSave,
                icon: const Icon(Icons.person_add_alt_1_rounded),
                label: const Text('Save recipient'),
              ),
            ],
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => openExplorer(context, explorerUrl),
              icon: const Icon(Icons.open_in_new_rounded),
              label: const Text('View recipient on explorer'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _line(BuildContext context, String label, String value) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _copy(BuildContext context) async {
    final String details = <String>[
      'Network: ${network.name}',
      'To: $recipient',
      'Amount: ${Units.formatWithSymbol(amount, network.decimals, network.symbol)}',
      if (fee != null)
        'Fee: ${Units.formatWithSymbol(fee!, network.decimals, network.symbol)}',
    ].join('\n');

    await Clipboard.setData(ClipboardData(text: details));
    if (context.mounted) {
      showAppSnackBar(
        context,
        'Transfer details copied',
        icon: Icons.copy_rounded,
      );
    }
  }
}

/// Blocking dialog that drives a transfer from signing to confirmation.
///
/// The controller is injected by the caller, which owns its lifecycle, so the
/// dialog only reacts to [SendStage] changes.
class _TransferProgressDialog extends StatefulWidget {
  const _TransferProgressDialog({
    required this.recipient,
    required this.amount,
    required this.gasPrice,
    required this.gasLimit,
  });

  final String recipient;
  final BigInt amount;
  final BigInt gasPrice;
  final BigInt gasLimit;

  @override
  State<_TransferProgressDialog> createState() => _TransferProgressDialogState();
}

class _TransferProgressDialogState extends State<_TransferProgressDialog> {
  @override
  void initState() {
    super.initState();
    // Kick off after the first frame so the dialog is visible while the
    // signing work happens.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      context.read<SendController>().send(
            to: widget.recipient,
            value: widget.amount,
            gasPrice: widget.gasPrice,
            gasLimit: widget.gasLimit,
          );
    });
  }

  @override
  Widget build(BuildContext context) {
    final SendController controller = context.watch<SendController>();
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool done = controller.stage == SendStage.confirmed ||
        controller.stage == SendStage.failed ||
        controller.stage == SendStage.broadcast;

    return PopScope(
      canPop: done,
      child: AlertDialog(
        title: Text(done ? 'Transfer submitted' : 'Sending…'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (!done) ...<Widget>[
              const LinearProgressIndicator(),
              const SizedBox(height: 18),
            ],
            Text(
              controller.stage == SendStage.broadcasting ||
                      controller.stage == SendStage.signing
                  ? 'Signing on this device…'
                  : controller.stage == SendStage.broadcast
                      ? 'Waiting for ${widget.recipient.length > 12 ? '${widget.recipient.substring(0, 8)}…' : widget.recipient} to confirm…'
                      : controller.stage == SendStage.confirmed
                          ? 'Confirmed on-chain.'
                          : controller.error ?? 'Broadcasting…',
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            if (controller.txHash != null) ...<Widget>[
              const SizedBox(height: 12),
              Text(
                'Tx ${controller.txHash!.length > 18 ? '${controller.txHash!.substring(0, 18)}…' : controller.txHash}',
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
        actions: <Widget>[
          if (done)
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
        ],
      ),
    );
  }
}

/// Shows the transaction hash once the node accepted the transfer.
class _TransferResultDialog extends StatelessWidget {
  const _TransferResultDialog({
    required this.network,
    required this.hash,
    required this.confirmed,
    required this.explorerUrl,
  });

  final NetworkConfig network;
  final String hash;
  final bool confirmed;
  final String explorerUrl;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return AlertDialog(
      icon: Icon(
        confirmed ? Icons.check_circle_rounded : Icons.schedule_rounded,
      ),
      title: Text(confirmed ? 'Transfer confirmed' : 'Transfer pending'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            confirmed
                ? 'The funds left your wallet and the transaction is mined.'
                : 'The transaction was accepted and will confirm shortly. You '
                    'can follow it on the explorer.',
            style: text.bodyMedium,
          ),
          const SizedBox(height: 12),
          SelectableText(hash, style: text.bodySmall),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
        FilledButton.icon(
          onPressed: () => openExplorer(context, explorerUrl),
          icon: const Icon(Icons.open_in_new_rounded),
          label: const Text('Explorer'),
        ),
      ],
    );
  }
}
