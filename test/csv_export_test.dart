import 'package:crypto_wallet/core/utils/csv_export.dart';
import 'package:crypto_wallet/data/networks/chain_models.dart';
import 'package:crypto_wallet/data/networks/network_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ChainTransaction tx({
    required String hash,
    required BigInt amount,
    BigInt? fee,
    String counterparty = 'bc1qrecipient',
    bool incoming = false,
    bool confirmed = true,
    bool failed = false,
  }) =>
      ChainTransaction(
        hash: hash,
        timestamp: DateTime.utc(2026, 3, 4, 5, 6, 7),
        amount: amount,
        fee: fee ?? BigInt.zero,
        counterparty: counterparty,
        isIncoming: incoming,
        confirmed: confirmed,
        failed: failed,
      );

  AccountSnapshot snapshot(List<ChainTransaction> transactions) =>
      AccountSnapshot(
        network: NetworkCatalog.bitcoin,
        address: 'bc1qown',
        balance: BigInt.zero,
        transactions: transactions,
        chart: const <double>[],
        fetchedAt: DateTime.utc(2026, 3, 4),
      );

  test('writes a header and one row per transaction', () {
    final String csv = buildActivityCsv(
      snapshot(<ChainTransaction>[
        tx(hash: 'aa', amount: -BigInt.from(150000000)),
        tx(hash: 'bb', amount: BigInt.from(25000000), incoming: true),
      ]),
    );

    final List<String> lines =
        csv.trim().split('\n').map((String l) => l.trim()).toList();
    expect(lines.length, 3);
    expect(
      lines.first,
      'date,network,direction,amount,ticker,fee,counterparty,hash,status',
    );
    expect(lines[1], startsWith('2026-03-04T05:06:07.000Z,Bitcoin,out,1.5,BTC,'));
    expect(lines[1], endsWith(',bc1qrecipient,aa,confirmed'));
    expect(lines[2], contains(',in,0.25,BTC,'));
  });

  test('amounts are plain numbers, the sign lives in direction', () {
    final String csv = buildActivityCsv(
      snapshot(<ChainTransaction>[
        tx(hash: 'aa', amount: -BigInt.from(150000000), incoming: false),
      ]),
    );

    // No grouping separator and no minus sign glued to the number.
    expect(csv, contains(',out,1.5,BTC,'));
    expect(csv, isNot(contains('1,500')));
    expect(csv, isNot(contains('-1.5')));
  });

  test('quotes a counterparty label carrying commas and quotes', () {
    final String csv = buildActivityCsv(
      snapshot(<ChainTransaction>[
        tx(
          hash: 'aa',
          amount: BigInt.one,
          counterparty: 'Alice, "the whale"',
        ),
      ]),
    );

    expect(csv, contains('"Alice, ""the whale"""'));
  });

  test('reports pending and failed rows', () {
    final String csv = buildActivityCsv(
      snapshot(<ChainTransaction>[
        tx(hash: 'aa', amount: BigInt.one, confirmed: false),
        tx(hash: 'bb', amount: BigInt.one, failed: true),
      ]),
    );

    final List<String> lines = csv.trim().split('\n');
    expect(lines[1], endsWith(',pending'));
    expect(lines[2], endsWith(',failed'));
  });

  test('an empty history is just the header', () {
    final String csv = buildActivityCsv(snapshot(const <ChainTransaction>[]));

    expect(csv.trim().split('\n').length, 1);
  });
}
