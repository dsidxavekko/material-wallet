import '../../data/networks/chain_models.dart';

/// Whether [tx] matches a search [query] typed in the activity feed.
///
/// Every whitespace-separated term must appear (case-insensitively) in at
/// least one of: the hash, either counterparty address, the token ticker, the
/// address-book label or the private note. An empty query matches everything.
bool matchesActivityQuery(
  ChainTransaction tx,
  String query, {
  String? contactLabel,
  String? note,
}) {
  final List<String> terms = query
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((String t) => t.isNotEmpty)
      .toList(growable: false);
  if (terms.isEmpty) {
    return true;
  }
  final List<String> haystack = <String>[
    tx.hash,
    tx.counterparty,
    ?tx.tokenPeer,
    ?tx.tokenSymbol,
    ?contactLabel,
    ?note,
  ].map((String s) => s.toLowerCase()).toList(growable: false);
  return terms.every(
    (String term) => haystack.any((String field) => field.contains(term)),
  );
}
