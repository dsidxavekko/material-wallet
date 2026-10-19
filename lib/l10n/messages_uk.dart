/// Ukrainian for [Messages]: exact texts, then patterns for texts with values.
library;

/// `{}` in an English template stands for a value; in the Ukrainian text
/// `{1}`, `{2}` … refer to those values by position, so word order may change.
String translateToUkrainian(String english) {
  final String? exact = _exact[english];
  if (exact != null) {
    return exact;
  }
  for (final _Pattern p in _patterns) {
    final RegExpMatch? m = p.regex.firstMatch(english);
    if (m != null) {
      // Values that are messages themselves ("… Nothing was sent.") are
      // translated too; a plain value (a network name) comes back unchanged.
      final List<String> values = <String>[
        for (int i = 1; i <= m.groupCount; i++) translateToUkrainian(m.group(i)!),
      ];
      return p.build(values, m);
    }
  }
  return english;
}

class _Pattern {
  _Pattern(String template, this.build)
      : regex = RegExp(
          '^${RegExp.escape(template).replaceAll(r'\{\}', '(.+?)')}\$',
          dotAll: true,
        );

  final RegExp regex;
  final String Function(List<String> values, RegExpMatch match) build;
}

_Pattern _p(String english, String ukrainian) => _Pattern(english, (values, _) {
      String out = ukrainian;
      for (int i = 0; i < values.length; i++) {
        out = out.replaceAll('{${i + 1}}', values[i]);
      }
      return out;
    });

/// Ukrainian plural form of "day": 1 день, 2–4 дні, 5+ днів (11–14 днів).
String _days(int n) {
  final int mod10 = n % 10;
  final int mod100 = n % 100;
  if (mod10 == 1 && mod100 != 11) return '$n день';
  if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) return '$n дні';
  return '$n днів';
}

final List<_Pattern> _patterns = <_Pattern>[
  _Pattern('{} days ago', (v, m) {
    final int? n = int.tryParse(m.group(1)!);
    return n == null ? '${v[0]} дн. тому' : '${_days(n)} тому';
  }),
  _p('{} min ago', '{1} хв тому'),
  _p('{} h ago', '{1} год тому'),
  _p('Try again in {} min {}s', 'Спробуйте через {1} хв {2} с'),
  _p('Try again in {}s', 'Спробуйте через {1} с'),
  _p('Account {}', 'Акаунт {1}'),
  _p('{} recipients', 'Отримувачі ({1})'),
  _p('Network: {}', 'Мережа: {1}'),
  _p('Wallet {}', 'Гаманець {1}'),
  _p('{} is confirmed on {}.', '{1} підтверджено в {2}.'),
  _p('A transfer is confirmed on {}.', 'Переказ підтверджено в {1}.'),
  _p('New incoming transfer on {}.', 'Новий вхідний переказ у {1}.'),
  _p('{} on {}.', '{1} у {2}.'),
  _p('{} does not support sending yet.', '{1} поки не підтримує надсилання.'),
  _p('{} does not support sending.', '{1} не підтримує надсилання.'),
  _p('{} Nothing was sent.', '{1} Нічого не надіслано.'),
  _p('Could not load {}.', 'Не вдалося завантажити {1}.'),
  _p('Something went wrong while loading {}.', 'Щось пішло не так під час завантаження {1}.'),
  _p('Token transfers unavailable for {}', 'Перекази токенів недоступні для {1}'),
  _p('Invalid Solana {}.', 'Некоректна адреса Solana ({1}).'),
  _p(
    'Not enough SOL: the transfer costs {} and opens the recipient\'s token account for {}.',
    'Недостатньо SOL: переказ коштує {1} і відкриває рахунок токена отримувача за {2}.',
  ),
  _p('Not enough SOL for the network fee ({}).', 'Недостатньо SOL на комісію мережі ({1}).'),
  _p('The network would reject this transfer ({}).', 'Мережа відхилила б цей переказ ({1}).'),
  _p('The network would reject this transfer ({}). Nothing was sent.', 'Мережа відхилила б цей переказ ({1}). Нічого не надіслано.'),
  _p(
    'The recipient account is new: it needs at least {} to exist. Send {} or more.',
    'Рахунок отримувача новий: щоб існувати, йому потрібно щонайменше {1}. Надішліть {2} або більше.',
  ),
  _p(
    'This would leave {} in your account, below the {} an account must keep. Send everything or less.',
    'Це залишило б на вашому рахунку {1}, що менше за {2}, які рахунок має зберігати. Надішліть усе або менше.',
  ),
  _p('Your {} balance is lower than this amount.', 'Ваш баланс {1} менший за цю суму.'),
  _p(
    'Your {} balance dropped since the last refresh. Nothing was sent.',
    'Ваш баланс {1} зменшився після останнього оновлення. Нічого не надіслано.',
  ),
  _p(
    'Aptos needs {} available to cover the gas limit before it runs the transfer.',
    'Aptos потребує {1} доступних, щоб покрити ліміт газу, перш ніж виконати переказ.',
  ),
  _p('The node rejected the request (HTTP {}).', 'Вузол відхилив запит (HTTP {1}).'),
  _p('The node rejected the transaction (HTTP {}).', 'Вузол відхилив транзакцію (HTTP {1}).'),
  _p('The API rejected the request (HTTP {}).', 'API відхилило запит (HTTP {1}).'),
  _p(
    'This address is the contract of {}. Funds sent to a token contract are usually lost.',
    'Ця адреса — контракт {1}. Кошти, надіслані на контракт токена, зазвичай втрачені.',
  ),
];

const Map<String, String> _exact = <String, String>{
  // Relative dates (formatters)
  'Just now': 'Щойно',
  'Yesterday': 'Учора',
  'Today': 'Сьогодні',
  // Password strength hints
  'This is one of the most common passwords': 'Це один із найпоширеніших паролів',
  'Digits alone are guessed quickly — add words or letters':
      'Самі цифри вгадують швидко — додайте слова або літери',
  'Longer is stronger — try several unrelated words':
      'Довший — міцніший: спробуйте кілька не пов\'язаних слів',
  'Avoid runs like abcd or 1234': 'Уникайте послідовностей на кшталт abcd чи 1234',
  'Add more words or characters': 'Додайте більше слів або символів',
  'All': 'Усі',
  'Sent': 'Надіслані',
  'Received': 'Отримані',
  '0x… or name.eth': '0x… або name.eth',
  '0x… (64 hex chars)': '0x… (64 hex-символи)',
  'Material Wallet activity': 'Активність Material Wallet',
  // Notifications
  'Transfer confirmed': 'Переказ підтверджено',
  'Funds received': 'Кошти отримано',
  'Incoming funds': 'Вхідні кошти',
  'Tells you when funds arrive, even if the app is closed.':
      'Повідомляє, коли надходять кошти, навіть якщо застосунок закрито.',
  'Transfer confirmations': 'Підтвердження переказів',
  'Tells you when an outgoing transfer confirms.':
      'Повідомляє, коли вихідний переказ підтверджено.',
  // Fee presets, auto-lock
  'Slow': 'Повільно',
  'Normal': 'Звичайно',
  'Fast': 'Швидко',
  'Custom': 'Власна',
  'Immediately': 'Одразу',
  'After 30 seconds': 'Через 30 секунд',
  'After 1 minute': 'Через 1 хвилину',
  'After 5 minutes': 'Через 5 хвилин',
  'Never': 'Ніколи',
  // Opening things
  'Could not open the block explorer.': 'Не вдалося відкрити оглядач блоків.',
  // Sending
  'Your balance dropped since the last refresh. Nothing was sent.':
      'Ваш баланс зменшився після останнього оновлення. Нічого не надіслано.',
  'Your token balance dropped since the last refresh. Nothing was sent.':
      'Ваш баланс токенів зменшився після останнього оновлення. Нічого не надіслано.',
  'Your balance changed since the last refresh. Nothing was sent.':
      'Ваш баланс змінився після останнього оновлення. Нічого не надіслано.',
  'Something went wrong while sending. Nothing was sent.':
      'Щось пішло не так під час надсилання. Нічого не надіслано.',
  'The network no longer knows this transfer.': 'Мережа більше не знає цього переказу.',
  'Could not prepare a faster version. Nothing was changed.':
      'Не вдалося підготувати швидшу версію. Нічого не змінено.',
  'The network no longer knows the original transfer. Nothing was sent.':
      'Мережа більше не знає початкового переказу. Нічого не надіслано.',
  'The original transfer has just confirmed. Nothing was sent.':
      'Початковий переказ щойно підтверджено. Нічого не надіслано.',
  'The original transfer changed since it was reviewed. Nothing was sent.':
      'Початковий переказ змінився після перевірки. Нічого не надіслано.',
  'Could not price this transfer.': 'Не вдалося оцінити цей переказ.',
  'The wallet key does not match this account. Nothing was sent.':
      'Ключ гаманця не збігається з цим акаунтом. Нічого не надіслано.',
  'Enter an amount to send.': 'Введіть суму для надсилання.',
  'This token is not one the wallet can send (its program is not the SPL Token or Token-2022 program).':
      'Цей токен гаманець надіслати не може (його програма — не SPL Token і не Token-2022).',
  'The token\'s decimals changed since the balance was read. Refresh and try again.':
      'Кількість десяткових знаків токена змінилася після читання балансу. Оновіть і спробуйте знову.',
  'That address is a token account, not a wallet. Use the owner\'s wallet address.':
      'Ця адреса — рахунок токена, а не гаманець. Використайте адресу гаманця власника.',
  'Your token balance is lower than this amount.': 'Ваш баланс токенів менший за цю суму.',
  'Your balance is split across several token accounts and none holds this much on its own. Send a smaller amount.':
      'Ваш баланс розділений між кількома рахунками токена, і жоден окремо стільки не тримає. Надішліть меншу суму.',
  'The recipient\'s token account is not usable for this token.':
      'Рахунок токена отримувача не підходить для цього токена.',
  'This would leave less SOL in your account than an account must keep. Top up some SOL first.':
      'Це залишило б на рахунку менше SOL, ніж він має зберігати. Спершу поповніть SOL.',
  'This would leave your SOL balance below the minimum an account must keep.':
      'Це залишило б ваш баланс SOL нижче мінімуму, який має зберігати рахунок.',
  'Your account holds no SOL to pay the network fee.':
      'На вашому рахунку немає SOL для сплати комісії мережі.',
  'Not enough tokens in the account.': 'Недостатньо токенів на рахунку.',
  'The network moved on while preparing. Try again.':
      'Мережа пішла далі, поки ми готувалися. Спробуйте знову.',
  'Not enough SOL for the amount and the network fee.':
      'Недостатньо SOL на суму та комісію мережі.',
  'Sending to your own address does nothing.': 'Надсилання на власну адресу нічого не дає.',
  'This Aptos account has not been funded yet, so it cannot send.':
      'Цей акаунт Aptos ще не поповнено, тому він не може надсилати.',
  'Not enough APT for the amount and the network fee.':
      'Недостатньо APT на суму та комісію мережі.',
  'Not enough APT for the network fee.': 'Недостатньо APT на комісію мережі.',
  'This is a watch-only wallet. It holds no keys and cannot send. Nothing was sent.':
      'Це гаманець лише для перегляду. У ньому немає ключів, і він не може надсилати. Нічого не надіслано.',
  'Unlock the wallet before sending.': 'Розблокуйте гаманець перед надсиланням.',
  // Wallet list / vault
  'No wallet on this device.': 'На цьому пристрої немає гаманця.',
  'That recovery phrase is not a valid BIP-39 phrase.':
      'Ця фраза відновлення — не коректна фраза BIP-39.',
  'A wallet already exists; add the phrase as another wallet instead.':
      'Гаманець уже існує; додайте фразу як інший гаманець.',
  'Unlock the wallet first.': 'Спершу розблокуйте гаманець.',
  'This wallet is already on the device.': 'Цей гаманець уже є на пристрої.',
  'Add at least one address to follow.': 'Додайте принаймні одну адресу, за якою стежити.',
  'Keep at least one address to follow.': 'Залиште принаймні одну адресу, за якою стежити.',
  'This is the only recovery phrase on the device. Erase the wallet from Settings instead.':
      'Це єдина фраза відновлення на пристрої. Замість цього сотріть гаманець у Налаштуваннях.',
  'Watch-only': 'Лише перегляд',
  'Update fingerprint unlock': 'Оновлення розблокування відбитком',
  'Enable fingerprint unlock': 'Увімкнення розблокування відбитком',
  'Unlock Material Wallet': 'Розблокувати Material Wallet',
  'Fingerprint unlock was reset because the fingerprints on this device changed.':
      'Розблокування відбитком скинуто, бо відбитки на цьому пристрої змінилися.',
  'Wrong password — could not unlock the wallet.':
      'Хибний пароль — не вдалося розблокувати гаманець.',
  'Recovery phrase is corrupted.': 'Фразу відновлення пошкоджено.',
  'Cancel': 'Скасувати',
  // Chain API
  'The network request timed out.': 'Час очікування мережевого запиту минув.',
  'Could not reach the blockchain API. Check your connection.':
      'Не вдалося зв\'язатися з API блокчейну. Перевірте з\'єднання.',
  'Unexpected response from the API.': 'Неочікувана відповідь від API.',
  'The node rejected the request.': 'Вузол відхилив запит.',
  'The node accepted the transaction but returned no hash.':
      'Вузол прийняв транзакцію, але не повернув хеш.',
  'The node accepted the transaction but returned no signature.':
      'Вузол прийняв транзакцію, але не повернув підпис.',
  'The node accepted the transaction but returned no txid.':
      'Вузол прийняв транзакцію, але не повернув txid.',
  'The node returned no usable blockhash.': 'Вузол не повернув придатного blockhash.',
  'The node returned no simulation result.': 'Вузол не повернув результату симуляції.',
  'The node returned no ledger information.': 'Вузол не повернув даних реєстру.',
  'The node returned no gas price.': 'Вузол не повернув ціни газу.',
  'The simulation returned no result.': 'Симуляція не повернула результату.',
  'The node returned no fee estimate.': 'Вузол не повернув оцінки комісії.',
  'The node returned no token balance.': 'Вузол не повернув баланс токена.',
  'The node returned a malformed token balance.': 'Вузол повернув пошкоджений баланс токена.',
  'The Aptos indexer returned no balances.': 'Індексатор Aptos не повернув балансів.',
  'This name uses characters the wallet cannot resolve safely.':
      'Ця назва містить символи, які гаманець не може безпечно розпізнати.',
  'Unknown': 'Невідомо',
  'Coinbase': 'Coinbase',
  'Contract creation': 'Створення контракту',
  'Unlimited': 'Без обмежень',
  // Address checks
  'Enter a recipient address': 'Введіть адресу отримувача',
  'This address is for a different Bitcoin network':
      'Ця адреса для іншої мережі Bitcoin',
  'Invalid Bitcoin SegWit address': 'Некоректна адреса Bitcoin SegWit',
  'Invalid Bitcoin address': 'Некоректна адреса Bitcoin',
  'An EVM address starts with 0x': 'Адреса EVM починається з 0x',
  'An EVM address has 40 hex characters': 'Адреса EVM має 40 hex-символів',
  'The address checksum does not match': 'Контрольна сума адреси не збігається',
  'Invalid Solana address': 'Некоректна адреса Solana',
  'An Aptos address starts with 0x': 'Адреса Aptos починається з 0x',
  'Invalid Aptos address': 'Некоректна адреса Aptos',
  'Not a Bitcoin, EVM, Solana or Aptos address':
      'Це не адреса Bitcoin, EVM, Solana чи Aptos',
  'This is the token contract itself. Tokens sent to their own contract are almost always lost.':
      'Це сам контракт токена. Токени, надіслані на власний контракт, майже завжди втрачено.',
  'Could not verify this address. Check it character by character.':
      'Не вдалося перевірити цю адресу. Перевірте її символ за символом.',
  'This address is flagged as a scam.': 'Цю адресу позначено як шахрайську.',
  'This is a contract (a wallet app, an exchange or a Safe), not a person.':
      'Це контракт (застосунок-гаманець, біржа чи Safe), а не людина.',
  // Signer errors
  'Amount out of range.': 'Сума поза допустимим діапазоном.',
  'Invalid Aptos address.': 'Некоректна адреса Aptos.',
  'Unsupported token type.': 'Непідтримуваний тип токена.',
  'Malformed address.': 'Пошкоджена адреса.',
  'Invalid amount.': 'Некоректна сума.',
  'Invalid chain id.': 'Некоректний id мережі.',
  'Malformed key or blockhash.': 'Пошкоджений ключ або blockhash.',
  'Invalid token decimals.': 'Некоректна кількість десяткових знаків токена.',
  'Could not derive a token account.': 'Не вдалося вивести рахунок токена.',
  'The token would go back to the account it comes from.':
      'Токен повернувся б на рахунок, з якого надходить.',
  'The recipient address is for a different Bitcoin network.':
      'Адреса отримувача для іншої мережі Bitcoin.',
  'The recipient is not a valid SegWit address.':
      'Отримувач — не коректна адреса SegWit.',
  'This transfer is already confirmed — there is nothing to speed up.':
      'Цей переказ уже підтверджено — пришвидшувати нічого.',
  'This transfer spends coins that are not all yours, so it cannot be replaced from this wallet.':
      'Цей переказ витрачає монети, які не всі ваші, тож його не можна замінити з цього гаманця.',
  'This transfer was sent without replace-by-fee, so the network will not accept a faster version of it.':
      'Цей переказ надіслано без replace-by-fee, тож мережа не прийме його швидшу версію.',
  'Only native SegWit transfers can be replaced.':
      'Замінити можна лише перекази native SegWit.',
  'This transfer has no change to take the extra fee from.':
      'У цьому переказі немає здачі, з якої взяти додаткову комісію.',
  'The transfer\'s amounts do not add up. Nothing was changed.':
      'Суми в переказі не сходяться. Нічого не змінено.',
  'The change is too small to pay for a faster version. Nothing was changed.':
      'Здача замала, щоб оплатити швидшу версію. Нічого не змінено.',
  'Nothing to spend.': 'Немає чого витрачати.',
  'Signing failed: the recovered key does not match this wallet.':
      'Підписання не вдалося: відновлений ключ не збігається з цим гаманцем.',
  'The recipient address is not a valid EVM address.':
      'Адреса отримувача — не коректна адреса EVM.',
  // Throttle
  'Try again now': 'Спробуйте зараз',
  // Network groups / watch families
  'EVM networks': 'Мережі EVM',
  'Bitcoin testnet': 'Тестова мережа Bitcoin',
};
