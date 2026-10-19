// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Ukrainian (`uk`).
class AppLocalizationsUk extends AppLocalizations {
  AppLocalizationsUk([String locale = 'uk']) : super(locale);

  @override
  String get languageSystem => 'Як у системі';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageUkrainian => 'Українська';

  @override
  String get activity => 'Активність';

  @override
  String get exportCsv => 'Експорт у CSV';

  @override
  String get searchAddressLabelNoteOr =>
      'Пошук за адресою, міткою, нотаткою або хешем';

  @override
  String get clear => 'Очистити';

  @override
  String get noTransactionsYet => 'Транзакцій поки немає';

  @override
  String get nothingMatches => 'Нічого не знайдено';

  @override
  String get onChainActivityForThis =>
      'Тут з\'явиться активність у цій мережі.';

  @override
  String get tryAnotherAddressLabelNote =>
      'Спробуйте іншу адресу, мітку, нотатку або хеш.';

  @override
  String get privateNote => 'Приватна нотатка';

  @override
  String get visibleOnlyOnThisDevice =>
      'Видно лише на цьому пристрої та в експорті CSV';

  @override
  String get cancel => 'Скасувати';

  @override
  String get save => 'Зберегти';

  @override
  String get couldNotExportTheActivity => 'Не вдалося експортувати активність.';

  @override
  String get loading => 'Завантаження…';

  @override
  String get loadMore => 'Показати ще';

  @override
  String get moneyIn => 'Надходження';

  @override
  String get moneyOut => 'Витрати';

  @override
  String get tokenApproval => 'Дозвіл на токен';

  @override
  String get failed => 'Невдала';

  @override
  String get pending => 'Очікує';

  @override
  String get viewOnExplorer => 'Відкрити в оглядачі';

  @override
  String get moreActions => 'Інші дії';

  @override
  String get addNote => 'Додати нотатку';

  @override
  String get editNote => 'Змінити нотатку';

  @override
  String get cancelTransaction => 'Скасувати транзакцію';

  @override
  String get speedUp => 'Пришвидшити';

  @override
  String get welcomeBack => 'З поверненням';

  @override
  String get enterYourPasswordToDecrypt =>
      'Введіть пароль, щоб розшифрувати гаманець.';

  @override
  String get password => 'Пароль';

  @override
  String get decrypting => 'Розшифрування…';

  @override
  String get unlock => 'Розблокувати';

  @override
  String get theFingerprintsOnThisPhone =>
      'Відбитки пальців на цьому телефоні змінилися, тому розблокування відбитком вимкнено. Введіть пароль, а потім увімкніть його знову в Налаштуваннях.';

  @override
  String get unlockWithFingerprint => 'Розблокувати відбитком';

  @override
  String get forgotPasswordEraseRecoveryPhrases =>
      'Забули пароль — стерти фрази відновлення';

  @override
  String get enterYourPassword => 'Введіть пароль';

  @override
  String get couldNotUnlockTheWallet => 'Не вдалося розблокувати гаманець.';

  @override
  String get eraseTheRecoveryPhrases => 'Стерти фрази відновлення?';

  @override
  String get thisDeletesEveryRecoveryPhrase =>
      'Це видалить усі фрази відновлення та пароль з цього пристрою. Без резервних копій кошти не відновити. Гаманці лише для перегляду залишаться. Переконайтеся, що маєте резервні копії, перш ніж продовжити.';

  @override
  String get erase => 'Стерти';

  @override
  String get recoveryPhrasesErasedFromThis =>
      'Фрази відновлення стерто з цього пристрою.';

  @override
  String get security => 'Безпека';

  @override
  String get setAPassword => 'Задайте пароль';

  @override
  String get yourRecoveryPhraseIsEncrypted =>
      'Вашу фразу відновлення шифрує AES-256-GCM за ключем, виведеним із цього пароля, і він знадобиться щоразу, коли ви відкриваєте гаманець. Кодову фразу з кількох слів набагато важче вгадати, ніж короткий код.';

  @override
  String passwordMinCharacters(Object minLength) {
    return 'Пароль (мін. $minLength символів)';
  }

  @override
  String get confirmPassword => 'Підтвердіть пароль';

  @override
  String get unlockWithFingerprint2 => 'Розблокування відбитком';

  @override
  String get openTheWalletWithYour =>
      'Відкривайте гаманець відбитком пальця замість введення пароля';

  @override
  String get thereIsNoPasswordRecovery =>
      'Відновити пароль неможливо. Якщо ви його забудете, для відновлення гаманця знадобиться фраза відновлення.';

  @override
  String get encrypting => 'Шифрування…';

  @override
  String get encryptContinue => 'Зашифрувати й продовжити';

  @override
  String useAtLeastCharacters(Object minLength) {
    return 'Використайте щонайменше $minLength символів';
  }

  @override
  String get passwordsDoNotMatch => 'Паролі не збігаються';

  @override
  String get walletEncryptedAndStoredOn =>
      'Гаманець зашифровано й збережено на цьому пристрої.';

  @override
  String get enterYourCurrentPassword => 'Введіть поточний пароль';

  @override
  String get walletAddedAndEncryptedOn =>
      'Гаманець додано й зашифровано на цьому пристрої.';

  @override
  String get addWallet => 'Додати гаманець';

  @override
  String get confirmWithYourPassword => 'Підтвердіть паролем';

  @override
  String get thisPhraseWillBeEncrypted =>
      'Цю фразу буде зашифровано поруч з іншими гаманцями під тим самим паролем, тож одне розблокування відкриває їх усі.';

  @override
  String get nameOptional => 'Назва (необов\'язково)';

  @override
  String get eGSavings => 'напр. Заощадження';

  @override
  String get currentPassword => 'Поточний пароль';

  @override
  String get wallets => 'Гаманці';

  @override
  String get addAWallet => 'Додати гаманець';

  @override
  String get createANewWallet => 'Створити новий гаманець';

  @override
  String get aFreshRecoveryPhrase => 'Нова фраза відновлення';

  @override
  String get importARecoveryPhrase => 'Імпортувати фразу відновлення';

  @override
  String get another12Or24Word => 'Ще один гаманець із 12 або 24 слів';

  @override
  String get watchAnAddress => 'Стежити за адресою';

  @override
  String get followABalanceWithoutThe => 'Стежте за балансом без ключів';

  @override
  String get recoveryPhrase => 'Фраза відновлення';

  @override
  String watchOnly(Object p0) {
    return 'Лише перегляд · $p0';
  }

  @override
  String get walletOptions => 'Параметри гаманця';

  @override
  String get rename => 'Перейменувати';

  @override
  String get editAddresses => 'Змінити адреси';

  @override
  String get remove => 'Видалити';

  @override
  String get walletName => 'Назва гаманця';

  @override
  String remove2(Object name) {
    return 'Видалити $name?';
  }

  @override
  String get theFollowedAddressesAreForgotten =>
      'Адреси, за якими ви стежили, буде забуто. У блокчейні нічого не зміниться.';

  @override
  String get withoutItsRecoveryPhraseThe =>
      'Без фрази відновлення кошти в цьому гаманці не відновити. Переконайтеся, що маєте резервну копію, перш ніж продовжити.';

  @override
  String get confirmYourPassword => 'Підтвердіть паролем';

  @override
  String get enterAnAddressToFollow => 'Введіть адресу, за якою стежити';

  @override
  String get thisNameHasCharactersThe =>
      'У цій назві є символи, які гаманець не може прочитати точно';

  @override
  String get couldNotLookTheName => 'Не вдалося знайти назву.';

  @override
  String pointsToNoAddress(Object name) {
    return '$name не вказує на жодну адресу';
  }

  @override
  String get scanAnAddress => 'Скануйте адресу';

  @override
  String addressOtherAddresses(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Відстежується $count адреси.',
      many: 'Відстежується $count адрес.',
      few: 'Відстежуються $count адреси.',
      one: 'Відстежується $count адреса.',
    );
    return '$_temp0';
  }

  @override
  String get walletUpdated => 'Гаманець оновлено.';

  @override
  String get watchOnlyWallet => 'Гаманець лише для перегляду';

  @override
  String get editWatchOnlyWallet => 'Змінити гаманець лише для перегляду';

  @override
  String get followAnAddress => 'Стежте за адресою';

  @override
  String get seeTheBalanceTokensAnd =>
      'Дивіться баланс, токени та історію адреси, ключів до якої у вас немає: холодного гаманця, накопичувального рахунку чи публічної адреси друга. Нічого секретного не зберігається, і з цього гаманця ніколи не можна надсилати.';

  @override
  String get eGColdStorage => 'напр. Холодне сховище';

  @override
  String get address => 'Адреса';

  @override
  String get bc10xNameEthSolana =>
      'bc1…, 0x…, name.eth, адреса Solana або Aptos';

  @override
  String get paste => 'Вставити';

  @override
  String get scan => 'Сканувати';

  @override
  String get addAddress => 'Додати адресу';

  @override
  String get remove3 => 'Прибрати';

  @override
  String get oneAddressPerKindAn =>
      'Одна адреса на тип: адреса EVM однакова в Ethereum, Base, Polygon, Arbitrum, BNB Chain і Sepolia.';

  @override
  String get follow => 'Стежити';

  @override
  String get network => 'Мережа';

  @override
  String get mainnets => 'Основні мережі';

  @override
  String get testnets => 'Тестові мережі';

  @override
  String testnet(Object group) {
    return '$group · Тестова мережа';
  }

  @override
  String get wallet => 'Гаманець';

  @override
  String get settings => 'Налаштування';

  @override
  String get portfolio => 'Портфель';

  @override
  String get refresh => 'Оновити';

  @override
  String get totalAcrossNetworks => 'Усього за мережами';

  @override
  String get someNetworksCouldNotBe =>
      'Деякі мережі не вдалося прочитати, тож цей підсумок може бути занижений.';

  @override
  String get unavailable => 'Недоступно';

  @override
  String tokenOtherTokens(String native, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count токена',
      many: '$count токенів',
      few: '$count токени',
      one: '$count токен',
    );
    return '$native · $_temp0';
  }

  @override
  String get receive => 'Отримати';

  @override
  String get noWalletFound => 'Гаманець не знайдено';

  @override
  String get unlockYourWalletToGenerate =>
      'Розблокуйте гаманець, щоб створити адресу для отримання.';

  @override
  String scanToPay(Object p0, Object symbol) {
    return 'Скануйте, щоб сплатити $p0 $symbol';
  }

  @override
  String scanToReceive(Object symbol) {
    return 'Скануйте, щоб отримати $symbol';
  }

  @override
  String onlySendOnToThis(Object symbol, Object name) {
    return 'Надсилайте на цю адресу лише $symbol у мережі $name.';
  }

  @override
  String get requestAnAmountOptional => 'Запитати суму (необов\'язково)';

  @override
  String get enterAValidAmount => 'Введіть коректну суму';

  @override
  String get sharePaymentRequest => 'Поділитися запитом на оплату';

  @override
  String get yourAddress => 'Ваша адреса';

  @override
  String get copyAddress => 'Копіювати адресу';

  @override
  String pleaseSendOnTo(
    Object p0,
    Object symbol,
    Object name,
    Object address,
    Object link,
  ) {
    return 'Надішліть, будь ласка, $p0 $symbol у мережі $name на адресу $address\n$link';
  }

  @override
  String get paymentRequest => 'Запит на оплату';

  @override
  String get couldNotShareTheRequest => 'Не вдалося поділитися запитом.';

  @override
  String get addressCopiedToClipboard => 'Адресу скопійовано';

  @override
  String get addressBook => 'Адресна книга';

  @override
  String get add => 'Додати';

  @override
  String get noSavedRecipients => 'Немає збережених отримувачів';

  @override
  String get saveTheAddressesYouSend =>
      'Збережіть адреси, на які часто надсилаєте, і вони з\'являться тут і в надсиланні.';

  @override
  String saved(Object label) {
    return 'Збережено «$label».';
  }

  @override
  String get newRecipient => 'Новий отримувач';

  @override
  String get label => 'Мітка';

  @override
  String get saveRecipient => 'Зберегти отримувача';

  @override
  String get yourAddresses => 'Ваші адреси';

  @override
  String get beforeReceivingLargeAmountsCheck =>
      'Перш ніж отримувати великі суми, звірте ці адреси зі своєю фразою відновлення на іншому довіреному пристрої.';

  @override
  String get locked => 'Заблоковано';

  @override
  String onlySendOnHere(Object symbol, Object name) {
    return 'Надсилайте сюди лише $symbol у мережі $name.';
  }

  @override
  String get displayCurrency => 'Валюта відображення';

  @override
  String get appearance => 'Вигляд';

  @override
  String get currency => 'Валюта';

  @override
  String get about => 'Про застосунок';

  @override
  String get selfCustodialWallet => 'Гаманець із власним зберіганням';

  @override
  String get watchOnlyMode => 'Режим перегляду';

  @override
  String get noKeysOnThisDevice => 'На цьому пристрої немає ключів';

  @override
  String get encryptedOnThisDevice => 'Зашифровано на цьому пристрої';

  @override
  String created(Object p0) {
    return 'Створено $p0';
  }

  @override
  String get seedEncryptedWithAes256 => 'Seed зашифровано AES-256-GCM';

  @override
  String get nothingSecretIsStored => 'Нічого секретного не зберігається';

  @override
  String get activeNetwork => 'Активна мережа';

  @override
  String testnet2(Object name) {
    return '$name · Тестова мережа';
  }

  @override
  String get fingerprintUnlockEnabled => 'Розблокування відбитком увімкнено.';

  @override
  String get fingerprintUnlockWasNotEnabled =>
      'Розблокування відбитком не ввімкнено.';

  @override
  String get enable => 'Увімкнути';

  @override
  String get tokenApprovals => 'Дозволи токенів';

  @override
  String get reviewAndRevokeWhatContracts =>
      'Перегляд і відкликання дозволів, які контракти мають на витрату ваших токенів';

  @override
  String get notAvailableOnThisDevice => 'Недоступно на цьому пристрої';

  @override
  String get opensTheWalletWithoutTyping =>
      'Відкриває гаманець без введення пароля';

  @override
  String get confirmsYourPasswordOnceTo =>
      'Один раз підтверджує пароль для налаштування';

  @override
  String get autoLock => 'Автоблокування';

  @override
  String get transferNotifications => 'Сповіщення про перекази';

  @override
  String get tellsYouWhenAnOutgoing =>
      'Повідомляє, коли вихідний переказ підтверджено';

  @override
  String get notifyWhenClosed => 'Сповіщати при закритому застосунку';

  @override
  String get checksForIncomingFundsAnd =>
      'Перевіряє вхідні кошти та підтверджені перекази приблизно кожні 15 хвилин, навіть коли застосунок закрито. Пароль не потрібен.';

  @override
  String get notificationsWereNotAllowedYou =>
      'Сповіщення не дозволено. Увімкнути їх можна в системних налаштуваннях.';

  @override
  String get never => 'Ніколи';

  @override
  String get immediately => 'Одразу';

  @override
  String secondOtherSeconds(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Через $count секунди',
      many: 'Через $count секунд',
      few: 'Через $count секунди',
      one: 'Через $count секунду',
    );
    return '$_temp0';
  }

  @override
  String minuteOtherMinutes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Через $count хвилини',
      many: 'Через $count хвилин',
      few: 'Через $count хвилини',
      one: 'Через $count хвилину',
    );
    return '$_temp0';
  }

  @override
  String get autoLockAfter => 'Автоблокування через';

  @override
  String walletOnThisDeviceOther(String name, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count гаманця на цьому пристрої',
      many: '$count гаманців на цьому пристрої',
      few: '$count гаманці на цьому пристрої',
      one: '$count гаманець на цьому пристрої',
    );
    return '$name · $_temp0';
  }

  @override
  String get activeAccount => 'Активний акаунт';

  @override
  String ofLabel(String name, int index, int count) {
    return '$name · $index з $count';
  }

  @override
  String get followedAddress => 'Адреса, за якою стежите';

  @override
  String get receiveAddress => 'Адреса для отримання';

  @override
  String get noAddress => 'Немає адреси';

  @override
  String get walletLocked => 'Гаманець заблоковано';

  @override
  String get thisWalletFollowsNoAddress =>
      'Цей гаманець не стежить за жодною адресою в активній мережі';

  @override
  String get watchOnlyCannotSend => 'Лише перегляд — надсилати не можна';

  @override
  String get derivedForTheActiveNetwork => 'Створено для активної мережі';

  @override
  String get allChainsWithQrCodes => 'Усі мережі з QR-кодами';

  @override
  String wordBip39Phrase(Object length) {
    return 'Фраза BIP-39 з $length слів';
  }

  @override
  String get changePassword => 'Змінити пароль';

  @override
  String get savedRecipientsAndLabels => 'Збережені отримувачі та мітки';

  @override
  String get lockWallet => 'Заблокувати гаманець';

  @override
  String get clearTheDecryptedSeedFrom =>
      'Прибрати розшифрований seed із пам\'яті';

  @override
  String get eraseRecoveryPhrases => 'Стерти фрази відновлення';

  @override
  String get deletesEveryEncryptedSeedAnd =>
      'Видаляє всі зашифровані seed і пароль; гаманці лише для перегляду залишаються';

  @override
  String get defaultLabel => 'За замовчуванням';

  @override
  String get addAccount => 'Додати акаунт';

  @override
  String get aFreshSetOfAddresses => 'Нові адреси з того самого seed';

  @override
  String get accountName => 'Назва акаунта';

  @override
  String get eGSavingsEmptyDefault =>
      'напр. Заощадження (порожньо = за замовчуванням)';

  @override
  String get revealRecoveryPhrase => 'Показати фразу відновлення?';

  @override
  String get makeSureNobodyCanSee =>
      'Переконайтеся, що ніхто не бачить ваш екран. Той, хто прочитає ці слова, може забрати ваші кошти.';

  @override
  String get reveal => 'Показати';

  @override
  String get revealRecoveryPhrase2 => 'Показати фразу відновлення';

  @override
  String wordKeepItOfflineOther(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count слова · зберігайте їх офлайн.',
      many: '$count слів · зберігайте їх офлайн.',
      few: '$count слова · зберігайте їх офлайн.',
      one: '$count слово · зберігайте його офлайн.',
    );
    return '$_temp0';
  }

  @override
  String get thisWalletAlsoUsesA =>
      'Цей гаманець також використовує кодову фразу BIP-39 (25-те слово). Для відновлення потрібні обидві: самі слова відкриють інший, порожній гаманець. Кодову фразу тут не показано.';

  @override
  String get eraseEveryRecoveryPhrase => 'Стерти всі фрази відновлення?';

  @override
  String get thisDeletesAllRecoveryPhrases =>
      'Це видалить усі фрази відновлення та пароль з цього пристрою. Без резервних копій кошти не відновити. Гаманці лише для перегляду залишаться. Переконайтеся, що маєте резервні копії, перш ніж продовжити.';

  @override
  String get theRecoveryPhraseIsRe =>
      'Фразу відновлення буде перешифровано новим паролем.';

  @override
  String newPasswordMinCharacters(Object minLength) {
    return 'Новий пароль (мін. $minLength символів)';
  }

  @override
  String get confirmNewPassword => 'Підтвердіть новий пароль';

  @override
  String get reEncrypting => 'Перешифрування…';

  @override
  String get saveNewPassword => 'Зберегти новий пароль';

  @override
  String get newPasswordsDoNotMatch => 'Нові паролі не збігаються';

  @override
  String get couldNotChangeThePassword => 'Не вдалося змінити пароль.';

  @override
  String get passwordUpdatedFingerprintUnlockWas =>
      'Пароль оновлено. Розблокування відбитком вимкнено — увімкніть його знову в Налаштуваннях.';

  @override
  String get passwordUpdatedSuccessfully => 'Пароль успішно оновлено.';

  @override
  String get system => 'Система';

  @override
  String get light => 'Світла';

  @override
  String get dark => 'Темна';

  @override
  String get pricesAreConvertedFromUsd => 'Ціни перераховуються з USD';

  @override
  String get version => 'Версія';

  @override
  String get selfCustodialBip39Bip =>
      'Власне зберігання · BIP-39 / BIP-84 / BIP-44';

  @override
  String materialWalletBuiltWithFlutter(Object appVersion) {
    return 'Material Wallet $appVersion — створено на Flutter і Material 3.';
  }

  @override
  String get dataSources => 'Джерела даних';

  @override
  String get mempoolSpaceBlockscoutCoingeckoPublicnode =>
      'mempool.space · Blockscout · CoinGecko · PublicNode · dRPC · 1RPC · офіційні RPC мереж (Base, Arbitrum, Polygon, BNB) · Solana RPC · вузол Aptos · індексатор Aptos Labs (баланси токенів Aptos)';

  @override
  String get materialWalletDemoBuild => 'Material Wallet · демо-збірка';

  @override
  String get couldNotLoadYourApprovals =>
      'Не вдалося завантажити ваші дозволи.';

  @override
  String get approvalsUnavailable => 'Дозволи недоступні';

  @override
  String pullDownToTryAgain(Object error) {
    return '$error Потягніть вниз, щоб повторити.';
  }

  @override
  String get noActiveApprovals => 'Немає активних дозволів';

  @override
  String get noContractOnThisNetwork =>
      'Жоден контракт у цій мережі не може витрачати ваші токени. Шахрайський сайт, що попросив дозвіл, з\'явився б тут.';

  @override
  String get aWatchOnlyWalletCannot =>
      'Гаманець лише для перегляду не може відкликати дозволи.';

  @override
  String revokeApproval(Object symbol) {
    return 'Відкликати дозвіл для $symbol?';
  }

  @override
  String thisSetsTheAllowanceFor(Object p0, Object symbol) {
    return 'Це обнулить ліміт для $p0, тож контракт більше не зможе переміщувати ваші $symbol. Контракти, яким потрібен дозвіл, перестануть працювати, доки ви не надасте його знову.';
  }

  @override
  String get keepIt => 'Залишити';

  @override
  String get revoke => 'Відкликати';

  @override
  String get revokeApproval2 => 'Відкликати дозвіл';

  @override
  String get confirmRevoke => 'Підтвердіть відкликання';

  @override
  String couldNotReachToPrice(Object name) {
    return 'Не вдалося зв\'язатися з $name, щоб оцінити відкликання.';
  }

  @override
  String get theRevokeCouldNotBe =>
      'Відкликання не вдалося надіслати. Нічого не змінилося.';

  @override
  String get revokeSubmitted => 'Відкликання надіслано.';

  @override
  String approvedFor(Object p0) {
    return 'Дозволено для $p0';
  }

  @override
  String get unlimitedThisContractCanMove =>
      'Без обмежень — цей контракт у будь-який час може перемістити все.';

  @override
  String get undo => 'Скасувати';

  @override
  String get nothingFollowedHere => 'Тут ні за чим не стежите';

  @override
  String thisWatchOnlyWalletHas(Object name) {
    return 'Цей гаманець лише для перегляду не має адреси в мережі $name. Виберіть іншу мережу або додайте адресу такого типу в Налаштування → Гаманці.';
  }

  @override
  String get tokens => 'Токени';

  @override
  String get approvals => 'Дозволи';

  @override
  String hideTheHidden(Object hiddenCount) {
    return 'Сховати приховані: $hiddenCount';
  }

  @override
  String showHidden(Object hiddenCount) {
    return 'Показати приховані: $hiddenCount';
  }

  @override
  String get recentActivity => 'Остання активність';

  @override
  String get seeAll => 'Показати все';

  @override
  String get everyNetworkInOneList => 'Усі мережі в одному списку';

  @override
  String get noTransactionsOnThisNetwork =>
      'У цій мережі ще немає транзакцій. Отримайте кошти, і вони з\'являться тут.';

  @override
  String youCanFollowThisAddress(String name) {
    return '$name — за цією адресою можна стежити, але не надсилати з неї.';
  }

  @override
  String get showBalance => 'Показати баланс';

  @override
  String get hideBalance => 'Сховати баланс';

  @override
  String get testnetNoMarketPrice => 'Тестова мережа — без ринкової ціни';

  @override
  String get priceTemporarilyUnavailable => 'Ціна тимчасово недоступна';

  @override
  String get retry => 'Повторити';

  @override
  String yourAddress2(Object networkLabel) {
    return 'Ваша адреса · $networkLabel';
  }

  @override
  String get copy => 'Копіювати';

  @override
  String get explorer => 'Оглядач';

  @override
  String get loadingOnChainData => 'Завантаження даних із блокчейну…';

  @override
  String get couldNotLoadData => 'Не вдалося завантажити дані';

  @override
  String get tryAgain => 'Спробувати знову';

  @override
  String get scanQrCode => 'Скануйте QR-код';

  @override
  String get toggleFlashlight => 'Увімкнути ліхтарик';

  @override
  String get switchCamera => 'Перемкнути камеру';

  @override
  String get pointTheCameraAtA => 'Наведіть камеру на QR-код гаманця';

  @override
  String get yourRecoveryPhrase => 'Ваша фраза відновлення';

  @override
  String writeTheseWordsDown(Object length) {
    return 'Запишіть ці слова ($length)';
  }

  @override
  String get theyAreTheOnlyWay =>
      'Це єдиний спосіб відновити ваш гаманець. Зберігайте їх офлайн — той, хто їх прочитає, може забрати ваші кошти.';

  @override
  String get copyPhrase => 'Копіювати фразу';

  @override
  String get neverShareThisPhraseMaterial =>
      'Нікому не показуйте цю фразу. Material Wallet ніколи не попросить її в вас.';

  @override
  String get iHaveWrittenDownMy => 'Я записав(ла) свою фразу відновлення';

  @override
  String get continueLabel => 'Продовжити';

  @override
  String get recoveryPhraseCopiedClearedAutomatically =>
      'Фразу відновлення скопійовано — буде очищено автоматично';

  @override
  String get importWallet => 'Імпорт гаманця';

  @override
  String get enterYourRecoveryPhrase => 'Введіть свою фразу відновлення';

  @override
  String get typeOrPasteThe12 =>
      'Введіть або вставте 12 чи 24 слова через пробіл. Контрольну суму перевіряють локально, перш ніж щось зберегти.';

  @override
  String get wordOneWordTwoWord => 'слово одне слово два слово три …';

  @override
  String get passphrase25thWordOptional =>
      'Кодова фраза (25-те слово) — необов\'язково';

  @override
  String get leaveEmptyIfYouNever =>
      'залиште порожнім, якщо ніколи її не задавали';

  @override
  String get waitingForYourPhrase => 'Чекаємо на вашу фразу';

  @override
  String validWordPhrase(Object wordCount) {
    return 'Коректна фраза з $wordCount слів';
  }

  @override
  String wordSChecksumNotValid(Object wordCount) {
    return 'Слів: $wordCount — контрольна сума ще не коректна';
  }

  @override
  String get ifYourPhraseWasCreated =>
      'Якщо вашу фразу створено з кодовою фразою (25-м словом), введіть її нижче — відсутня або з помилкою виведе інші адреси, і кожен баланс показуватиме нуль.';

  @override
  String get aSelfCustodialWalletYour =>
      'Гаманець із власним зберіганням. Ваші ключі ніколи не залишають цей пристрій — фраза відновлення створюється тут і зберігається локально.';

  @override
  String get iAlreadyHaveAWallet => 'У мене вже є гаманець';

  @override
  String get justWatchAnAddress => 'Лише стежити за адресою';

  @override
  String get verifyBackup => 'Перевірка резервної копії';

  @override
  String get confirmYourRecoveryPhrase => 'Підтвердіть свою фразу відновлення';

  @override
  String get typeTheWordsBelowExactly =>
      'Введіть слова нижче точно так, як у вашій резервній копії. Позиції щоразу вибираються випадково, тож передбачити, які запитають, неможливо.';

  @override
  String word(Object p0) {
    return 'Слово №$p0';
  }

  @override
  String get typeTheWord => 'Введіть слово';

  @override
  String get aWatchOnlyWalletCannot2 =>
      'Гаманець лише для перегляду не може надсилати чи замінювати перекази.';

  @override
  String get cancelThisTransfer => 'Скасувати цей переказ?';

  @override
  String get speedThisTransferUp => 'Пришвидшити цей переказ?';

  @override
  String thisSends0ToYourself(Object symbol) {
    return 'Це надсилає 0 $symbol вам самим і повторно використовує nonce транзакції, що очікує, тож вона ніколи не підтвердиться. Працює, лише поки транзакція ще очікує.';
  }

  @override
  String thisReSendsTheIdentical(Object counterparty) {
    return 'Це повторно надсилає той самий переказ токена на $counterparty з вищою комісією, повторно використовуючи nonce та calldata транзакції, що очікує. Підтвердиться рівно одна з двох.';
  }

  @override
  String thisSendsToAgainWith(Object p0, Object counterparty) {
    return 'Це знову надсилає $p0 на $counterparty з вищою комісією, повторно використовуючи nonce транзакції, що очікує. Підтвердиться рівно одна з двох.';
  }

  @override
  String get cancelTransfer => 'Скасувати переказ';

  @override
  String get confirmCancel => 'Підтвердити скасування';

  @override
  String get confirmSpeedUp => 'Підтвердити пришвидшення';

  @override
  String couldNotReachToPrice2(Object name) {
    return 'Не вдалося зв\'язатися з $name, щоб оцінити заміну.';
  }

  @override
  String get replacementSubmittedTheOriginalCan =>
      'Заміну надіслано — оригінал більше не може підтвердитися.';

  @override
  String get fasterReplacementSubmitted => 'Швидшу заміну надіслано.';

  @override
  String get theReplacementCouldNotBe =>
      'Заміну не вдалося надіслати. Нічого не змінилося.';

  @override
  String get thisTransferCannotBeSped => 'Цей переказ неможливо пришвидшити.';

  @override
  String theSamePaymentIsSent(Object p0, Object p1, Object feeRate) {
    return 'Той самий платіж надсилається знову з вищою комісією, що сплачується зі здачі: $p0 → $p1 ($feeRate sat/vB). Одержувач усе одно отримає ту саму суму; підтвердиться рівно один із двох переказів.';
  }

  @override
  String get send => 'Надіслати';

  @override
  String get thisWalletFollowsAnAddress =>
      'Цей гаманець стежить за адресою, але не має ключів, тому не може надсилати. Перейдіть на гаманець із фразою відновлення в Налаштування → Гаманці.';

  @override
  String get accountDataUnavailable => 'Дані акаунта недоступні';

  @override
  String get theBalanceIsStillLoading =>
      'Баланс ще завантажується. Поверніться і спробуйте знову.';

  @override
  String send2(Object symbol) {
    return 'Надіслати $symbol';
  }

  @override
  String get available => 'Доступно';

  @override
  String amountIn(Object code) {
    return 'Сума в $code';
  }

  @override
  String get amount => 'Сума';

  @override
  String notEnoughOrTooLittle(Object symbol, Object p1) {
    return 'Недостатньо $symbol або замало $p1 на комісію';
  }

  @override
  String get notEnoughFundsForAmount => 'Недостатньо коштів на суму та комісію';

  @override
  String enterIn(Object symbol) {
    return 'Введіть у $symbol';
  }

  @override
  String enterIn2(Object code) {
    return 'Введіть у $code';
  }

  @override
  String get max => 'МАКС';

  @override
  String get recipientAddress => 'Адреса отримувача';

  @override
  String get base58Address => 'Адреса Base58';

  @override
  String get resolvingTheName => 'Розпізнаємо назву…';

  @override
  String get scanQrCode2 => 'Сканувати QR-код';

  @override
  String gweiTipGweiCap(Object p0, Object p1) {
    return '$p0 gwei пріоритет · $p1 gwei ліміт';
  }

  @override
  String get networkFee => 'Комісія мережі';

  @override
  String get maxNetworkFee => 'Макс. комісія мережі';

  @override
  String get reviewTransfer => 'Перевірити переказ';

  @override
  String thisIsWhatGetsSigned(Object p0) {
    return '≈ $p0 (саме це буде підписано)';
  }

  @override
  String get thisNameUsesCharactersThe =>
      'Ця назва містить символи, які гаманець не може безпечно розпізнати.';

  @override
  String doesNotPointToAn(Object name) {
    return '$name не вказує на адресу.';
  }

  @override
  String get theResolverReturnedAnInvalid =>
      'Резолвер повернув некоректну адресу.';

  @override
  String couldNotLookUp(Object name, Object message) {
    return 'Не вдалося знайти $name: $message';
  }

  @override
  String get clipboardIsEmpty => 'Буфер обміну порожній.';

  @override
  String get thisPaymentLinkIsNot =>
      'Це платіжне посилання не підтримується — нічого не заповнено.';

  @override
  String get differentNetwork => 'Інша мережа';

  @override
  String thisLinkTargetsButThe(Object name, Object p1) {
    return 'Це посилання стосується $name, а екран надсилання налаштовано на $p1. Перемкнути?';
  }

  @override
  String get switchLabel => 'Перемкнути';

  @override
  String thisLinkPaysWithA(Object name) {
    return 'Це посилання платить токеном, якого немає на вашому балансі $name. Відкрийте мережу, дайте їй синхронізуватися й відскануйте код знову.';
  }

  @override
  String couldNotReachToPrice3(Object name) {
    return 'Не вдалося зв\'язатися з $name, щоб оцінити цей переказ. Нічого не надіслано.';
  }

  @override
  String includesTheOneTimeDeposit(Object symbol) {
    return 'Включає одноразовий депозит, що відкриває отримувачу рахунок $symbol. У отримувача ще немає рахунку для цього токена.';
  }

  @override
  String get confirmTransfer => 'Підтвердьте переказ';

  @override
  String get theTransferFailedNothingWas =>
      'Переказ не вдався. Нічого не надіслано.';

  @override
  String hasNoTransactionHistoryIn(Object name) {
    return 'У цьому гаманці немає історії транзакцій у $name. Надсилати можна, але завислий переказ тут не можна пришвидшити чи скасувати, ви не отримаєте сповіщення про підтвердження, а отримувача не буде звірено з вашими минулими платежами чи списками шахраїв. Уважно перевірте адресу.';
  }

  @override
  String get saveARecipientFromThe =>
      'Збережіть отримувача з підсумку переказу, і він з\'явиться тут.';

  @override
  String get eGExchange => 'напр. Біржа';

  @override
  String get estimating => 'Оцінюємо…';

  @override
  String get total => 'Разом';

  @override
  String get transferPrepared => 'Переказ підготовлено';

  @override
  String validatedAgainstTheLiveBalance(Object name) {
    return 'Перевірено за актуальним балансом у $name.';
  }

  @override
  String get ensName => 'Ім\'я ENS';

  @override
  String get to => 'Кому';

  @override
  String get sendingIsBlockedUntilYou =>
      'Надсилання заблоковано, доки ви не виправите отримувача вище.';

  @override
  String sendingIsNotSupportedOn(Object name) {
    return 'Надсилання в $name поки не підтримується. Відновіть фразу відновлення в гаманці з підписом, щоб переміщувати кошти.';
  }

  @override
  String theTransferIsSignedOn(Object name) {
    return 'Переказ підписується на цьому пристрої та надсилається просто в $name. Скасувати його неможливо.';
  }

  @override
  String send3(Object amountSymbol) {
    return 'Надіслати $amountSymbol';
  }

  @override
  String get copyDetails => 'Копіювати деталі';

  @override
  String get viewRecipientOnExplorer => 'Відкрити отримувача в оглядачі';

  @override
  String to2(Object recipient) {
    return 'Кому: $recipient';
  }

  @override
  String amount2(Object p0) {
    return 'Сума: $p0';
  }

  @override
  String fee(Object p0) {
    return 'Комісія: $p0';
  }

  @override
  String get transferDetailsCopied => 'Деталі переказу скопійовано';

  @override
  String get thisAddressLooksLikeAnother =>
      'Ця адреса схожа на іншу, яку ви використовуєте';

  @override
  String itStartsAndEndsLike(Object p0) {
    return 'Вона починається й закінчується як $p0, на яку ви вже надсилали. Шахраї копіюють видимі краї справжньої адреси й чекають, що ви надішлете кошти на неї. Перевірте середину адреси, перш ніж продовжити.';
  }

  @override
  String get enterAPriorityFeeAbove => 'Введіть пріоритетну комісію більше 0.';

  @override
  String get theFeeCapMustBe =>
      'Ліміт комісії має бути не меншим за пріоритетну комісію.';

  @override
  String get customNetworkFee => 'Власна комісія мережі';

  @override
  String currentBaseFeeGwei(Object p0) {
    return 'Поточна базова комісія: $p0 gwei.';
  }

  @override
  String get priorityFeeTip => 'Пріоритетна комісія (чайові)';

  @override
  String get maxFeeCap => 'Макс. комісія (ліміт)';

  @override
  String get apply => 'Застосувати';

  @override
  String get enterAFeeRateOf => 'Введіть ставку комісії щонайменше 1 sat/vB.';

  @override
  String get thatFeeRateIsUnreasonably => 'Ця ставка комісії надмірно висока.';

  @override
  String get customFeeRate => 'Власна ставка комісії';

  @override
  String get theTransferPaysThisMany =>
      'Переказ платить стільки сатоші за віртуальний байт. Вища ставка підтверджується швидше.';

  @override
  String get feeRate => 'Ставка комісії';

  @override
  String get transfer => 'Переказ';

  @override
  String get transferConfirmed => 'Переказ підтверджено';

  @override
  String get transferSent => 'Переказ надіслано';

  @override
  String get theFundsLeftYourWallet =>
      'Кошти залишили ваш гаманець, а транзакцію додано в блок.';

  @override
  String get theTransactionWasAcceptedAnd =>
      'Транзакцію прийнято, і невдовзі вона підтвердиться. Стежити за нею можна в оглядачі.';

  @override
  String get done => 'Готово';

  @override
  String get transaction => 'Транзакція';

  @override
  String get copyTransactionHash => 'Копіювати хеш транзакції';

  @override
  String get transactionHashCopied => 'Хеш транзакції скопійовано';

  @override
  String get transferSubmitted => 'Переказ надіслано';

  @override
  String get sending => 'Надсилання…';

  @override
  String get signingOnThisDevice => 'Підписуємо на цьому пристрої…';

  @override
  String waitingForToConfirm(Object shortTo) {
    return 'Чекаємо підтвердження від $shortTo…';
  }

  @override
  String get confirmedOnChain => 'Підтверджено в блокчейні.';

  @override
  String get broadcasting => 'Транслюємо…';

  @override
  String get close => 'Закрити';

  @override
  String get weak => 'Слабкий';

  @override
  String get fair => 'Середній';

  @override
  String get good => 'Добрий';

  @override
  String get strong => 'Надійний';

  @override
  String get showLabel => 'Показати';

  @override
  String get hideLabel => 'Сховати';

  @override
  String get couldNotOpenYourWallet => 'Не вдалося відкрити гаманець';

  @override
  String get theSecureStorageOnThis =>
      'Захищене сховище на цьому пристрої не відповіло. Ваш гаманець не втрачено — спробуйте ще раз.';

  @override
  String get language => 'Мова';

  @override
  String get chooseLanguage => 'Оберіть мову';
}
