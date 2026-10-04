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
import '../../shared/widgets/empty_state.dart';
import '../../state/settings_controller.dart';
import '../../state/wallet_controller.dart';
import '../scan/scan_screen.dart';

/// Prepares an outgoing transfer against the **live** balance of the active
/// network.
///
/// The transaction is fully validated and the real network fee is fetched, but
/// this build does not sign or broadcast — the confirmation sheet says so
/// explicitly and lets the details be copied instead.
class SendScreen extends StatefulWidget {
  const SendScreen({super.key});

  @override
  State<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends State<SendScreen> {
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();

  BigInt? _fee;
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

  BigInt get _effectiveFee => _fee ?? BigInt.zero;

  BigInt get _total => _enteredAmount + (_enteredAmount > BigInt.zero ? _effectiveFee : BigInt.zero);

  bool get _hasEnoughFunds => _total <= _balance;

  bool get _isValid =>
      _enteredAmount > BigInt.zero &&
      _hasEnoughFunds &&
      _addressController.text.trim().length >= 8;

  String get _availableLabel => Units.formatWithSymbol(
        _balance,
        _network.decimals,
        _network.symbol,
        maxDecimals: 8,
      );

  Future<void> _loadFee() async {
    final BigInt? fee = await context.read<WalletController>().estimateFee();
    if (mounted) {
      setState(() {
        _fee = fee;
        _loadingFee = false;
      });
    }
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
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
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
                    fee: _fee,
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
    _addressController.text = text;
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
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _PreparedSheet(
        network: network,
        recipient: _addressController.text.trim(),
        amount: _enteredAmount,
        fee: _fee,
        explorerUrl: network.explorerAddress(_addressController.text.trim()),
      ),
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
/// This build does not sign or broadcast transactions, and says so plainly
/// instead of pretending the funds moved.
class _PreparedSheet extends StatelessWidget {
  const _PreparedSheet({
    required this.network,
    required this.recipient,
    required this.amount,
    required this.fee,
    required this.explorerUrl,
  });

  final NetworkConfig network;
  final String recipient;
  final BigInt amount;
  final BigInt? fee;
  final String explorerUrl;

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
                      'Broadcasting is not enabled in this build — nothing was '
                      'sent to the network. Restore your recovery phrase in a '
                      'signing wallet to move funds.',
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
            FilledButton.icon(
              onPressed: () => _copy(context),
              icon: const Icon(Icons.copy_rounded),
              label: const Text('Copy details'),
            ),
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
