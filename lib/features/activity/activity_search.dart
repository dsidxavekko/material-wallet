import '../../data/networks/chain_models.dart';
import '../../data/networks/network_config.dart';

/// Whether [tx] matches the activity search [query].
///
/// The query is matched, case-insensitively and as a substring, against what a
/// person remembers about a payment: the other party's address or saved label,
/// the transaction hash, the coin or token ticker, and their own note. An empty
/// query matches everything.
bool matchesActivityQuery(
  ChainTransaction tx,
  String query, {
  required NetworkConfig network,
  String? counterpartyLabel,
  String? note,
}) {
  final String needle = query.trim().toLowerCase();
  if (needle.isEmpty) {
    return true;
  }
  final List<String?> haystack = <String?>[
    tx.hash,
    tx.displayCounterparty,
    tx.counterparty,
    tx.ticker(network),
    tx.token?.contract,
    counterpartyLabel,
    note,
  ];
  return haystack.any(
    (String? field) => field != null && field.toLowerCase().contains(needle),
  );
}
