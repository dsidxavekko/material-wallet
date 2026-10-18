import '../networks/chain_models.dart';

/// How serious a finding about the recipient is.
///
/// [block] refuses to sign, [warn] demands a conscious confirmation, [info]
/// only informs, [none] found nothing to say.
enum RecipientRisk { none, info, warn, block }

/// The result of the pre-signature recipient check.
class RecipientCheck {
  const RecipientCheck(this.risk, this.message);

  static const RecipientCheck none = RecipientCheck(RecipientRisk.none, '');

  final RecipientRisk risk;
  final String message;

  bool get maySend => risk != RecipientRisk.block;
}

/// What to tell the user about a recipient just before they sign.
///
/// [info] is the live explorer answer; `null` means either the chain has no
/// address index (Bitcoin, Solana, Aptos, JSON-RPC-only EVM) or the address
/// has no history — both are perfectly normal and raise no flag.
/// [lookupFailed] is `true` when the index was asked and did not answer: a
/// failed check is reported, never treated as a pass.
///
/// [isTokenTransfer] / [tokenContract] implement the one rule that needs no
/// network at all: sending a token to its own contract address sends it to
/// nobody.
RecipientCheck checkRecipient({
  required String recipient,
  required bool isTokenTransfer,
  required String? tokenContract,
  AddressInfo? info,
  bool lookupFailed = false,
}) {
  if (isTokenTransfer &&
      tokenContract != null &&
      recipient.toLowerCase() == tokenContract.toLowerCase()) {
    return const RecipientCheck(
      RecipientRisk.block,
      'This is the token contract itself. Tokens sent to their own contract '
          'are almost always lost.',
    );
  }

  if (lookupFailed) {
    return const RecipientCheck(
      RecipientRisk.warn,
      'Could not verify this address. Check it character by character.',
    );
  }

  if (info == null) {
    return RecipientCheck.none;
  }

  if (info.isScam) {
    return const RecipientCheck(
      RecipientRisk.warn,
      'This address is flagged as a scam.',
    );
  }

  if (info.isTokenContract) {
    return RecipientCheck(
      RecipientRisk.warn,
      'This address is the contract of ${info.tokenSymbol}. Funds sent to a '
          'token contract are usually lost.',
    );
  }

  if (info.isContract) {
    return const RecipientCheck(
      RecipientRisk.info,
      'This is a contract (a wallet app, an exchange or a Safe), not a '
          'person.',
    );
  }

  return RecipientCheck.none;
}
