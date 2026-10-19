import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/utils/app_log.dart';
import '../../core/utils/explorer.dart';
import '../../core/utils/feedback.dart';
import '../../core/utils/units.dart';
import '../../data/deep_links/payment_link.dart';
import '../../data/networks/network_config.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/qr_card.dart';
import '../../state/settings_controller.dart';
import '../../state/wallet_controller.dart';
import '../../l10n/l10n.dart';

/// Shows the wallet's **real** receive address for the active network, both as
/// text and as a scannable QR code.
///
/// Optionally asks for an amount: the QR then carries a payment-request URI
/// (BIP-21, EIP-681, Solana Pay, `aptos:`) that a paying wallet fills in on
/// its own, and the request can be shared as text.
class ReceiveScreen extends StatefulWidget {
  const ReceiveScreen({super.key});

  @override
  State<ReceiveScreen> createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends State<ReceiveScreen> {
  final TextEditingController _amount = TextEditingController();

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final WalletController wallet = context.watch<WalletController>();
    final NetworkConfig network =
        context.select<SettingsController, NetworkConfig>((s) => s.network);
    final String? address = wallet.address;
    final BigInt? requested = Units.parse(_amount.text, network.decimals);
    final bool hasRequest = address != null &&
        requested != null &&
        requested > BigInt.zero;
    final String? payload = address == null
        ? null
        : buildPaymentLink(
            network: network,
            address: address,
            amount: hasRequest ? requested : null,
          );
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme scheme = Theme.of(context).colorScheme;

    if (address == null) {
      return Scaffold(
        appBar: AppBar(title: Text(context.l10n.receive)),
        body: EmptyState(
          icon: Icons.key_off_rounded,
          title: context.l10n.noWalletFound,
          message: context.l10n.unlockYourWalletToGenerate,
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.receive)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: <Widget>[
          Card(
            child: ListTile(
              leading: Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: network.color.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  network.symbol.length > 3
                      ? network.symbol.substring(0, 3)
                      : network.symbol,
                  style: text.labelSmall?.copyWith(
                    color: network.color,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              title: Text(
                network.name,
                style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                network.isTestnet
                    ? context.l10n.testnet(network.group)
                    : network.group,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Center(child: QrCard(data: payload!)),
          const SizedBox(height: 20),
          Center(
            child: Text(
              hasRequest
                  ? context.l10n.scanToPay(Units.format(requested, network.decimals), network.symbol)
                  : context.l10n.scanToReceive(network.symbol),
              style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text(
              context.l10n.onlySendOnToThis(network.symbol, network.name),
              textAlign: TextAlign.center,
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: context.l10n.requestAnAmountOptional,
              suffixText: network.symbol,
              helperText: _amount.text.trim().isNotEmpty && !hasRequest
                  ? context.l10n.enterAValidAmount
                  : null,
            ),
            onChanged: (_) => setState(() {}),
          ),
          if (hasRequest) ...<Widget>[
            const SizedBox(height: 10),
            FilledButton.tonalIcon(
              onPressed: () => _shareRequest(
                context,
                network: network,
                address: address,
                amount: requested,
                link: payload,
              ),
              icon: const Icon(Icons.ios_share_rounded),
              label: Text(context.l10n.sharePaymentRequest),
            ),
          ],
          const SizedBox(height: 26),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    context.l10n.yourAddress,
                    style: text.labelLarge
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    address,
                    style: text.bodyMedium
                        ?.copyWith(height: 1.45, letterSpacing: 0.2),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: () => _copy(context, address),
            icon: const Icon(Icons.copy_rounded),
            label: Text(context.l10n.copyAddress),
          ),
          const SizedBox(height: 10),
          FilledButton.tonalIcon(
            onPressed: () => openExplorer(
              context,
              network.explorerAddress(address),
            ),
            icon: const Icon(Icons.open_in_new_rounded),
            label: Text(context.l10n.viewOnExplorer),
          ),
        ],
      ),
    );
  }

  Future<void> _shareRequest(
    BuildContext context, {
    required NetworkConfig network,
    required String address,
    required BigInt amount,
    required String link,
  }) async {
    try {
      await SharePlus.instance.share(
        ShareParams(
          text: context.l10n.pleaseSendOnTo(Units.format(amount, network.decimals), network.symbol, network.name, address, link),
          subject: context.l10n.paymentRequest,
        ),
      );
    } catch (error, stackTrace) {
      AppLog.warning('Could not share the payment request', error, stackTrace);
      if (context.mounted) {
        showAppSnackBar(
          context,
          context.l10n.couldNotShareTheRequest,
          icon: Icons.error_outline_rounded,
        );
      }
    }
  }

  Future<void> _copy(BuildContext context, String address) async {
    await Clipboard.setData(ClipboardData(text: address));
    if (context.mounted) {
      showAppSnackBar(
        context,
        context.l10n.addressCopiedToClipboard,
        icon: Icons.check_circle_outline_rounded,
      );
    }
  }
}
