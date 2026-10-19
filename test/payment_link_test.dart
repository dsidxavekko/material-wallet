import 'package:crypto_wallet/data/deep_links/payment_link.dart';
import 'package:crypto_wallet/data/networks/network_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parsePaymentLink', () {
    test('parses a BIP-21 bitcoin link with an amount', () {
      final PaymentLink? link =
          parsePaymentLink(Uri.parse('bitcoin:bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu?amount=0.5'));

      expect(link, isNotNull);
      expect(link!.network.id, NetworkCatalog.bitcoin.id);
      expect(link.recipient, 'bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu');
      expect(link.amount, '0.5');
    });

    test('parses an EIP-681 ethereum link and defaults to Ethereum', () {
      final PaymentLink? link = parsePaymentLink(
        Uri.parse('ethereum:0x9858EfFD232B4033E47d90003D41EC34EcaEda94'),
      );

      expect(link, isNotNull);
      expect(link!.network.id, NetworkCatalog.ethereum.id);
      expect(link.recipient, '0x9858EfFD232B4033E47d90003D41EC34EcaEda94');
      expect(link.amount, isNull);
    });

    test('reads the chain id from an ethereum link', () {
      final PaymentLink? link = parsePaymentLink(
        Uri.parse('ethereum:0x9858EfFD232B4033E47d90003D41EC34EcaEda94@137'),
      );

      expect(link!.network.id, NetworkCatalog.polygon.id);
      expect(link.recipient, '0x9858EfFD232B4033E47d90003D41EC34EcaEda94');
    });

    test('converts an EIP-681 wei value to whole ether', () {
      final PaymentLink? link = parsePaymentLink(
        Uri.parse('ethereum:0x9858EfFD232B4033E47d90003D41EC34EcaEda94?value=1000000000000000000'),
      );

      expect(link!.amount, '1');
    });

    test('parses a Solana Pay link', () {
      final PaymentLink? link = parsePaymentLink(
        Uri.parse('solana:HAgk14JpMQLgt6rVgv7cBQFJWFrrrdNsZba4yzN3Uy7F?amount=2'),
      );

      expect(link!.network.id, NetworkCatalog.solana.id);
      expect(link.recipient, 'HAgk14JpMQLgt6rVgv7cBQFJWFrrrdNsZba4yzN3Uy7F');
      expect(link.amount, '2');
    });

    test('parses an aptos link', () {
      final PaymentLink? link = parsePaymentLink(
        Uri.parse('aptos:0x1?amount=1.5'),
      );

      expect(link!.network.id, NetworkCatalog.aptos.id);
      expect(link.recipient, '0x1');
      expect(link.amount, '1.5');
    });

    test('returns null for an unknown scheme or missing address', () {
      expect(parsePaymentLink(Uri.parse('https://example.com')), isNull);
      expect(parsePaymentLink(Uri.parse('bitcoin:')), isNull);
    });
  });

  group('parsePaymentLink — EIP-681 token transfer', () {
    const String usdc = '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48';
    const String shop = '0x9858EfFD232B4033E47d90003D41EC34EcaEda94';

    test('opens a token transfer: the shop is the recipient, not the contract',
        () {
      final PaymentLink? link = parsePaymentLink(Uri.parse(
        'ethereum:$usdc@1/transfer?address=$shop&uint256=100000000',
      ));

      expect(link, isNotNull);
      expect(link!.isTokenTransfer, isTrue);
      expect(link.network.id, NetworkCatalog.ethereum.id);
      expect(link.tokenContract, usdc);
      // The old behaviour made the token contract itself the recipient.
      expect(link.recipient, shop);
      expect(link.uint256, '100000000');
      expect(link.amount, isNull);
    });

    test('keeps the chain id of a token transfer', () {
      final PaymentLink? link = parsePaymentLink(Uri.parse(
        'ethereum:$usdc@137/transfer?address=$shop&uint256=5',
      ));

      expect(link!.network.id, NetworkCatalog.polygon.id);
      expect(link.isTokenTransfer, isTrue);
    });

    test('a transfer without a chain id defaults to Ethereum', () {
      final PaymentLink? link = parsePaymentLink(Uri.parse(
        'ethereum:$usdc/transfer?address=$shop&uint256=7',
      ));

      expect(link!.network.id, NetworkCatalog.ethereum.id);
      expect(link.uint256, '7');
    });

    test('rejects any function other than transfer', () {
      expect(
        parsePaymentLink(Uri.parse(
          'ethereum:$usdc@1/approve?address=$shop&uint256=100',
        )),
        isNull,
      );
    });

    test('rejects a transfer without a recipient or amount', () {
      expect(
        parsePaymentLink(Uri.parse('ethereum:$usdc/transfer?uint256=100')),
        isNull,
      );
      expect(
        parsePaymentLink(Uri.parse('ethereum:$usdc/transfer?address=$shop')),
        isNull,
      );
      expect(
        parsePaymentLink(
          Uri.parse('ethereum:$usdc/transfer?address=$shop&uint256=abc'),
        ),
        isNull,
      );
    });
  });

  group('buildPaymentLink (D1)', () {
    const String evm = '0x9858EfFD232B4033E47d90003D41EC34EcaEda94';

    PaymentLink roundTrip(NetworkConfig network, String address, BigInt amount) {
      final String uri =
          buildPaymentLink(network: network, address: address, amount: amount);
      final PaymentLink? parsed = parsePaymentLink(Uri.parse(uri));
      expect(parsed, isNotNull, reason: uri);
      return parsed!;
    }

    test('without an amount the QR stays the plain address', () {
      expect(
        buildPaymentLink(network: NetworkCatalog.ethereum, address: evm),
        evm,
      );
      expect(
        buildPaymentLink(
          network: NetworkCatalog.ethereum,
          address: evm,
          amount: BigInt.zero,
        ),
        evm,
      );
    });

    test('Bitcoin: BIP-21, mainnet and testnet', () {
      final PaymentLink main = roundTrip(
        NetworkCatalog.bitcoin,
        'bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu',
        BigInt.from(50000000),
      );
      expect(main.network.id, NetworkCatalog.bitcoin.id);
      expect(main.amount, '0.5');

      final PaymentLink test = roundTrip(
        NetworkCatalog.bitcoinTestnet,
        'tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kxpjzsx',
        BigInt.from(1234),
      );
      expect(test.network.id, NetworkCatalog.bitcoinTestnet.id);
      expect(test.amount, '0.00001234');
    });

    test('EVM: EIP-681 carries the chain id and the amount in wei', () {
      final String uri = buildPaymentLink(
        network: NetworkCatalog.polygon,
        address: evm,
        amount: BigInt.parse('1500000000000000000'),
      );
      expect(uri, 'ethereum:$evm@137?value=1500000000000000000');

      final PaymentLink parsed = roundTrip(
        NetworkCatalog.polygon,
        evm,
        BigInt.parse('1500000000000000000'),
      );
      expect(parsed.network.id, NetworkCatalog.polygon.id);
      expect(parsed.recipient, evm);
      expect(parsed.amount, '1.5');
    });

    test('Solana Pay and aptos: round trip', () {
      final PaymentLink sol = roundTrip(
        NetworkCatalog.solana,
        '11111111111111111111111111111112',
        BigInt.from(2500000000),
      );
      expect(sol.network.id, NetworkCatalog.solana.id);
      expect(sol.amount, '2.5');

      final PaymentLink apt = roundTrip(
        NetworkCatalog.aptos,
        '0x1',
        BigInt.from(100000000),
      );
      expect(apt.network.id, NetworkCatalog.aptos.id);
      expect(apt.amount, '1');
    });
  });
}
