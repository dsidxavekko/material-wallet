import 'package:crypto_wallet/data/networks/chain_models.dart';
import 'package:crypto_wallet/data/wallet/recipient_check.dart';
import 'package:flutter_test/flutter_test.dart';

/// The pre-signature recipient check (goals §B1). Every branch of the decision
/// table gets a case against the canonical explorer answer, because this is the
/// one guard that stands between a mistyped address and lost funds — and it
/// errs toward speaking up, never toward a silent pass.
void main() {
  const String recipient = '0x9858EfFD232B4033E47d90003D41EC34EcaEda94';
  const String usdc = '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48';

  RecipientCheck call({
    String to = recipient,
    bool isTokenTransfer = false,
    String? tokenContract,
    AddressInfo? info,
    bool lookupFailed = false,
  }) =>
      checkRecipient(
        recipient: to,
        isTokenTransfer: isTokenTransfer,
        tokenContract: tokenContract,
        info: info,
        lookupFailed: lookupFailed,
      );

  group('AddressInfo.fromJson', () {
    test('reads the signals the check depends on', () {
      final AddressInfo info = AddressInfo.fromJson(<String, Object?>{
        'is_contract': true,
        'is_scam': false,
        'token': <String, Object?>{'symbol': 'USDC'},
        'ens_domain_name': '商店.eth',
      });
      expect(info.isContract, isTrue);
      expect(info.isScam, isFalse);
      expect(info.isTokenContract, isTrue);
      expect(info.tokenSymbol, 'USDC');
      expect(info.ensDomain, '商店.eth');
    });

    test('treats a plain EOA with no token as flag-free', () {
      final AddressInfo info =
          AddressInfo.fromJson(<String, Object?>{'is_contract': false});
      expect(info.isContract, isFalse);
      expect(info.isScam, isFalse);
      expect(info.isTokenContract, isFalse);
      expect(info.tokenSymbol, isNull);
    });
  });

  group('checkRecipient', () {
    test('a token sent to its own contract is blocked, without a lookup', () {
      final RecipientCheck check = call(
        to: usdc.toUpperCase().replaceFirst('0X', '0x'),
        isTokenTransfer: true,
        tokenContract: usdc,
      );
      expect(check.risk, RecipientRisk.block);
      expect(check.maySend, isFalse);
      expect(check.message, isNotEmpty);
    });

    test('the same address as a native send is not blocked', () {
      final RecipientCheck check = call(
        to: usdc,
        isTokenTransfer: false,
        tokenContract: usdc,
      );
      expect(check.maySend, isTrue);
    });

    test('a token sent to a different address is fine', () {
      final RecipientCheck check = call(
        to: recipient,
        isTokenTransfer: true,
        tokenContract: usdc,
      );
      expect(check.maySend, isTrue);
    });

    test('a flagged scam address warns but does not block', () {
      final RecipientCheck check = call(
        info: const AddressInfo(isContract: false, isScam: true),
      );
      expect(check.risk, RecipientRisk.warn);
      expect(check.maySend, isTrue);
    });

    test('a token contract warns, naming the token', () {
      final RecipientCheck check = call(
        info: const AddressInfo(
          isContract: true,
          isScam: false,
          tokenSymbol: 'USDC',
        ),
      );
      expect(check.risk, RecipientRisk.warn);
      expect(check.message, contains('USDC'));
    });

    test('a scam flag outranks the plainer contract notice', () {
      final RecipientCheck check = call(
        info: const AddressInfo(
          isContract: true,
          isScam: true,
          tokenSymbol: 'USDC',
        ),
      );
      expect(check.risk, RecipientRisk.warn);
      expect(check.message, isNot(contains('USDC')));
    });

    test('a contract that is not a token is only informational', () {
      final RecipientCheck check = call(
        info: const AddressInfo(isContract: true, isScam: false),
      );
      expect(check.risk, RecipientRisk.info);
      expect(check.maySend, isTrue);
    });

    test('a plain account raises nothing', () {
      final RecipientCheck check = call(
        info: const AddressInfo(isContract: false, isScam: false),
      );
      expect(check.risk, RecipientRisk.none);
    });

    test('a chain with no address index raises nothing', () {
      expect(call().risk, RecipientRisk.none);
    });

    test('a failed lookup is reported, never taken as a pass', () {
      final RecipientCheck check = call(lookupFailed: true);
      expect(check.risk, RecipientRisk.warn);
      expect(check.message, contains('verify'));
    });

    test('a failed lookup still blocks a token sent to its own contract', () {
      final RecipientCheck check = call(
        to: usdc,
        isTokenTransfer: true,
        tokenContract: usdc,
        lookupFailed: true,
      );
      expect(check.risk, RecipientRisk.block);
    });
  });
}
