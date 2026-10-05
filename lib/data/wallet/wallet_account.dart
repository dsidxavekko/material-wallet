/// A wallet created or imported on this device.
///
/// Only the BIP-39 mnemonic is persisted — every address and key is derived
/// from it on demand, so nothing else needs to be stored.
class WalletAccount {
  const WalletAccount({required this.mnemonic, required this.createdAt});

  /// The BIP-39 recovery phrase (12 or 24 lowercase words).
  final String mnemonic;

  final DateTime createdAt;

  List<String> get words => mnemonic.split(' ');
}