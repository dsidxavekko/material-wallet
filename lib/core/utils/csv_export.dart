import '../../data/networks/chain_models.dart';
import 'units.dart';

/// Renders the loaded activity of [snapshot] as CSV.
///
/// One row per transaction, in the order the list already has (newest first).
/// A token transfer reports its own amount and ticker; the fee is always the
/// network coin's, so it has a ticker column of its own (`fee_ticker`).
/// Amounts are whole coins without grouping so a spreadsheet parses them as
/// numbers, and the sign lives in a separate `direction` column — a `-` glued
/// to a number is exactly the kind of thing a spreadsheet imports as text.
///
/// The counterparty may be an address-book label containing commas, so every
/// field is escaped per RFC 4180 (quote when it carries `,`, `"` or a line
/// break; double the quotes inside).
String buildActivityCsv(AccountSnapshot snapshot) {
  final int decimals = snapshot.network.decimals;

  final StringBuffer buffer = StringBuffer();
  buffer.writeln(
    'date,network,direction,amount,ticker,fee,fee_ticker,counterparty,hash,'
    'status',
  );

  for (final ChainTransaction tx in snapshot.transactions) {
    final String status = tx.failed
        ? 'failed'
        : tx.confirmed
            ? 'confirmed'
            : 'pending';
    final TokenTransferInfo? moved = tx.token;
    buffer.writeln(<String>[
      tx.timestamp.toUtc().toIso8601String(),
      snapshot.network.name,
      tx.isIncoming ? 'in' : 'out',
      moved != null
          ? Units.format(
              moved.amount,
              moved.decimals,
              maxDecimals: moved.decimals,
              group: false,
            )
          : Units.format(
              tx.amount.abs(),
              decimals,
              maxDecimals: decimals,
              group: false,
            ),
      tx.ticker(snapshot.network),
      Units.format(tx.fee, decimals, maxDecimals: decimals, group: false),
      snapshot.network.symbol,
      tx.displayCounterparty,
      tx.hash,
      status,
    ].map(_escape).join(','));
  }

  return buffer.toString();
}

/// RFC 4180 field escaping: quote only when needed, double inner quotes.
String _escape(String field) {
  if (field.contains(',') ||
      field.contains('"') ||
      field.contains('\n') ||
      field.contains('\r')) {
    return '"${field.replaceAll('"', '""')}"';
  }
  return field;
}
