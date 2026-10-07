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
}
