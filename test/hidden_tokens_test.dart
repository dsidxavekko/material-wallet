import 'package:crypto_wallet/data/networks/chain_models.dart';
import 'package:crypto_wallet/features/home/widgets/token_list.dart';
import 'package:crypto_wallet/core/utils/formatters.dart';
import 'package:crypto_wallet/state/hidden_tokens_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

TokenBalance _token(String contract, {String symbol = 'SPAM'}) => TokenBalance(
      symbol: symbol,
      name: '$symbol token',
      decimals: 6,
      balance: BigInt.from(5000000),
      contractAddress: contract,
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('hidden tokens', () {
    test('survive a restart', () async {
      final HiddenTokensController first = HiddenTokensController();
      await first.load();
      await first.setHidden('ethereum', _token('0xAbC'), true);

      final HiddenTokensController second = HiddenTokensController();
      await second.load();
      expect(second.isHidden('ethereum', _token('0xAbC')), isTrue);
    });

    test('match the contract case-insensitively', () async {
      final HiddenTokensController hidden = HiddenTokensController();
      await hidden.setHidden('ethereum', _token('0xABC'), true);
      expect(hidden.isHidden('ethereum', _token('0xabc')), isTrue);
    });

    test('apply to one network only', () async {
      final HiddenTokensController hidden = HiddenTokensController();
      await hidden.setHidden('ethereum', _token('0xabc'), true);
      expect(hidden.isHidden('base', _token('0xabc')), isFalse);
    });

    test('can be shown again and are counted', () async {
      final HiddenTokensController hidden = HiddenTokensController();
      final List<TokenBalance> tokens = <TokenBalance>[
        _token('0x1'),
        _token('0x2', symbol: 'GOOD'),
      ];
      await hidden.setHidden('ethereum', tokens[0], true);
      expect(hidden.hiddenCount('ethereum', tokens), 1);

      await hidden.setHidden('ethereum', tokens[0], false);
      expect(hidden.hiddenCount('ethereum', tokens), 0);
    });

    test('a corrupt store reads as nothing hidden', () async {
      SharedPreferences.setMockInitialValues(
        <String, Object>{'nova.wallet.hiddenTokens': 'not json'},
      );
      final HiddenTokensController hidden = HiddenTokensController();
      await hidden.load();
      expect(hidden.isHidden('ethereum', _token('0x1')), isFalse);
    });
  });

  testWidgets('long-pressing a token row reports that token', (tester) async {
    TokenBalance? pressed;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TokenList(
            tokens: <TokenBalance>[_token('0x1', symbol: 'AAA')],
            currency: AppCurrency.usd,
            onTokenLongPress: (TokenBalance t) => pressed = t,
          ),
        ),
      ),
    );

    await tester.longPress(find.text('AAA token'));
    expect(pressed?.symbol, 'AAA');
  });
}
