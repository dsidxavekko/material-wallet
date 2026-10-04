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

  /// `true` for a 24-word phrase, `false` for the default 12-word one.
  bool get isExtended => words.length >= 24;

  Map<String, Object?> toJson() => <String, Object?>{
        'mnemonic': mnemonic,
        'createdAt': createdAt.toIso8601String(),
      };

  factory WalletAccount.fromJson(Map<String, Object?> json) {
    return WalletAccount(
      mnemonic: json['mnemonic']! as String,
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
              DateTime.now(),
    );
  }
}
