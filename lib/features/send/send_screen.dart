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
import '../../data/wallet/address_guard.dart';
import '../../data/wallet/address_validator.dart';
import '../../data/wallet/contact_store.dart';
import '../../data/wallet/evm_signer.dart';
import '../../shared/widgets/empty_state.dart';
import '../../state/contacts_controller.dart';
import '../../state/send_controller.dart';
import '../../state/settings_controller.dart';
import '../../state/wallet_controller.dart';
import '../../state/wallet_identity_controller.dart';
import '../lock/sensitive_auth.dart';
import '../scan/scan_screen.dart';
import 'transfer_success_screen.dart';
import 'widgets/transfer_progress_dialog.dart';

/// Sends the native currency of the active network, or an ERC-20 [token].
///
/// EVM networks are signed on-device and broadcast for real; every other chain
/// still stops at a validated, copyable summary.
class SendScreen extends StatefulWidget {
  const SendScreen({
    super.key,
    this.token,
    this.initialRecipient,
    this.initialAmount,
  });

  /// When set, the transfer is an ERC-20 `transfer` of this token instead of
  /// the chain's native currency.
  final TokenBalance? token;

  /// Prefill from a payment deep link.
  final String? initialRecipient;
  final String? initialAmount;

  @override
  State<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends State<SendScreen> {
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();

  /// The base fee, suggested tip and gas limit captured right before the
  /// confirmation sheet opens, reused for the signature — so the total the user
  /// approves is exactly the total that leaves the account.
  ({BigInt baseFee, BigInt maxPriorityFeePerGas, BigInt gasLimit})? _quote;
  FeePreset _preset = FeePreset.normal;

  /// User-entered fee, in wei per gas, used when [_preset] is custom.
  BigInt? _customTipWei;
  BigInt? _customCapWei;
  BigInt? _estimate;
  bool _loadingFee = true;

  bool get _isToken => widget.token != null;

  int get _decimals => widget.token?.decimals ?? _network.decimals;

  String get _symbol => widget.token?.symbol ?? _network.symbol;

  /// The native balance, used for the network fee (and the whole transfer on a
  /// native send).
  BigInt get _nativeBalance =>
      context.read<WalletController>().snapshot?.balance ?? BigInt.zero;

  /// The balance the entered amount is checked against: the token holding for a
  /// token transfer, otherwise the native balance.
  BigInt get _balance => widget.token?.balance ?? _nativeBalance;

  /// The tip for the selected [FeePreset].
  BigInt get _priority => _preset == FeePreset.custom
      ? (_customTipWei ?? BigInt.zero)
      : _preset.tipFor(_quote?.maxPriorityFeePerGas ?? BigInt.zero);

  /// The fee cap for the selected [FeePreset].
  BigInt get _cap => _preset == FeePreset.custom
      ? (_customCapWei ?? BigInt.zero)
      : _preset.capFor(
          _quote?.baseFee ?? BigInt.zero,
          _quote?.maxPriorityFeePerGas ?? BigInt.zero,
        );

  @override
  void initState() {
    super.initState();
    final String? recipient = widget.initialRecipient;
    if (recipient != null && recipient.isNotEmpty) {
      _addressController.text = _extractAddress(recipient);
    }
    final String? amount = widget.initialAmount;
    if (amount != null && amount.isNotEmpty) {
      _amountController.text = amount;
    }
    _loadFee();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  NetworkConfig get _network => context.read<SettingsController>().network;

  BigInt get _enteredAmount =>
      Units.parse(_amountController.text, _decimals) ?? BigInt.zero;

  BigInt get _effectiveFee {
    if (_quote != null) {
      // The cap is the most per gas the transfer can cost, times the limit.
      return _cap * _quote!.gasLimit;
    }
    return _estimate ?? BigInt.zero;
  }

  /// The native amount that leaves the account (zero for a token transfer).
  BigInt get _nativeOut => _isToken ? BigInt.zero : _enteredAmount;

  BigInt get _total =>
      _nativeOut + (_enteredAmount > BigInt.zero ? _effectiveFee : BigInt.zero);

  /// A token send must cover the token amount and, separately, the native fee;
  /// a native send must cover amount + fee from one balance.
  bool get _hasEnoughFunds => _isToken
      ? _enteredAmount <= _balance && _effectiveFee <= _nativeBalance
      : _total <= _nativeBalance;

  AddressValidation get _addressValidation =>
      AddressValidator.validate(_network, _addressController.text);

  /// A saved or already-seen address the entered recipient imitates.
  ///
  /// Address poisoning works by sending a worthless token from an address that
  /// copies the visible ends of a contract the user trusts; the victim then
  /// sends real funds to the attacker. The comparison runs on every keystroke,
  /// so it is done against the small set of addresses this wallet already
  /// deals with rather than any on-chain index.
  String? get _impersonatedAddress {
    final NetworkConfig network = _network;
    if (network.chain != ChainKind.evm) {
      return null;
    }
    final String recipient = _extractAddress(_addressController.text.trim());
    if (recipient.isEmpty) {
      return null;
    }
    return AddressGuard.impersonates(recipient, _knownAddresses(network));
  }

  /// Every address the user has deliberately saved or sent to on [network].
  ///
  /// Excludes incoming counterparties: those are exactly the addresses an
  /// attacker chooses, so trusting them would flag the real counterparty.
  List<String> _knownAddresses(NetworkConfig network) => <String>[
        for (final Contact contact
            in context.read<ContactsController>().contacts)
          if (contact.networkId == network.id) contact.address,
        for (final ChainTransaction tx
            in context.read<WalletController>().snapshot?.transactions ??
                const <ChainTransaction>[])
          if (!tx.isIncoming) tx.counterparty,
      ];

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
        _decimals,
        _symbol,
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
    final ({BigInt baseFee, BigInt maxPriorityFeePerGas, BigInt gasLimit})?
        quote = await controller.prepare(
      to: _signTo(recipient),
      value: _nativeOut,
      data: _calldata(recipient),
    );
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
      appBar: AppBar(title: Text('Send $_symbol')),
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
                      suffixText: _symbol,
                      errorText: _enteredAmount > BigInt.zero && !_hasEnoughFunds
                          ? _isToken
                              ? 'Not enough $_symbol, or too little '
                                  '${network.symbol} for the fee'
                              : 'Not enough funds for amount + fee'
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
                    // A valid checksum is not the same as a trustworthy
                    // address, so the whole field is re-validated on every
                    // keystroke to drive the poisoning warning below.
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
                  if (_impersonatedAddress case final String known) ...[
                    const SizedBox(height: 12),
                    _PoisonWarning(knownAddress: known),
                  ],
                  if (_quote != null) ...<Widget>[
                    const SizedBox(height: 18),
                    _FeePresetSelector(
                      value: _preset,
                      onChanged: _onPresetChanged,
                    ),
                    if (_preset == FeePreset.custom) ...<Widget>[
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () => _onPresetChanged(FeePreset.custom),
                          icon: const Icon(Icons.edit_rounded, size: 18),
                          label: Text(
                            '${Units.format(_priority, 9, group: false)} gwei tip · '
                            '${Units.format(_cap, 9, group: false)} gwei cap',
                          ),
                        ),
                      ),
                    ],
                  ],
                  const SizedBox(height: 20),
                  _SummaryCard(
                    network: network,
                    currency: currency,
                    amount: _enteredAmount,
                    amountDecimals: _decimals,
                    amountSymbol: _symbol,
                    showTotal: !_isToken,
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
    // A token send leaves the native balance untouched, so MAX is the whole
    // token holding; a native send keeps the fee back.
    final BigInt max = _isToken
        ? _balance
        : (_balance > _effectiveFee ? _balance - _effectiveFee : BigInt.zero);
    _amountController.text = Units.format(
      max,
      _decimals,
      maxDecimals: _decimals,
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

  /// The `to` field of the signed transaction: the token contract for an
  /// ERC-20 send, or the recipient for a native one.
  String _signTo(String recipient) =>
      _isToken ? widget.token!.contractAddress : recipient;

  /// ERC-20 calldata for the entered recipient and amount, or `null` for a
  /// native transfer.
  Uint8List? _calldata(String recipient) {
    if (!_isToken) {
      return null;
    }
    return EvmSigner.erc20TransferData(
      to: recipient,
      amount: _enteredAmount,
    );
  }

  /// The concrete EIP-1559 fee the current preset selects, captured for signing.
  ({BigInt maxFeePerGas, BigInt maxPriorityFeePerGas, BigInt gasLimit})
      _signingFees() => (
            maxFeePerGas: _cap,
            maxPriorityFeePerGas: _priority,
            gasLimit: _quote!.gasLimit,
          );

  /// Applies a preset. Picking [FeePreset.custom] opens the entry dialog and
  /// keeps the previous preset if the user cancels.
  Future<void> _onPresetChanged(FeePreset value) async {
    if (value != FeePreset.custom) {
      setState(() => _preset = value);
      return;
    }

    final BigInt baseFee = _quote?.baseFee ?? BigInt.zero;
    final BigInt tip = _quote?.maxPriorityFeePerGas ?? BigInt.zero;
    final ({BigInt tipWei, BigInt capWei})? result =
        await showDialog<({BigInt tipWei, BigInt capWei})>(
      context: context,
      builder: (_) => _CustomFeeDialog(
        initialTipWei: _customTipWei ?? FeePreset.normal.tipFor(tip),
        initialCapWei: _customCapWei ?? FeePreset.fast.capFor(baseFee, tip),
        baseFeeWei: baseFee,
      ),
    );
    if (result == null || !mounted) {
      return;
    }
    setState(() {
      _customTipWei = result.tipWei;
      _customCapWei = result.capWei;
      _preset = FeePreset.custom;
    });
  }

  Future<void> _prepare() async {
    final NetworkConfig network = _network;

    // Re-quote immediately before review: the fee moves, and the number shown
    // here is the one that gets signed.
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
    final bool canSend = network.canSign && _quote != null;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _PreparedSheet(
        network: network,
        recipient: recipient,
        amount: _enteredAmount,
        amountDecimals: _decimals,
        amountSymbol: _symbol,
        showTotal: !_isToken,
        fee: _effectiveFee,
        explorerUrl: network.explorerAddress(recipient),
        alreadySaved: alreadySaved,
        onSave: () => _saveRecipient(recipient, network),
        // Signing is only offered with a quote that will actually be used.
        onSend: canSend ? () => _signAndSend(recipient, _signingFees()) : null,
      ),
    );
  }

  /// Confirms with a fingerprint (or the PIN), signs on-device and broadcasts.
  ///
  /// The sheet is popped first so the progress dialog owns the screen, then the
  /// balance is refreshed so the UI reflects what actually left the account.
  Future<void> _signAndSend(
    String recipient,
    ({BigInt maxFeePerGas, BigInt maxPriorityFeePerGas, BigInt gasLimit}) fees,
  ) async {
    final NetworkConfig network = _network;
    final WalletIdentityController identity =
        context.read<WalletIdentityController>();
    final String? address = identity.addressFor(network);
    if (address == null) {
      return;
    }

    final bool authorized = await authorizeSensitiveAction(
      context,
      reason: 'Confirm transfer',
      title: 'Confirm transfer',
      confirmLabel: 'Send',
      icon: Icons.key_rounded,
    );
    if (!authorized || !mounted) {
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
      _runTransfer(
        controller,
        network: network,
        recipient: recipient,
        to: _signTo(recipient),
        value: _nativeOut,
        data: _calldata(recipient),
        tokenContract: _isToken ? widget.token!.contractAddress : null,
        amount: _enteredAmount,
        amountDecimals: _decimals,
        amountSymbol: _symbol,
        maxFeePerGas: fees.maxFeePerGas,
        maxPriorityFeePerGas: fees.maxPriorityFeePerGas,
        gasLimit: fees.gasLimit,
      ),
    );
  }

  /// Signs and broadcasts the already-reviewed transfer behind a progress
  /// dialog, then shows the outcome. The balance is refreshed so the UI matches
  /// the chain.
  Future<void> _runTransfer(
    SendController controller, {
    required NetworkConfig network,
    required String recipient,
    required String to,
    required BigInt value,
    required Uint8List? data,
    required String? tokenContract,
    required BigInt amount,
    required int amountDecimals,
    required String amountSymbol,
    required BigInt maxFeePerGas,
    required BigInt maxPriorityFeePerGas,
    required BigInt gasLimit,
  }) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ChangeNotifierProvider<SendController>.value(
        value: controller,
        child: TransferProgressDialog(
          to: to,
          value: value,
          data: data,
          tokenContract: tokenContract,
          tokenAmount: amount,
          maxPriorityFeePerGas: maxPriorityFeePerGas,
          maxFeePerGas: maxFeePerGas,
          gasLimit: gasLimit,
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

    // Replace the send form with the confirmation so "Done" lands on the
    // wallet, not back on a filled-in form.
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => TransferSuccessScreen(
          network: network,
          hash: hash,
          confirmed: confirmed,
          recipient: recipient,
          amount: amount,
          amountDecimals: amountDecimals,
          amountSymbol: amountSymbol,
        ),
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

/// Breakdown of the transfer: amount, network fee and (for native sends) total.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.network,
    required this.currency,
    required this.amount,
    required this.amountDecimals,
    required this.amountSymbol,
    required this.showTotal,
    required this.fee,
    required this.loadingFee,
  });

  final NetworkConfig network;
  final AppCurrency currency;
  final BigInt amount;

  /// Decimals and ticker of the amount, which differ from the network's native
  /// coin on a token transfer.
  final int amountDecimals;
  final String amountSymbol;

  /// The total row only makes sense when amount and fee share a unit.
  final bool showTotal;
  final BigInt? fee;
  final bool loadingFee;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final CoinPrice? price =
        context.select<WalletController, CoinPrice?>((s) => s.snapshot?.price);

    final BigInt effectiveFee = fee ?? BigInt.zero;
    final BigInt total = amount + (amount > BigInt.zero ? effectiveFee : BigInt.zero);

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
                amountDecimals,
                amountSymbol,
                maxDecimals: 8,
              ),
              showTotal ? fiatOf(amount) : '',
            ),
            const SizedBox(height: 12),
            _row(context, 'Max network fee', feeText, fiatOf(effectiveFee)),
            if (showTotal) ...<Widget>[
              const SizedBox(height: 14),
              Divider(color: scheme.outlineVariant, height: 1),
              const SizedBox(height: 14),
              Row(
                children: <Widget>[
                  Text(
                    'Total',
                    style:
                        text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
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
    required this.amountDecimals,
    required this.amountSymbol,
    required this.showTotal,
    required this.fee,
    required this.explorerUrl,
    required this.alreadySaved,
    required this.onSave,
    this.onSend,
  });

  final NetworkConfig network;
  final String recipient;
  final BigInt amount;
  final int amountDecimals;
  final String amountSymbol;
  final bool showTotal;
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
                amountDecimals,
                amountSymbol,
                maxDecimals: 8,
              ),
            ),
            _line(
              context,
              'Max network fee',
              fee == null
                  ? 'Unavailable'
                  : Units.formatWithSymbol(
                      fee!,
                      network.decimals,
                      network.symbol,
                      maxDecimals: 8,
                    ),
            ),
            if (showTotal)
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
                label: Text('Send $amountSymbol'),
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
      'Amount: ${Units.formatWithSymbol(amount, amountDecimals, amountSymbol)}',
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

/// Blocking warning shown when the entered recipient imitates an address the
/// wallet already deals with.
///
/// Deliberately louder than the inline field errors: the entered address is
/// perfectly valid, which is the point — the danger is in *which* address it is,
/// and only a comparison against known ones reveals that.
class _PoisonWarning extends StatelessWidget {
  const _PoisonWarning({required this.knownAddress});

  /// The trusted address this recipient appears to copy.
  final String knownAddress;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.warning_amber_rounded, color: scheme.onErrorContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'This address looks like another one you use',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: scheme.onErrorContainer,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  'It starts and ends like '
                  '${AppFormat.shortAddress(knownAddress)}, which you have '
                  'already sent to. Scammers copy the visible ends of a real '
                  'address and wait for you to send funds to it. Check the '
                  'middle of the address before continuing.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onErrorContainer,
                        height: 1.4,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Low / Normal / High / Custom fee preset selector for an EIP-1559 transfer.
class _FeePresetSelector extends StatelessWidget {
  const _FeePresetSelector({required this.value, required this.onChanged});

  final FeePreset value;
  final ValueChanged<FeePreset> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(
              Icons.speed_rounded,
              size: 18,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 10),
            Text(
              'Network fee',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SegmentedButton<FeePreset>(
          showSelectedIcon: false,
          segments: <ButtonSegment<FeePreset>>[
            for (final FeePreset preset in FeePreset.values)
              ButtonSegment<FeePreset>(
                value: preset,
                label: Text(preset.label),
              ),
          ],
          selected: <FeePreset>{value},
          onSelectionChanged: (Set<FeePreset> selection) =>
              onChanged(selection.first),
          expandedInsets: EdgeInsets.zero,
        ),
      ],
    );
  }
}

/// Entry dialog for a user-defined EIP-1559 tip and fee cap, in gwei.
class _CustomFeeDialog extends StatefulWidget {
  const _CustomFeeDialog({
    required this.initialTipWei,
    required this.initialCapWei,
    required this.baseFeeWei,
  });

  final BigInt initialTipWei;
  final BigInt initialCapWei;
  final BigInt baseFeeWei;

  @override
  State<_CustomFeeDialog> createState() => _CustomFeeDialogState();
}

class _CustomFeeDialogState extends State<_CustomFeeDialog> {
  late final TextEditingController _tip = TextEditingController(
    text: Units.format(widget.initialTipWei, 9, group: false),
  );
  late final TextEditingController _cap = TextEditingController(
    text: Units.format(widget.initialCapWei, 9, group: false),
  );
  String? _error;

  @override
  void dispose() {
    _tip.dispose();
    _cap.dispose();
    super.dispose();
  }

  void _submit() {
    final BigInt? tip = Units.parse(_tip.text, 9);
    final BigInt? cap = Units.parse(_cap.text, 9);
    if (tip == null || tip <= BigInt.zero) {
      setState(() => _error = 'Enter a priority fee above 0.');
      return;
    }
    if (cap == null || cap < tip) {
      setState(() => _error = 'The fee cap must be at least the priority fee.');
      return;
    }
    Navigator.of(context).pop((tipWei: tip, capWei: cap));
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;

    InputDecoration field(String label) => InputDecoration(
          labelText: label,
          suffixText: 'gwei',
        );

    return AlertDialog(
      icon: const Icon(Icons.tune_rounded),
      title: const Text('Custom network fee'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Current base fee: '
            '${Units.format(widget.baseFeeWei, 9, group: false)} gwei.',
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _tip,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            ],
            decoration: field('Priority fee (tip)'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _cap,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            ],
            decoration: field('Max fee (cap)'),
          ),
          if (_error != null) ...<Widget>[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: text.bodySmall?.copyWith(color: scheme.error),
            ),
          ],
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Apply'),
        ),
      ],
    );
  }
}
