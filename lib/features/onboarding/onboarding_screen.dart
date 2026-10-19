import 'package:flutter/material.dart';

import 'create_wallet_screen.dart';
import '../wallets/watch_wallet_screen.dart';
import 'import_wallet_screen.dart';
import '../../l10n/l10n.dart';

/// First screen shown when no wallet exists on the device.
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Spacer(),
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(26),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[scheme.primary, scheme.tertiary],
                  ),
                ),
                child: const Icon(
                  Icons.account_balance_wallet_rounded,
                  color: Colors.white,
                  size: 42,
                ),
              ),
              const SizedBox(height: 28),
              Text(
                'Material Wallet',
                style: text.displaySmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                context.l10n.aSelfCustodialWalletYour,
                style: text.bodyLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const CreateWalletScreen(),
                  ),
                ),
                icon: const Icon(Icons.add_circle_outline_rounded),
                label: Text(context.l10n.createANewWallet),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ImportWalletScreen(),
                  ),
                ),
                icon: const Icon(Icons.download_rounded),
                label: Text(context.l10n.iAlreadyHaveAWallet),
              ),
              const SizedBox(height: 4),
              TextButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const WatchWalletScreen(),
                  ),
                ),
                icon: const Icon(Icons.visibility_outlined),
                label: Text(context.l10n.justWatchAnAddress),
              ),
              const SizedBox(height: 18),
              Center(
                child: Text(
                  'BIP-39 · Bitcoin (BIP-84) · EVM (BIP-44)',
                  style: text.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
