/// The family of networks a coin belongs to, which determines how a receive
/// address is derived from the wallet's seed phrase.
enum ChainKind {
  /// Bitcoin, derived with BIP-84 (`bc1q…` native SegWit).
  bitcoin,

  /// Ethereum and every EVM-compatible chain, derived with BIP-44 (`0x…`).
  evm,

  /// Solana, derived with SLIP-0010 ed25519 (`HAgk…` base58).
  solana,

  /// Aptos, derived with SLIP-0010 ed25519 (`0x…` authentication key).
  aptos;

  String get label => switch (this) {
        ChainKind.bitcoin => 'Bitcoin (BIP-84)',
        ChainKind.evm => 'EVM (BIP-44)',
        ChainKind.solana => 'Solana (SLIP-0010)',
        ChainKind.aptos => 'Aptos (SLIP-0010)',
      };
}
