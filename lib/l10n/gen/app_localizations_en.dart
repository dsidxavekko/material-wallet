// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get languageSystem => 'System default';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageUkrainian => 'Українська';

  @override
  String get activity => 'Activity';

  @override
  String get exportCsv => 'Export CSV';

  @override
  String get searchAddressLabelNoteOr => 'Search address, label, note or hash';

  @override
  String get clear => 'Clear';

  @override
  String get noTransactionsYet => 'No transactions yet';

  @override
  String get nothingMatches => 'Nothing matches';

  @override
  String get onChainActivityForThis =>
      'On-chain activity for this network shows up here.';

  @override
  String get tryAnotherAddressLabelNote =>
      'Try another address, label, note or hash.';

  @override
  String get privateNote => 'Private note';

  @override
  String get visibleOnlyOnThisDevice =>
      'Visible only on this device and in your CSV export';

  @override
  String get cancel => 'Cancel';

  @override
  String get save => 'Save';

  @override
  String get couldNotExportTheActivity => 'Could not export the activity.';

  @override
  String get loading => 'Loading…';

  @override
  String get loadMore => 'Load more';

  @override
  String get moneyIn => 'Money in';

  @override
  String get moneyOut => 'Money out';

  @override
  String get tokenApproval => 'Token approval';

  @override
  String get failed => 'Failed';

  @override
  String get pending => 'Pending';

  @override
  String get viewOnExplorer => 'View on explorer';

  @override
  String get moreActions => 'More actions';

  @override
  String get addNote => 'Add note';

  @override
  String get editNote => 'Edit note';

  @override
  String get cancelTransaction => 'Cancel transaction';

  @override
  String get speedUp => 'Speed up';

  @override
  String get welcomeBack => 'Welcome back';

  @override
  String get enterYourPasswordToDecrypt =>
      'Enter your password to decrypt the wallet.';

  @override
  String get password => 'Password';

  @override
  String get decrypting => 'Decrypting…';

  @override
  String get unlock => 'Unlock';

  @override
  String get theFingerprintsOnThisPhone =>
      'The fingerprints on this phone changed, so fingerprint unlock was turned off. Enter your password, then enable it again in Settings.';

  @override
  String get unlockWithFingerprint => 'Unlock with fingerprint';

  @override
  String get forgotPasswordEraseRecoveryPhrases =>
      'Forgot password — erase recovery phrases';

  @override
  String get enterYourPassword => 'Enter your password';

  @override
  String get couldNotUnlockTheWallet => 'Could not unlock the wallet.';

  @override
  String get eraseTheRecoveryPhrases => 'Erase the recovery phrases?';

  @override
  String get thisDeletesEveryRecoveryPhrase =>
      'This deletes every recovery phrase and the password from this device. Without the backups the funds are unrecoverable. Watch-only wallets are kept. Make sure you have your backups before continuing.';

  @override
  String get erase => 'Erase';

  @override
  String get recoveryPhrasesErasedFromThis =>
      'Recovery phrases erased from this device.';

  @override
  String get security => 'Security';

  @override
  String get setAPassword => 'Set a password';

  @override
  String get yourRecoveryPhraseIsEncrypted =>
      'Your recovery phrase is encrypted with AES-256-GCM using a key derived from this password, and you will need it every time you open the wallet. A passphrase of several words is much harder to guess than a short code.';

  @override
  String passwordMinCharacters(Object minLength) {
    return 'Password (min. $minLength characters)';
  }

  @override
  String get confirmPassword => 'Confirm password';

  @override
  String get unlockWithFingerprint2 => 'Unlock with fingerprint';

  @override
  String get openTheWalletWithYour =>
      'Open the wallet with your fingerprint instead of typing the password';

  @override
  String get thereIsNoPasswordRecovery =>
      'There is no password recovery. If you forget it you will need your recovery phrase to restore the wallet.';

  @override
  String get encrypting => 'Encrypting…';

  @override
  String get encryptContinue => 'Encrypt & continue';

  @override
  String useAtLeastCharacters(Object minLength) {
    return 'Use at least $minLength characters';
  }

  @override
  String get passwordsDoNotMatch => 'Passwords do not match';

  @override
  String get walletEncryptedAndStoredOn =>
      'Wallet encrypted and stored on this device.';

  @override
  String get enterYourCurrentPassword => 'Enter your current password';

  @override
  String get walletAddedAndEncryptedOn =>
      'Wallet added and encrypted on this device.';

  @override
  String get addWallet => 'Add wallet';

  @override
  String get confirmWithYourPassword => 'Confirm with your password';

  @override
  String get thisPhraseWillBeEncrypted =>
      'This phrase will be encrypted next to your other wallets under the same password, so one unlock opens them all.';

  @override
  String get nameOptional => 'Name (optional)';

  @override
  String get eGSavings => 'e.g. Savings';

  @override
  String get currentPassword => 'Current password';

  @override
  String get wallets => 'Wallets';

  @override
  String get addAWallet => 'Add a wallet';

  @override
  String get createANewWallet => 'Create a new wallet';

  @override
  String get aFreshRecoveryPhrase => 'A fresh recovery phrase';

  @override
  String get importARecoveryPhrase => 'Import a recovery phrase';

  @override
  String get another12Or24Word => 'Another 12 or 24-word wallet';

  @override
  String get watchAnAddress => 'Watch an address';

  @override
  String get followABalanceWithoutThe => 'Follow a balance without the keys';

  @override
  String get recoveryPhrase => 'Recovery phrase';

  @override
  String watchOnly(Object p0) {
    return 'Watch-only · $p0';
  }

  @override
  String get walletOptions => 'Wallet options';

  @override
  String get rename => 'Rename';

  @override
  String get editAddresses => 'Edit addresses';

  @override
  String get remove => 'Remove';

  @override
  String get walletName => 'Wallet name';

  @override
  String remove2(Object name) {
    return 'Remove $name?';
  }

  @override
  String get theFollowedAddressesAreForgotten =>
      'The followed addresses are forgotten. Nothing on the blockchain changes.';

  @override
  String get withoutItsRecoveryPhraseThe =>
      'Without its recovery phrase the funds in this wallet are unrecoverable. Make sure you have your backup before continuing.';

  @override
  String get confirmYourPassword => 'Confirm your password';

  @override
  String get enterAnAddressToFollow => 'Enter an address to follow';

  @override
  String get thisNameHasCharactersThe =>
      'This name has characters the wallet cannot read exactly';

  @override
  String get couldNotLookTheName => 'Could not look the name up.';

  @override
  String pointsToNoAddress(Object name) {
    return '$name points to no address';
  }

  @override
  String get scanAnAddress => 'Scan an address';

  @override
  String addressOtherAddresses(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Following $count addresses.',
      one: 'Following $count address.',
    );
    return '$_temp0';
  }

  @override
  String get walletUpdated => 'Wallet updated.';

  @override
  String get watchOnlyWallet => 'Watch-only wallet';

  @override
  String get editWatchOnlyWallet => 'Edit watch-only wallet';

  @override
  String get followAnAddress => 'Follow an address';

  @override
  String get seeTheBalanceTokensAnd =>
      'See the balance, tokens and history of an address you do not hold the keys for — a cold wallet, a savings account or a friend\'s public address. Nothing secret is stored and this wallet can never send.';

  @override
  String get eGColdStorage => 'e.g. Cold storage';

  @override
  String get address => 'Address';

  @override
  String get bc10xNameEthSolana =>
      'bc1…, 0x…, name.eth, Solana or Aptos address';

  @override
  String get paste => 'Paste';

  @override
  String get scan => 'Scan';

  @override
  String get addAddress => 'Add address';

  @override
  String get remove3 => 'Remove';

  @override
  String get oneAddressPerKindAn =>
      'One address per kind: an EVM address is the same on Ethereum, Base, Polygon, Arbitrum, BNB Chain and Sepolia.';

  @override
  String get follow => 'Follow';

  @override
  String get network => 'Network';

  @override
  String get mainnets => 'Mainnets';

  @override
  String get testnets => 'Testnets';

  @override
  String testnet(Object group) {
    return '$group · Testnet';
  }

  @override
  String get wallet => 'Wallet';

  @override
  String get settings => 'Settings';

  @override
  String get portfolio => 'Portfolio';

  @override
  String get refresh => 'Refresh';

  @override
  String get totalAcrossNetworks => 'Total across networks';

  @override
  String get someNetworksCouldNotBe =>
      'Some networks could not be read, so this total may be too low.';

  @override
  String get unavailable => 'Unavailable';

  @override
  String tokenOtherTokens(String native, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tokens',
      one: '$count token',
    );
    return '$native · $_temp0';
  }

  @override
  String get receive => 'Receive';

  @override
  String get noWalletFound => 'No wallet found';

  @override
  String get unlockYourWalletToGenerate =>
      'Unlock your wallet to generate a receive address.';

  @override
  String scanToPay(Object p0, Object symbol) {
    return 'Scan to pay $p0 $symbol';
  }

  @override
  String scanToReceive(Object symbol) {
    return 'Scan to receive $symbol';
  }

  @override
  String onlySendOnToThis(Object symbol, Object name) {
    return 'Only send $symbol on $name to this address.';
  }

  @override
  String get requestAnAmountOptional => 'Request an amount (optional)';

  @override
  String get enterAValidAmount => 'Enter a valid amount';

  @override
  String get sharePaymentRequest => 'Share payment request';

  @override
  String get yourAddress => 'Your address';

  @override
  String get copyAddress => 'Copy address';

  @override
  String pleaseSendOnTo(
    Object p0,
    Object symbol,
    Object name,
    Object address,
    Object link,
  ) {
    return 'Please send $p0 $symbol on $name to $address\n$link';
  }

  @override
  String get paymentRequest => 'Payment request';

  @override
  String get couldNotShareTheRequest => 'Could not share the request.';

  @override
  String get addressCopiedToClipboard => 'Address copied to clipboard';

  @override
  String get addressBook => 'Address book';

  @override
  String get add => 'Add';

  @override
  String get noSavedRecipients => 'No saved recipients';

  @override
  String get saveTheAddressesYouSend =>
      'Save the addresses you send to often and they will appear here and in the send flow.';

  @override
  String saved(Object label) {
    return 'Saved “$label”.';
  }

  @override
  String get newRecipient => 'New recipient';

  @override
  String get label => 'Label';

  @override
  String get saveRecipient => 'Save recipient';

  @override
  String get yourAddresses => 'Your addresses';

  @override
  String get beforeReceivingLargeAmountsCheck =>
      'Before receiving large amounts, check these addresses against your recovery phrase on a second, trusted device.';

  @override
  String get locked => 'Locked';

  @override
  String onlySendOnHere(Object symbol, Object name) {
    return 'Only send $symbol on $name here.';
  }

  @override
  String get displayCurrency => 'Display currency';

  @override
  String get appearance => 'Appearance';

  @override
  String get currency => 'Currency';

  @override
  String get about => 'About';

  @override
  String get selfCustodialWallet => 'Self-custodial wallet';

  @override
  String get watchOnlyMode => 'Watch-only mode';

  @override
  String get noKeysOnThisDevice => 'No keys on this device';

  @override
  String get encryptedOnThisDevice => 'Encrypted on this device';

  @override
  String created(Object p0) {
    return 'Created $p0';
  }

  @override
  String get seedEncryptedWithAes256 => 'Seed encrypted with AES-256-GCM';

  @override
  String get nothingSecretIsStored => 'Nothing secret is stored';

  @override
  String get activeNetwork => 'Active network';

  @override
  String testnet2(Object name) {
    return '$name · Testnet';
  }

  @override
  String get fingerprintUnlockEnabled => 'Fingerprint unlock enabled.';

  @override
  String get fingerprintUnlockWasNotEnabled =>
      'Fingerprint unlock was not enabled.';

  @override
  String get enable => 'Enable';

  @override
  String get tokenApprovals => 'Token approvals';

  @override
  String get reviewAndRevokeWhatContracts =>
      'Review and revoke what contracts may spend your tokens';

  @override
  String get notAvailableOnThisDevice => 'Not available on this device';

  @override
  String get opensTheWalletWithoutTyping =>
      'Opens the wallet without typing the password';

  @override
  String get confirmsYourPasswordOnceTo =>
      'Confirms your password once to set up';

  @override
  String get autoLock => 'Auto-lock';

  @override
  String get transferNotifications => 'Transfer notifications';

  @override
  String get tellsYouWhenAnOutgoing =>
      'Tells you when an outgoing transfer confirms';

  @override
  String get notifyWhenClosed => 'Notify when closed';

  @override
  String get checksForIncomingFundsAnd =>
      'Checks for incoming funds and confirmed transfers about every 15 minutes, even with the app closed. Needs no password.';

  @override
  String get notificationsWereNotAllowedYou =>
      'Notifications were not allowed. You can enable them in system settings.';

  @override
  String get never => 'Never';

  @override
  String get immediately => 'Immediately';

  @override
  String secondOtherSeconds(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'After $count seconds',
      one: 'After $count second',
    );
    return '$_temp0';
  }

  @override
  String minuteOtherMinutes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'After $count minutes',
      one: 'After $count minute',
    );
    return '$_temp0';
  }

  @override
  String get autoLockAfter => 'Auto-lock after';

  @override
  String walletOnThisDeviceOther(String name, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count wallets on this device',
      one: '$count wallet on this device',
    );
    return '$name · $_temp0';
  }

  @override
  String get activeAccount => 'Active account';

  @override
  String ofLabel(String name, int index, int count) {
    return '$name · $index of $count';
  }

  @override
  String get followedAddress => 'Followed address';

  @override
  String get receiveAddress => 'Receive address';

  @override
  String get noAddress => 'No address';

  @override
  String get walletLocked => 'Wallet locked';

  @override
  String get thisWalletFollowsNoAddress =>
      'This wallet follows no address on the active network';

  @override
  String get watchOnlyCannotSend => 'Watch-only — cannot send';

  @override
  String get derivedForTheActiveNetwork => 'Derived for the active network';

  @override
  String get allChainsWithQrCodes => 'All chains, with QR codes';

  @override
  String wordBip39Phrase(Object length) {
    return '$length-word BIP-39 phrase';
  }

  @override
  String get changePassword => 'Change password';

  @override
  String get savedRecipientsAndLabels => 'Saved recipients and labels';

  @override
  String get lockWallet => 'Lock wallet';

  @override
  String get clearTheDecryptedSeedFrom =>
      'Clear the decrypted seed from memory';

  @override
  String get eraseRecoveryPhrases => 'Erase recovery phrases';

  @override
  String get deletesEveryEncryptedSeedAnd =>
      'Deletes every encrypted seed and the password; watch-only wallets stay';

  @override
  String get defaultLabel => 'Default';

  @override
  String get addAccount => 'Add account';

  @override
  String get aFreshSetOfAddresses =>
      'A fresh set of addresses from the same seed';

  @override
  String get accountName => 'Account name';

  @override
  String get eGSavingsEmptyDefault => 'e.g. Savings (empty = default)';

  @override
  String get revealRecoveryPhrase => 'Reveal recovery phrase?';

  @override
  String get makeSureNobodyCanSee =>
      'Make sure nobody can see your screen. Anyone who reads these words can take your funds.';

  @override
  String get reveal => 'Reveal';

  @override
  String get revealRecoveryPhrase2 => 'Reveal recovery phrase';

  @override
  String wordKeepItOfflineOther(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count words · keep them offline.',
      one: '$count word · keep it offline.',
    );
    return '$_temp0';
  }

  @override
  String get thisWalletAlsoUsesA =>
      'This wallet also uses a BIP-39 passphrase (25th word). Restoring needs both: the words alone open a different, empty wallet. The passphrase is not shown here.';

  @override
  String get eraseEveryRecoveryPhrase => 'Erase every recovery phrase?';

  @override
  String get thisDeletesAllRecoveryPhrases =>
      'This deletes all recovery phrases and the password from this device. Without the backups the funds are unrecoverable. Watch-only wallets are kept. Make sure you have your backups before continuing.';

  @override
  String get theRecoveryPhraseIsRe =>
      'The recovery phrase is re-encrypted with the new password.';

  @override
  String newPasswordMinCharacters(Object minLength) {
    return 'New password (min. $minLength characters)';
  }

  @override
  String get confirmNewPassword => 'Confirm new password';

  @override
  String get reEncrypting => 'Re-encrypting…';

  @override
  String get saveNewPassword => 'Save new password';

  @override
  String get newPasswordsDoNotMatch => 'New passwords do not match';

  @override
  String get couldNotChangeThePassword => 'Could not change the password.';

  @override
  String get passwordUpdatedFingerprintUnlockWas =>
      'Password updated. Fingerprint unlock was turned off — enable it again in Settings.';

  @override
  String get passwordUpdatedSuccessfully => 'Password updated successfully.';

  @override
  String get system => 'System';

  @override
  String get light => 'Light';

  @override
  String get dark => 'Dark';

  @override
  String get pricesAreConvertedFromUsd => 'Prices are converted from USD';

  @override
  String get version => 'Version';

  @override
  String get selfCustodialBip39Bip =>
      'Self-custodial · BIP-39 / BIP-84 / BIP-44';

  @override
  String materialWalletBuiltWithFlutter(Object appVersion) {
    return 'Material Wallet $appVersion — built with Flutter & Material 3.';
  }

  @override
  String get dataSources => 'Data sources';

  @override
  String get mempoolSpaceBlockscoutCoingeckoPublicnode =>
      'mempool.space · Blockscout · CoinGecko · PublicNode · dRPC · 1RPC · official chain RPCs (Base, Arbitrum, Polygon, BNB) · Solana RPC · Aptos fullnode · Aptos Labs indexer (Aptos token balances)';

  @override
  String get materialWalletDemoBuild => 'Material Wallet · demo build';

  @override
  String get couldNotLoadYourApprovals => 'Could not load your approvals.';

  @override
  String get approvalsUnavailable => 'Approvals unavailable';

  @override
  String pullDownToTryAgain(Object error) {
    return '$error Pull down to try again.';
  }

  @override
  String get noActiveApprovals => 'No active approvals';

  @override
  String get noContractOnThisNetwork =>
      'No contract on this network is allowed to spend your tokens. A scam site that asked for approval would show up here.';

  @override
  String get aWatchOnlyWalletCannot =>
      'A watch-only wallet cannot revoke approvals.';

  @override
  String revokeApproval(Object symbol) {
    return 'Revoke $symbol approval?';
  }

  @override
  String thisSetsTheAllowanceFor(Object p0, Object symbol) {
    return 'This sets the allowance for $p0 to zero, so it can no longer move your $symbol. Contracts that need the approval will stop working until you grant it again.';
  }

  @override
  String get keepIt => 'Keep it';

  @override
  String get revoke => 'Revoke';

  @override
  String get revokeApproval2 => 'Revoke approval';

  @override
  String get confirmRevoke => 'Confirm revoke';

  @override
  String couldNotReachToPrice(Object name) {
    return 'Could not reach $name to price the revoke.';
  }

  @override
  String get theRevokeCouldNotBe =>
      'The revoke could not be sent. Nothing changed.';

  @override
  String get revokeSubmitted => 'Revoke submitted.';

  @override
  String approvedFor(Object p0) {
    return 'Approved for $p0';
  }

  @override
  String get unlimitedThisContractCanMove =>
      'Unlimited — this contract can move all of it at any time.';

  @override
  String get undo => 'Undo';

  @override
  String get nothingFollowedHere => 'Nothing followed here';

  @override
  String thisWatchOnlyWalletHas(Object name) {
    return 'This watch-only wallet has no address on $name. Pick another network, or follow an address of this kind from Settings → Wallets.';
  }

  @override
  String get tokens => 'Tokens';

  @override
  String get approvals => 'Approvals';

  @override
  String hideTheHidden(Object hiddenCount) {
    return 'Hide the $hiddenCount hidden';
  }

  @override
  String showHidden(Object hiddenCount) {
    return 'Show $hiddenCount hidden';
  }

  @override
  String get recentActivity => 'Recent activity';

  @override
  String get seeAll => 'See all';

  @override
  String get everyNetworkInOneList => 'Every network in one list';

  @override
  String get noTransactionsOnThisNetwork =>
      'No transactions on this network yet. Receive some funds to see them here.';

  @override
  String youCanFollowThisAddress(String name) {
    return '$name — you can follow this address, but not send from it.';
  }

  @override
  String get showBalance => 'Show balance';

  @override
  String get hideBalance => 'Hide balance';

  @override
  String get testnetNoMarketPrice => 'Testnet — no market price';

  @override
  String get priceTemporarilyUnavailable => 'Price temporarily unavailable';

  @override
  String get retry => 'Retry';

  @override
  String yourAddress2(Object networkLabel) {
    return 'Your address · $networkLabel';
  }

  @override
  String get copy => 'Copy';

  @override
  String get explorer => 'Explorer';

  @override
  String get loadingOnChainData => 'Loading on-chain data…';

  @override
  String get couldNotLoadData => 'Could not load data';

  @override
  String get tryAgain => 'Try again';

  @override
  String get scanQrCode => 'Scan QR code';

  @override
  String get toggleFlashlight => 'Toggle flashlight';

  @override
  String get switchCamera => 'Switch camera';

  @override
  String get pointTheCameraAtA => 'Point the camera at a wallet QR code';

  @override
  String get yourRecoveryPhrase => 'Your recovery phrase';

  @override
  String writeTheseWordsDown(Object length) {
    return 'Write these $length words down';
  }

  @override
  String get theyAreTheOnlyWay =>
      'They are the only way to restore your wallet. Store them offline — anyone who reads them can take your funds.';

  @override
  String get copyPhrase => 'Copy phrase';

  @override
  String get neverShareThisPhraseMaterial =>
      'Never share this phrase. Material Wallet will never ask you for it.';

  @override
  String get iHaveWrittenDownMy => 'I have written down my recovery phrase';

  @override
  String get continueLabel => 'Continue';

  @override
  String get recoveryPhraseCopiedClearedAutomatically =>
      'Recovery phrase copied — cleared automatically';

  @override
  String get importWallet => 'Import wallet';

  @override
  String get enterYourRecoveryPhrase => 'Enter your recovery phrase';

  @override
  String get typeOrPasteThe12 =>
      'Type or paste the 12 or 24 words separated by spaces. The checksum is verified locally before anything is stored.';

  @override
  String get wordOneWordTwoWord => 'word one word two word three …';

  @override
  String get passphrase25thWordOptional => 'Passphrase (25th word) — optional';

  @override
  String get leaveEmptyIfYouNever => 'leave empty if you never set one';

  @override
  String get waitingForYourPhrase => 'Waiting for your phrase';

  @override
  String validWordPhrase(Object wordCount) {
    return 'Valid $wordCount-word phrase';
  }

  @override
  String wordSChecksumNotValid(Object wordCount) {
    return '$wordCount word(s) — checksum not valid yet';
  }

  @override
  String get ifYourPhraseWasCreated =>
      'If your phrase was created with a passphrase (a 25th word), enter it below — a missing or mistyped one derives different addresses and every balance would show as zero.';

  @override
  String get aSelfCustodialWalletYour =>
      'A self-custodial wallet. Your keys never leave this device — the recovery phrase is generated here and stored locally.';

  @override
  String get iAlreadyHaveAWallet => 'I already have a wallet';

  @override
  String get justWatchAnAddress => 'Just watch an address';

  @override
  String get verifyBackup => 'Verify backup';

  @override
  String get confirmYourRecoveryPhrase => 'Confirm your recovery phrase';

  @override
  String get typeTheWordsBelowExactly =>
      'Type the words below exactly as they appear in your backup. The positions are chosen at random every time, so you cannot predict which ones will be asked.';

  @override
  String word(Object p0) {
    return 'Word #$p0';
  }

  @override
  String get typeTheWord => 'Type the word';

  @override
  String get aWatchOnlyWalletCannot2 =>
      'A watch-only wallet cannot send or replace transfers.';

  @override
  String get cancelThisTransfer => 'Cancel this transfer?';

  @override
  String get speedThisTransferUp => 'Speed this transfer up?';

  @override
  String thisSends0ToYourself(Object symbol) {
    return 'This sends 0 $symbol to yourself and reuses the pending transaction\'s nonce, so it can never confirm. It only works while the transaction is still pending.';
  }

  @override
  String thisReSendsTheIdentical(Object counterparty) {
    return 'This re-sends the identical token transfer to $counterparty with a higher fee, reusing the pending transaction\'s nonce and calldata. Exactly one of the two will confirm.';
  }

  @override
  String thisSendsToAgainWith(Object p0, Object counterparty) {
    return 'This sends $p0 to $counterparty again with a higher fee, reusing the pending transaction\'s nonce. Exactly one of the two will confirm.';
  }

  @override
  String get cancelTransfer => 'Cancel transfer';

  @override
  String get confirmCancel => 'Confirm cancel';

  @override
  String get confirmSpeedUp => 'Confirm speed up';

  @override
  String couldNotReachToPrice2(Object name) {
    return 'Could not reach $name to price the replacement.';
  }

  @override
  String get replacementSubmittedTheOriginalCan =>
      'Replacement submitted — the original can no longer confirm.';

  @override
  String get fasterReplacementSubmitted => 'Faster replacement submitted.';

  @override
  String get theReplacementCouldNotBe =>
      'The replacement could not be sent. Nothing changed.';

  @override
  String get thisTransferCannotBeSped => 'This transfer cannot be sped up.';

  @override
  String theSamePaymentIsSent(Object p0, Object p1, Object feeRate) {
    return 'The same payment is sent again with a higher fee, paid out of your change: $p0 → $p1 ($feeRate sat/vB). The recipient still gets the same amount; exactly one of the two transfers will confirm.';
  }

  @override
  String get send => 'Send';

  @override
  String get thisWalletFollowsAnAddress =>
      'This wallet follows an address but holds no keys, so it cannot send. Switch to a wallet with a recovery phrase in Settings → Wallets.';

  @override
  String get accountDataUnavailable => 'Account data unavailable';

  @override
  String get theBalanceIsStillLoading =>
      'The balance is still loading. Go back and try again.';

  @override
  String send2(Object symbol) {
    return 'Send $symbol';
  }

  @override
  String get available => 'Available';

  @override
  String amountIn(Object code) {
    return 'Amount in $code';
  }

  @override
  String get amount => 'Amount';

  @override
  String notEnoughOrTooLittle(Object symbol, Object p1) {
    return 'Not enough $symbol, or too little $p1 for the fee';
  }

  @override
  String get notEnoughFundsForAmount => 'Not enough funds for amount + fee';

  @override
  String enterIn(Object symbol) {
    return 'Enter in $symbol';
  }

  @override
  String enterIn2(Object code) {
    return 'Enter in $code';
  }

  @override
  String get max => 'MAX';

  @override
  String get recipientAddress => 'Recipient address';

  @override
  String get base58Address => 'Base58 address';

  @override
  String get resolvingTheName => 'Resolving the name…';

  @override
  String get scanQrCode2 => 'Scan QR code';

  @override
  String gweiTipGweiCap(Object p0, Object p1) {
    return '$p0 gwei tip · $p1 gwei cap';
  }

  @override
  String get networkFee => 'Network fee';

  @override
  String get maxNetworkFee => 'Max network fee';

  @override
  String get reviewTransfer => 'Review transfer';

  @override
  String thisIsWhatGetsSigned(Object p0) {
    return '≈ $p0 (this is what gets signed)';
  }

  @override
  String get thisNameUsesCharactersThe =>
      'This name uses characters the wallet cannot resolve safely.';

  @override
  String doesNotPointToAn(Object name) {
    return '$name does not point to an address.';
  }

  @override
  String get theResolverReturnedAnInvalid =>
      'The resolver returned an invalid address.';

  @override
  String couldNotLookUp(Object name, Object message) {
    return 'Could not look up $name: $message';
  }

  @override
  String get clipboardIsEmpty => 'Clipboard is empty.';

  @override
  String get thisPaymentLinkIsNot =>
      'This payment link is not supported — nothing was filled in.';

  @override
  String get differentNetwork => 'Different network';

  @override
  String thisLinkTargetsButThe(Object name, Object p1) {
    return 'This link targets $name, but the send screen is set to $p1. Switch?';
  }

  @override
  String get switchLabel => 'Switch';

  @override
  String thisLinkPaysWithA(Object name) {
    return 'This link pays with a token that is not in your $name balance. Open the network, let it sync and scan the code again.';
  }

  @override
  String couldNotReachToPrice3(Object name) {
    return 'Could not reach $name to price this transfer. Nothing was sent.';
  }

  @override
  String includesTheOneTimeDeposit(Object symbol) {
    return 'Includes the one-time deposit that opens the recipient\'s $symbol account. The recipient has no account for this token yet.';
  }

  @override
  String get confirmTransfer => 'Confirm transfer';

  @override
  String get theTransferFailedNothingWas =>
      'The transfer failed. Nothing was sent.';

  @override
  String hasNoTransactionHistoryIn(Object name) {
    return '$name has no transaction history in this wallet. You can send, but a stuck transfer cannot be sped up or cancelled here, you will not get a confirmation notification, and the recipient is not checked against your past payments or scam lists. Double-check the address.';
  }

  @override
  String get saveARecipientFromThe =>
      'Save a recipient from the transfer summary and it will show up here.';

  @override
  String get eGExchange => 'e.g. Exchange';

  @override
  String get estimating => 'Estimating…';

  @override
  String get total => 'Total';

  @override
  String get transferPrepared => 'Transfer prepared';

  @override
  String validatedAgainstTheLiveBalance(Object name) {
    return 'Validated against the live balance on $name.';
  }

  @override
  String get ensName => 'ENS name';

  @override
  String get to => 'To';

  @override
  String get sendingIsBlockedUntilYou =>
      'Sending is blocked until you fix the recipient above.';

  @override
  String sendingIsNotSupportedOn(Object name) {
    return 'Sending is not supported on $name yet. Restore your recovery phrase in a signing wallet to move funds.';
  }

  @override
  String theTransferIsSignedOn(Object name) {
    return 'The transfer is signed on this device and sent straight to $name. It cannot be undone.';
  }

  @override
  String send3(Object amountSymbol) {
    return 'Send $amountSymbol';
  }

  @override
  String get copyDetails => 'Copy details';

  @override
  String get viewRecipientOnExplorer => 'View recipient on explorer';

  @override
  String to2(Object recipient) {
    return 'To: $recipient';
  }

  @override
  String amount2(Object p0) {
    return 'Amount: $p0';
  }

  @override
  String fee(Object p0) {
    return 'Fee: $p0';
  }

  @override
  String get transferDetailsCopied => 'Transfer details copied';

  @override
  String get thisAddressLooksLikeAnother =>
      'This address looks like another one you use';

  @override
  String itStartsAndEndsLike(Object p0) {
    return 'It starts and ends like $p0, which you have already sent to. Scammers copy the visible ends of a real address and wait for you to send funds to it. Check the middle of the address before continuing.';
  }

  @override
  String get enterAPriorityFeeAbove => 'Enter a priority fee above 0.';

  @override
  String get theFeeCapMustBe =>
      'The fee cap must be at least the priority fee.';

  @override
  String get customNetworkFee => 'Custom network fee';

  @override
  String currentBaseFeeGwei(Object p0) {
    return 'Current base fee: $p0 gwei.';
  }

  @override
  String get priorityFeeTip => 'Priority fee (tip)';

  @override
  String get maxFeeCap => 'Max fee (cap)';

  @override
  String get apply => 'Apply';

  @override
  String get enterAFeeRateOf => 'Enter a fee rate of at least 1 sat/vB.';

  @override
  String get thatFeeRateIsUnreasonably => 'That fee rate is unreasonably high.';

  @override
  String get customFeeRate => 'Custom fee rate';

  @override
  String get theTransferPaysThisMany =>
      'The transfer pays this many satoshis per virtual byte. A higher rate confirms sooner.';

  @override
  String get feeRate => 'Fee rate';

  @override
  String get transfer => 'Transfer';

  @override
  String get transferConfirmed => 'Transfer confirmed';

  @override
  String get transferSent => 'Transfer sent';

  @override
  String get theFundsLeftYourWallet =>
      'The funds left your wallet and the transaction is mined.';

  @override
  String get theTransactionWasAcceptedAnd =>
      'The transaction was accepted and will confirm shortly. You can follow it on the explorer.';

  @override
  String get done => 'Done';

  @override
  String get transaction => 'Transaction';

  @override
  String get copyTransactionHash => 'Copy transaction hash';

  @override
  String get transactionHashCopied => 'Transaction hash copied';

  @override
  String get transferSubmitted => 'Transfer submitted';

  @override
  String get sending => 'Sending…';

  @override
  String get signingOnThisDevice => 'Signing on this device…';

  @override
  String waitingForToConfirm(Object shortTo) {
    return 'Waiting for $shortTo to confirm…';
  }

  @override
  String get confirmedOnChain => 'Confirmed on-chain.';

  @override
  String get broadcasting => 'Broadcasting…';

  @override
  String get close => 'Close';

  @override
  String get weak => 'Weak';

  @override
  String get fair => 'Fair';

  @override
  String get good => 'Good';

  @override
  String get strong => 'Strong';

  @override
  String get showLabel => 'Show';

  @override
  String get hideLabel => 'Hide';

  @override
  String get couldNotOpenYourWallet => 'Could not open your wallet';

  @override
  String get theSecureStorageOnThis =>
      'The secure storage on this device did not respond. Your wallet is not lost — try again.';

  @override
  String get language => 'Language';

  @override
  String get chooseLanguage => 'Choose language';
}
