import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/utils/feedback.dart';
import '../../data/wallet/seed_vault.dart';
import '../../state/wallet_identity_controller.dart';
import '../../shared/widgets/pin_confirm_dialog.dart';

/// Re-authenticates the user before a privileged action: sending funds,
/// replacing a stuck transaction, revoking an approval, or revealing the
/// recovery phrase.
///
/// When biometric unlock is enabled the fingerprint is **required** — it is a
/// second, unguessable factor and the whole point of turning it on. The 6-digit
/// PIN is only asked for on devices without biometrics, unless the caller
/// explicitly allows the fallback (see [allowPinFallback]).
///
/// Returns `false` when the user cancels or the check fails, so the caller must
/// not proceed. Never throws: a failed prompt is a normal outcome.
Future<bool> authorizeSensitiveAction(
  BuildContext context, {
  required String reason,
  required String title,
  required String confirmLabel,
  IconData icon = Icons.key_rounded,
  bool allowPinFallback = false,
}) async {
  final WalletIdentityController identity =
      context.read<WalletIdentityController>();

  if (identity.biometricsEnabled) {
    final bool passed = await identity.confirmWithBiometrics(reason: reason);
    if (passed || !allowPinFallback) {
      return passed;
    }
    // Falls through to the PIN: the caller decided losing the phrase behind a
    // flaky sensor is worse than typing six digits.
    if (!context.mounted) {
      return false;
    }
  }

  final String? pin = await PinConfirmDialog.show(
    context,
    title: title,
    confirmLabel: confirmLabel,
    icon: icon,
  );
  if (pin == null || !context.mounted) {
    return false;
  }

  try {
    await identity.verifyPin(pin);
    return true;
  } on SeedVaultException catch (error) {
    if (context.mounted) {
      showAppSnackBar(context, error.message, icon: Icons.lock_outline_rounded);
    }
    return false;
  }
}
