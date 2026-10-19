import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_uk.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'gen/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('uk'),
  ];

  /// No description provided for @languageSystem.
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get languageSystem;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @languageUkrainian.
  ///
  /// In en, this message translates to:
  /// **'Українська'**
  String get languageUkrainian;

  /// No description provided for @activity.
  ///
  /// In en, this message translates to:
  /// **'Activity'**
  String get activity;

  /// No description provided for @exportCsv.
  ///
  /// In en, this message translates to:
  /// **'Export CSV'**
  String get exportCsv;

  /// No description provided for @searchAddressLabelNoteOr.
  ///
  /// In en, this message translates to:
  /// **'Search address, label, note or hash'**
  String get searchAddressLabelNoteOr;

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// No description provided for @noTransactionsYet.
  ///
  /// In en, this message translates to:
  /// **'No transactions yet'**
  String get noTransactionsYet;

  /// No description provided for @nothingMatches.
  ///
  /// In en, this message translates to:
  /// **'Nothing matches'**
  String get nothingMatches;

  /// No description provided for @onChainActivityForThis.
  ///
  /// In en, this message translates to:
  /// **'On-chain activity for this network shows up here.'**
  String get onChainActivityForThis;

  /// No description provided for @tryAnotherAddressLabelNote.
  ///
  /// In en, this message translates to:
  /// **'Try another address, label, note or hash.'**
  String get tryAnotherAddressLabelNote;

  /// No description provided for @privateNote.
  ///
  /// In en, this message translates to:
  /// **'Private note'**
  String get privateNote;

  /// No description provided for @visibleOnlyOnThisDevice.
  ///
  /// In en, this message translates to:
  /// **'Visible only on this device and in your CSV export'**
  String get visibleOnlyOnThisDevice;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @couldNotExportTheActivity.
  ///
  /// In en, this message translates to:
  /// **'Could not export the activity.'**
  String get couldNotExportTheActivity;

  /// No description provided for @loading.
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get loading;

  /// No description provided for @loadMore.
  ///
  /// In en, this message translates to:
  /// **'Load more'**
  String get loadMore;

  /// No description provided for @moneyIn.
  ///
  /// In en, this message translates to:
  /// **'Money in'**
  String get moneyIn;

  /// No description provided for @moneyOut.
  ///
  /// In en, this message translates to:
  /// **'Money out'**
  String get moneyOut;

  /// No description provided for @tokenApproval.
  ///
  /// In en, this message translates to:
  /// **'Token approval'**
  String get tokenApproval;

  /// No description provided for @failed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get failed;

  /// No description provided for @pending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get pending;

  /// No description provided for @viewOnExplorer.
  ///
  /// In en, this message translates to:
  /// **'View on explorer'**
  String get viewOnExplorer;

  /// No description provided for @moreActions.
  ///
  /// In en, this message translates to:
  /// **'More actions'**
  String get moreActions;

  /// No description provided for @addNote.
  ///
  /// In en, this message translates to:
  /// **'Add note'**
  String get addNote;

  /// No description provided for @editNote.
  ///
  /// In en, this message translates to:
  /// **'Edit note'**
  String get editNote;

  /// No description provided for @cancelTransaction.
  ///
  /// In en, this message translates to:
  /// **'Cancel transaction'**
  String get cancelTransaction;

  /// No description provided for @speedUp.
  ///
  /// In en, this message translates to:
  /// **'Speed up'**
  String get speedUp;

  /// No description provided for @welcomeBack.
  ///
  /// In en, this message translates to:
  /// **'Welcome back'**
  String get welcomeBack;

  /// No description provided for @enterYourPasswordToDecrypt.
  ///
  /// In en, this message translates to:
  /// **'Enter your password to decrypt the wallet.'**
  String get enterYourPasswordToDecrypt;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @decrypting.
  ///
  /// In en, this message translates to:
  /// **'Decrypting…'**
  String get decrypting;

  /// No description provided for @unlock.
  ///
  /// In en, this message translates to:
  /// **'Unlock'**
  String get unlock;

  /// No description provided for @theFingerprintsOnThisPhone.
  ///
  /// In en, this message translates to:
  /// **'The fingerprints on this phone changed, so fingerprint unlock was turned off. Enter your password, then enable it again in Settings.'**
  String get theFingerprintsOnThisPhone;

  /// No description provided for @unlockWithFingerprint.
  ///
  /// In en, this message translates to:
  /// **'Unlock with fingerprint'**
  String get unlockWithFingerprint;

  /// No description provided for @forgotPasswordEraseRecoveryPhrases.
  ///
  /// In en, this message translates to:
  /// **'Forgot password — erase recovery phrases'**
  String get forgotPasswordEraseRecoveryPhrases;

  /// No description provided for @enterYourPassword.
  ///
  /// In en, this message translates to:
  /// **'Enter your password'**
  String get enterYourPassword;

  /// No description provided for @couldNotUnlockTheWallet.
  ///
  /// In en, this message translates to:
  /// **'Could not unlock the wallet.'**
  String get couldNotUnlockTheWallet;

  /// No description provided for @eraseTheRecoveryPhrases.
  ///
  /// In en, this message translates to:
  /// **'Erase the recovery phrases?'**
  String get eraseTheRecoveryPhrases;

  /// No description provided for @thisDeletesEveryRecoveryPhrase.
  ///
  /// In en, this message translates to:
  /// **'This deletes every recovery phrase and the password from this device. Without the backups the funds are unrecoverable. Watch-only wallets are kept. Make sure you have your backups before continuing.'**
  String get thisDeletesEveryRecoveryPhrase;

  /// No description provided for @erase.
  ///
  /// In en, this message translates to:
  /// **'Erase'**
  String get erase;

  /// No description provided for @recoveryPhrasesErasedFromThis.
  ///
  /// In en, this message translates to:
  /// **'Recovery phrases erased from this device.'**
  String get recoveryPhrasesErasedFromThis;

  /// No description provided for @security.
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get security;

  /// No description provided for @setAPassword.
  ///
  /// In en, this message translates to:
  /// **'Set a password'**
  String get setAPassword;

  /// No description provided for @yourRecoveryPhraseIsEncrypted.
  ///
  /// In en, this message translates to:
  /// **'Your recovery phrase is encrypted with AES-256-GCM using a key derived from this password, and you will need it every time you open the wallet. A passphrase of several words is much harder to guess than a short code.'**
  String get yourRecoveryPhraseIsEncrypted;

  /// No description provided for @passwordMinCharacters.
  ///
  /// In en, this message translates to:
  /// **'Password (min. {minLength} characters)'**
  String passwordMinCharacters(Object minLength);

  /// No description provided for @confirmPassword.
  ///
  /// In en, this message translates to:
  /// **'Confirm password'**
  String get confirmPassword;

  /// No description provided for @unlockWithFingerprint2.
  ///
  /// In en, this message translates to:
  /// **'Unlock with fingerprint'**
  String get unlockWithFingerprint2;

  /// No description provided for @openTheWalletWithYour.
  ///
  /// In en, this message translates to:
  /// **'Open the wallet with your fingerprint instead of typing the password'**
  String get openTheWalletWithYour;

  /// No description provided for @thereIsNoPasswordRecovery.
  ///
  /// In en, this message translates to:
  /// **'There is no password recovery. If you forget it you will need your recovery phrase to restore the wallet.'**
  String get thereIsNoPasswordRecovery;

  /// No description provided for @encrypting.
  ///
  /// In en, this message translates to:
  /// **'Encrypting…'**
  String get encrypting;

  /// No description provided for @encryptContinue.
  ///
  /// In en, this message translates to:
  /// **'Encrypt & continue'**
  String get encryptContinue;

  /// No description provided for @useAtLeastCharacters.
  ///
  /// In en, this message translates to:
  /// **'Use at least {minLength} characters'**
  String useAtLeastCharacters(Object minLength);

  /// No description provided for @passwordsDoNotMatch.
  ///
  /// In en, this message translates to:
  /// **'Passwords do not match'**
  String get passwordsDoNotMatch;

  /// No description provided for @walletEncryptedAndStoredOn.
  ///
  /// In en, this message translates to:
  /// **'Wallet encrypted and stored on this device.'**
  String get walletEncryptedAndStoredOn;

  /// No description provided for @enterYourCurrentPassword.
  ///
  /// In en, this message translates to:
  /// **'Enter your current password'**
  String get enterYourCurrentPassword;

  /// No description provided for @walletAddedAndEncryptedOn.
  ///
  /// In en, this message translates to:
  /// **'Wallet added and encrypted on this device.'**
  String get walletAddedAndEncryptedOn;

  /// No description provided for @addWallet.
  ///
  /// In en, this message translates to:
  /// **'Add wallet'**
  String get addWallet;

  /// No description provided for @confirmWithYourPassword.
  ///
  /// In en, this message translates to:
  /// **'Confirm with your password'**
  String get confirmWithYourPassword;

  /// No description provided for @thisPhraseWillBeEncrypted.
  ///
  /// In en, this message translates to:
  /// **'This phrase will be encrypted next to your other wallets under the same password, so one unlock opens them all.'**
  String get thisPhraseWillBeEncrypted;

  /// No description provided for @nameOptional.
  ///
  /// In en, this message translates to:
  /// **'Name (optional)'**
  String get nameOptional;

  /// No description provided for @eGSavings.
  ///
  /// In en, this message translates to:
  /// **'e.g. Savings'**
  String get eGSavings;

  /// No description provided for @currentPassword.
  ///
  /// In en, this message translates to:
  /// **'Current password'**
  String get currentPassword;

  /// No description provided for @wallets.
  ///
  /// In en, this message translates to:
  /// **'Wallets'**
  String get wallets;

  /// No description provided for @addAWallet.
  ///
  /// In en, this message translates to:
  /// **'Add a wallet'**
  String get addAWallet;

  /// No description provided for @createANewWallet.
  ///
  /// In en, this message translates to:
  /// **'Create a new wallet'**
  String get createANewWallet;

  /// No description provided for @aFreshRecoveryPhrase.
  ///
  /// In en, this message translates to:
  /// **'A fresh recovery phrase'**
  String get aFreshRecoveryPhrase;

  /// No description provided for @importARecoveryPhrase.
  ///
  /// In en, this message translates to:
  /// **'Import a recovery phrase'**
  String get importARecoveryPhrase;

  /// No description provided for @another12Or24Word.
  ///
  /// In en, this message translates to:
  /// **'Another 12 or 24-word wallet'**
  String get another12Or24Word;

  /// No description provided for @watchAnAddress.
  ///
  /// In en, this message translates to:
  /// **'Watch an address'**
  String get watchAnAddress;

  /// No description provided for @followABalanceWithoutThe.
  ///
  /// In en, this message translates to:
  /// **'Follow a balance without the keys'**
  String get followABalanceWithoutThe;

  /// No description provided for @recoveryPhrase.
  ///
  /// In en, this message translates to:
  /// **'Recovery phrase'**
  String get recoveryPhrase;

  /// No description provided for @watchOnly.
  ///
  /// In en, this message translates to:
  /// **'Watch-only · {p0}'**
  String watchOnly(Object p0);

  /// No description provided for @walletOptions.
  ///
  /// In en, this message translates to:
  /// **'Wallet options'**
  String get walletOptions;

  /// No description provided for @rename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get rename;

  /// No description provided for @editAddresses.
  ///
  /// In en, this message translates to:
  /// **'Edit addresses'**
  String get editAddresses;

  /// No description provided for @remove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get remove;

  /// No description provided for @walletName.
  ///
  /// In en, this message translates to:
  /// **'Wallet name'**
  String get walletName;

  /// No description provided for @remove2.
  ///
  /// In en, this message translates to:
  /// **'Remove {name}?'**
  String remove2(Object name);

  /// No description provided for @theFollowedAddressesAreForgotten.
  ///
  /// In en, this message translates to:
  /// **'The followed addresses are forgotten. Nothing on the blockchain changes.'**
  String get theFollowedAddressesAreForgotten;

  /// No description provided for @withoutItsRecoveryPhraseThe.
  ///
  /// In en, this message translates to:
  /// **'Without its recovery phrase the funds in this wallet are unrecoverable. Make sure you have your backup before continuing.'**
  String get withoutItsRecoveryPhraseThe;

  /// No description provided for @confirmYourPassword.
  ///
  /// In en, this message translates to:
  /// **'Confirm your password'**
  String get confirmYourPassword;

  /// No description provided for @enterAnAddressToFollow.
  ///
  /// In en, this message translates to:
  /// **'Enter an address to follow'**
  String get enterAnAddressToFollow;

  /// No description provided for @thisNameHasCharactersThe.
  ///
  /// In en, this message translates to:
  /// **'This name has characters the wallet cannot read exactly'**
  String get thisNameHasCharactersThe;

  /// No description provided for @couldNotLookTheName.
  ///
  /// In en, this message translates to:
  /// **'Could not look the name up.'**
  String get couldNotLookTheName;

  /// No description provided for @pointsToNoAddress.
  ///
  /// In en, this message translates to:
  /// **'{name} points to no address'**
  String pointsToNoAddress(Object name);

  /// No description provided for @scanAnAddress.
  ///
  /// In en, this message translates to:
  /// **'Scan an address'**
  String get scanAnAddress;

  /// No description provided for @addressOtherAddresses.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{Following {count} address.} other{Following {count} addresses.}}'**
  String addressOtherAddresses(int count);

  /// No description provided for @walletUpdated.
  ///
  /// In en, this message translates to:
  /// **'Wallet updated.'**
  String get walletUpdated;

  /// No description provided for @watchOnlyWallet.
  ///
  /// In en, this message translates to:
  /// **'Watch-only wallet'**
  String get watchOnlyWallet;

  /// No description provided for @editWatchOnlyWallet.
  ///
  /// In en, this message translates to:
  /// **'Edit watch-only wallet'**
  String get editWatchOnlyWallet;

  /// No description provided for @followAnAddress.
  ///
  /// In en, this message translates to:
  /// **'Follow an address'**
  String get followAnAddress;

  /// No description provided for @seeTheBalanceTokensAnd.
  ///
  /// In en, this message translates to:
  /// **'See the balance, tokens and history of an address you do not hold the keys for — a cold wallet, a savings account or a friend\'s public address. Nothing secret is stored and this wallet can never send.'**
  String get seeTheBalanceTokensAnd;

  /// No description provided for @eGColdStorage.
  ///
  /// In en, this message translates to:
  /// **'e.g. Cold storage'**
  String get eGColdStorage;

  /// No description provided for @address.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get address;

  /// No description provided for @bc10xNameEthSolana.
  ///
  /// In en, this message translates to:
  /// **'bc1…, 0x…, name.eth, Solana or Aptos address'**
  String get bc10xNameEthSolana;

  /// No description provided for @paste.
  ///
  /// In en, this message translates to:
  /// **'Paste'**
  String get paste;

  /// No description provided for @scan.
  ///
  /// In en, this message translates to:
  /// **'Scan'**
  String get scan;

  /// No description provided for @addAddress.
  ///
  /// In en, this message translates to:
  /// **'Add address'**
  String get addAddress;

  /// No description provided for @remove3.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get remove3;

  /// No description provided for @oneAddressPerKindAn.
  ///
  /// In en, this message translates to:
  /// **'One address per kind: an EVM address is the same on Ethereum, Base, Polygon, Arbitrum, BNB Chain and Sepolia.'**
  String get oneAddressPerKindAn;

  /// No description provided for @follow.
  ///
  /// In en, this message translates to:
  /// **'Follow'**
  String get follow;

  /// No description provided for @network.
  ///
  /// In en, this message translates to:
  /// **'Network'**
  String get network;

  /// No description provided for @mainnets.
  ///
  /// In en, this message translates to:
  /// **'Mainnets'**
  String get mainnets;

  /// No description provided for @testnets.
  ///
  /// In en, this message translates to:
  /// **'Testnets'**
  String get testnets;

  /// No description provided for @testnet.
  ///
  /// In en, this message translates to:
  /// **'{group} · Testnet'**
  String testnet(Object group);

  /// No description provided for @wallet.
  ///
  /// In en, this message translates to:
  /// **'Wallet'**
  String get wallet;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @portfolio.
  ///
  /// In en, this message translates to:
  /// **'Portfolio'**
  String get portfolio;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @totalAcrossNetworks.
  ///
  /// In en, this message translates to:
  /// **'Total across networks'**
  String get totalAcrossNetworks;

  /// No description provided for @someNetworksCouldNotBe.
  ///
  /// In en, this message translates to:
  /// **'Some networks could not be read, so this total may be too low.'**
  String get someNetworksCouldNotBe;

  /// No description provided for @unavailable.
  ///
  /// In en, this message translates to:
  /// **'Unavailable'**
  String get unavailable;

  /// No description provided for @tokenOtherTokens.
  ///
  /// In en, this message translates to:
  /// **'{native} · {count, plural, one{{count} token} other{{count} tokens}}'**
  String tokenOtherTokens(String native, int count);

  /// No description provided for @receive.
  ///
  /// In en, this message translates to:
  /// **'Receive'**
  String get receive;

  /// No description provided for @noWalletFound.
  ///
  /// In en, this message translates to:
  /// **'No wallet found'**
  String get noWalletFound;

  /// No description provided for @unlockYourWalletToGenerate.
  ///
  /// In en, this message translates to:
  /// **'Unlock your wallet to generate a receive address.'**
  String get unlockYourWalletToGenerate;

  /// No description provided for @scanToPay.
  ///
  /// In en, this message translates to:
  /// **'Scan to pay {p0} {symbol}'**
  String scanToPay(Object p0, Object symbol);

  /// No description provided for @scanToReceive.
  ///
  /// In en, this message translates to:
  /// **'Scan to receive {symbol}'**
  String scanToReceive(Object symbol);

  /// No description provided for @onlySendOnToThis.
  ///
  /// In en, this message translates to:
  /// **'Only send {symbol} on {name} to this address.'**
  String onlySendOnToThis(Object symbol, Object name);

  /// No description provided for @requestAnAmountOptional.
  ///
  /// In en, this message translates to:
  /// **'Request an amount (optional)'**
  String get requestAnAmountOptional;

  /// No description provided for @enterAValidAmount.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid amount'**
  String get enterAValidAmount;

  /// No description provided for @sharePaymentRequest.
  ///
  /// In en, this message translates to:
  /// **'Share payment request'**
  String get sharePaymentRequest;

  /// No description provided for @yourAddress.
  ///
  /// In en, this message translates to:
  /// **'Your address'**
  String get yourAddress;

  /// No description provided for @copyAddress.
  ///
  /// In en, this message translates to:
  /// **'Copy address'**
  String get copyAddress;

  /// No description provided for @pleaseSendOnTo.
  ///
  /// In en, this message translates to:
  /// **'Please send {p0} {symbol} on {name} to {address}\n{link}'**
  String pleaseSendOnTo(
    Object p0,
    Object symbol,
    Object name,
    Object address,
    Object link,
  );

  /// No description provided for @paymentRequest.
  ///
  /// In en, this message translates to:
  /// **'Payment request'**
  String get paymentRequest;

  /// No description provided for @couldNotShareTheRequest.
  ///
  /// In en, this message translates to:
  /// **'Could not share the request.'**
  String get couldNotShareTheRequest;

  /// No description provided for @addressCopiedToClipboard.
  ///
  /// In en, this message translates to:
  /// **'Address copied to clipboard'**
  String get addressCopiedToClipboard;

  /// No description provided for @addressBook.
  ///
  /// In en, this message translates to:
  /// **'Address book'**
  String get addressBook;

  /// No description provided for @add.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// No description provided for @noSavedRecipients.
  ///
  /// In en, this message translates to:
  /// **'No saved recipients'**
  String get noSavedRecipients;

  /// No description provided for @saveTheAddressesYouSend.
  ///
  /// In en, this message translates to:
  /// **'Save the addresses you send to often and they will appear here and in the send flow.'**
  String get saveTheAddressesYouSend;

  /// No description provided for @saved.
  ///
  /// In en, this message translates to:
  /// **'Saved “{label}”.'**
  String saved(Object label);

  /// No description provided for @newRecipient.
  ///
  /// In en, this message translates to:
  /// **'New recipient'**
  String get newRecipient;

  /// No description provided for @label.
  ///
  /// In en, this message translates to:
  /// **'Label'**
  String get label;

  /// No description provided for @saveRecipient.
  ///
  /// In en, this message translates to:
  /// **'Save recipient'**
  String get saveRecipient;

  /// No description provided for @yourAddresses.
  ///
  /// In en, this message translates to:
  /// **'Your addresses'**
  String get yourAddresses;

  /// No description provided for @beforeReceivingLargeAmountsCheck.
  ///
  /// In en, this message translates to:
  /// **'Before receiving large amounts, check these addresses against your recovery phrase on a second, trusted device.'**
  String get beforeReceivingLargeAmountsCheck;

  /// No description provided for @locked.
  ///
  /// In en, this message translates to:
  /// **'Locked'**
  String get locked;

  /// No description provided for @onlySendOnHere.
  ///
  /// In en, this message translates to:
  /// **'Only send {symbol} on {name} here.'**
  String onlySendOnHere(Object symbol, Object name);

  /// No description provided for @displayCurrency.
  ///
  /// In en, this message translates to:
  /// **'Display currency'**
  String get displayCurrency;

  /// No description provided for @appearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearance;

  /// No description provided for @currency.
  ///
  /// In en, this message translates to:
  /// **'Currency'**
  String get currency;

  /// No description provided for @about.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get about;

  /// No description provided for @selfCustodialWallet.
  ///
  /// In en, this message translates to:
  /// **'Self-custodial wallet'**
  String get selfCustodialWallet;

  /// No description provided for @watchOnlyMode.
  ///
  /// In en, this message translates to:
  /// **'Watch-only mode'**
  String get watchOnlyMode;

  /// No description provided for @noKeysOnThisDevice.
  ///
  /// In en, this message translates to:
  /// **'No keys on this device'**
  String get noKeysOnThisDevice;

  /// No description provided for @encryptedOnThisDevice.
  ///
  /// In en, this message translates to:
  /// **'Encrypted on this device'**
  String get encryptedOnThisDevice;

  /// No description provided for @created.
  ///
  /// In en, this message translates to:
  /// **'Created {p0}'**
  String created(Object p0);

  /// No description provided for @seedEncryptedWithAes256.
  ///
  /// In en, this message translates to:
  /// **'Seed encrypted with AES-256-GCM'**
  String get seedEncryptedWithAes256;

  /// No description provided for @nothingSecretIsStored.
  ///
  /// In en, this message translates to:
  /// **'Nothing secret is stored'**
  String get nothingSecretIsStored;

  /// No description provided for @activeNetwork.
  ///
  /// In en, this message translates to:
  /// **'Active network'**
  String get activeNetwork;

  /// No description provided for @testnet2.
  ///
  /// In en, this message translates to:
  /// **'{name} · Testnet'**
  String testnet2(Object name);

  /// No description provided for @fingerprintUnlockEnabled.
  ///
  /// In en, this message translates to:
  /// **'Fingerprint unlock enabled.'**
  String get fingerprintUnlockEnabled;

  /// No description provided for @fingerprintUnlockWasNotEnabled.
  ///
  /// In en, this message translates to:
  /// **'Fingerprint unlock was not enabled.'**
  String get fingerprintUnlockWasNotEnabled;

  /// No description provided for @enable.
  ///
  /// In en, this message translates to:
  /// **'Enable'**
  String get enable;

  /// No description provided for @tokenApprovals.
  ///
  /// In en, this message translates to:
  /// **'Token approvals'**
  String get tokenApprovals;

  /// No description provided for @reviewAndRevokeWhatContracts.
  ///
  /// In en, this message translates to:
  /// **'Review and revoke what contracts may spend your tokens'**
  String get reviewAndRevokeWhatContracts;

  /// No description provided for @notAvailableOnThisDevice.
  ///
  /// In en, this message translates to:
  /// **'Not available on this device'**
  String get notAvailableOnThisDevice;

  /// No description provided for @opensTheWalletWithoutTyping.
  ///
  /// In en, this message translates to:
  /// **'Opens the wallet without typing the password'**
  String get opensTheWalletWithoutTyping;

  /// No description provided for @confirmsYourPasswordOnceTo.
  ///
  /// In en, this message translates to:
  /// **'Confirms your password once to set up'**
  String get confirmsYourPasswordOnceTo;

  /// No description provided for @autoLock.
  ///
  /// In en, this message translates to:
  /// **'Auto-lock'**
  String get autoLock;

  /// No description provided for @transferNotifications.
  ///
  /// In en, this message translates to:
  /// **'Transfer notifications'**
  String get transferNotifications;

  /// No description provided for @tellsYouWhenAnOutgoing.
  ///
  /// In en, this message translates to:
  /// **'Tells you when an outgoing transfer confirms'**
  String get tellsYouWhenAnOutgoing;

  /// No description provided for @notifyWhenClosed.
  ///
  /// In en, this message translates to:
  /// **'Notify when closed'**
  String get notifyWhenClosed;

  /// No description provided for @checksForIncomingFundsAnd.
  ///
  /// In en, this message translates to:
  /// **'Checks for incoming funds and confirmed transfers about every 15 minutes, even with the app closed. Needs no password.'**
  String get checksForIncomingFundsAnd;

  /// No description provided for @notificationsWereNotAllowedYou.
  ///
  /// In en, this message translates to:
  /// **'Notifications were not allowed. You can enable them in system settings.'**
  String get notificationsWereNotAllowedYou;

  /// No description provided for @never.
  ///
  /// In en, this message translates to:
  /// **'Never'**
  String get never;

  /// No description provided for @immediately.
  ///
  /// In en, this message translates to:
  /// **'Immediately'**
  String get immediately;

  /// No description provided for @secondOtherSeconds.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{After {count} second} other{After {count} seconds}}'**
  String secondOtherSeconds(int count);

  /// No description provided for @minuteOtherMinutes.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{After {count} minute} other{After {count} minutes}}'**
  String minuteOtherMinutes(int count);

  /// No description provided for @autoLockAfter.
  ///
  /// In en, this message translates to:
  /// **'Auto-lock after'**
  String get autoLockAfter;

  /// No description provided for @walletOnThisDeviceOther.
  ///
  /// In en, this message translates to:
  /// **'{name} · {count, plural, one{{count} wallet on this device} other{{count} wallets on this device}}'**
  String walletOnThisDeviceOther(String name, int count);

  /// No description provided for @activeAccount.
  ///
  /// In en, this message translates to:
  /// **'Active account'**
  String get activeAccount;

  /// No description provided for @ofLabel.
  ///
  /// In en, this message translates to:
  /// **'{name} · {index} of {count}'**
  String ofLabel(String name, int index, int count);

  /// No description provided for @followedAddress.
  ///
  /// In en, this message translates to:
  /// **'Followed address'**
  String get followedAddress;

  /// No description provided for @receiveAddress.
  ///
  /// In en, this message translates to:
  /// **'Receive address'**
  String get receiveAddress;

  /// No description provided for @noAddress.
  ///
  /// In en, this message translates to:
  /// **'No address'**
  String get noAddress;

  /// No description provided for @walletLocked.
  ///
  /// In en, this message translates to:
  /// **'Wallet locked'**
  String get walletLocked;

  /// No description provided for @thisWalletFollowsNoAddress.
  ///
  /// In en, this message translates to:
  /// **'This wallet follows no address on the active network'**
  String get thisWalletFollowsNoAddress;

  /// No description provided for @watchOnlyCannotSend.
  ///
  /// In en, this message translates to:
  /// **'Watch-only — cannot send'**
  String get watchOnlyCannotSend;

  /// No description provided for @derivedForTheActiveNetwork.
  ///
  /// In en, this message translates to:
  /// **'Derived for the active network'**
  String get derivedForTheActiveNetwork;

  /// No description provided for @allChainsWithQrCodes.
  ///
  /// In en, this message translates to:
  /// **'All chains, with QR codes'**
  String get allChainsWithQrCodes;

  /// No description provided for @wordBip39Phrase.
  ///
  /// In en, this message translates to:
  /// **'{length}-word BIP-39 phrase'**
  String wordBip39Phrase(Object length);

  /// No description provided for @changePassword.
  ///
  /// In en, this message translates to:
  /// **'Change password'**
  String get changePassword;

  /// No description provided for @savedRecipientsAndLabels.
  ///
  /// In en, this message translates to:
  /// **'Saved recipients and labels'**
  String get savedRecipientsAndLabels;

  /// No description provided for @lockWallet.
  ///
  /// In en, this message translates to:
  /// **'Lock wallet'**
  String get lockWallet;

  /// No description provided for @clearTheDecryptedSeedFrom.
  ///
  /// In en, this message translates to:
  /// **'Clear the decrypted seed from memory'**
  String get clearTheDecryptedSeedFrom;

  /// No description provided for @eraseRecoveryPhrases.
  ///
  /// In en, this message translates to:
  /// **'Erase recovery phrases'**
  String get eraseRecoveryPhrases;

  /// No description provided for @deletesEveryEncryptedSeedAnd.
  ///
  /// In en, this message translates to:
  /// **'Deletes every encrypted seed and the password; watch-only wallets stay'**
  String get deletesEveryEncryptedSeedAnd;

  /// No description provided for @defaultLabel.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get defaultLabel;

  /// No description provided for @addAccount.
  ///
  /// In en, this message translates to:
  /// **'Add account'**
  String get addAccount;

  /// No description provided for @aFreshSetOfAddresses.
  ///
  /// In en, this message translates to:
  /// **'A fresh set of addresses from the same seed'**
  String get aFreshSetOfAddresses;

  /// No description provided for @accountName.
  ///
  /// In en, this message translates to:
  /// **'Account name'**
  String get accountName;

  /// No description provided for @eGSavingsEmptyDefault.
  ///
  /// In en, this message translates to:
  /// **'e.g. Savings (empty = default)'**
  String get eGSavingsEmptyDefault;

  /// No description provided for @revealRecoveryPhrase.
  ///
  /// In en, this message translates to:
  /// **'Reveal recovery phrase?'**
  String get revealRecoveryPhrase;

  /// No description provided for @makeSureNobodyCanSee.
  ///
  /// In en, this message translates to:
  /// **'Make sure nobody can see your screen. Anyone who reads these words can take your funds.'**
  String get makeSureNobodyCanSee;

  /// No description provided for @reveal.
  ///
  /// In en, this message translates to:
  /// **'Reveal'**
  String get reveal;

  /// No description provided for @revealRecoveryPhrase2.
  ///
  /// In en, this message translates to:
  /// **'Reveal recovery phrase'**
  String get revealRecoveryPhrase2;

  /// No description provided for @wordKeepItOfflineOther.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} word · keep it offline.} other{{count} words · keep them offline.}}'**
  String wordKeepItOfflineOther(int count);

  /// No description provided for @thisWalletAlsoUsesA.
  ///
  /// In en, this message translates to:
  /// **'This wallet also uses a BIP-39 passphrase (25th word). Restoring needs both: the words alone open a different, empty wallet. The passphrase is not shown here.'**
  String get thisWalletAlsoUsesA;

  /// No description provided for @eraseEveryRecoveryPhrase.
  ///
  /// In en, this message translates to:
  /// **'Erase every recovery phrase?'**
  String get eraseEveryRecoveryPhrase;

  /// No description provided for @thisDeletesAllRecoveryPhrases.
  ///
  /// In en, this message translates to:
  /// **'This deletes all recovery phrases and the password from this device. Without the backups the funds are unrecoverable. Watch-only wallets are kept. Make sure you have your backups before continuing.'**
  String get thisDeletesAllRecoveryPhrases;

  /// No description provided for @theRecoveryPhraseIsRe.
  ///
  /// In en, this message translates to:
  /// **'The recovery phrase is re-encrypted with the new password.'**
  String get theRecoveryPhraseIsRe;

  /// No description provided for @newPasswordMinCharacters.
  ///
  /// In en, this message translates to:
  /// **'New password (min. {minLength} characters)'**
  String newPasswordMinCharacters(Object minLength);

  /// No description provided for @confirmNewPassword.
  ///
  /// In en, this message translates to:
  /// **'Confirm new password'**
  String get confirmNewPassword;

  /// No description provided for @reEncrypting.
  ///
  /// In en, this message translates to:
  /// **'Re-encrypting…'**
  String get reEncrypting;

  /// No description provided for @saveNewPassword.
  ///
  /// In en, this message translates to:
  /// **'Save new password'**
  String get saveNewPassword;

  /// No description provided for @newPasswordsDoNotMatch.
  ///
  /// In en, this message translates to:
  /// **'New passwords do not match'**
  String get newPasswordsDoNotMatch;

  /// No description provided for @couldNotChangeThePassword.
  ///
  /// In en, this message translates to:
  /// **'Could not change the password.'**
  String get couldNotChangeThePassword;

  /// No description provided for @passwordUpdatedFingerprintUnlockWas.
  ///
  /// In en, this message translates to:
  /// **'Password updated. Fingerprint unlock was turned off — enable it again in Settings.'**
  String get passwordUpdatedFingerprintUnlockWas;

  /// No description provided for @passwordUpdatedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Password updated successfully.'**
  String get passwordUpdatedSuccessfully;

  /// No description provided for @system.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get system;

  /// No description provided for @light.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get light;

  /// No description provided for @dark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get dark;

  /// No description provided for @pricesAreConvertedFromUsd.
  ///
  /// In en, this message translates to:
  /// **'Prices are converted from USD'**
  String get pricesAreConvertedFromUsd;

  /// No description provided for @version.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get version;

  /// No description provided for @selfCustodialBip39Bip.
  ///
  /// In en, this message translates to:
  /// **'Self-custodial · BIP-39 / BIP-84 / BIP-44'**
  String get selfCustodialBip39Bip;

  /// No description provided for @materialWalletBuiltWithFlutter.
  ///
  /// In en, this message translates to:
  /// **'Material Wallet {appVersion} — built with Flutter & Material 3.'**
  String materialWalletBuiltWithFlutter(Object appVersion);

  /// No description provided for @dataSources.
  ///
  /// In en, this message translates to:
  /// **'Data sources'**
  String get dataSources;

  /// No description provided for @mempoolSpaceBlockscoutCoingeckoPublicnode.
  ///
  /// In en, this message translates to:
  /// **'mempool.space · Blockscout · CoinGecko · PublicNode · dRPC · 1RPC · official chain RPCs (Base, Arbitrum, Polygon, BNB) · Solana RPC · Aptos fullnode · Aptos Labs indexer (Aptos token balances)'**
  String get mempoolSpaceBlockscoutCoingeckoPublicnode;

  /// No description provided for @materialWalletDemoBuild.
  ///
  /// In en, this message translates to:
  /// **'Material Wallet · demo build'**
  String get materialWalletDemoBuild;

  /// No description provided for @couldNotLoadYourApprovals.
  ///
  /// In en, this message translates to:
  /// **'Could not load your approvals.'**
  String get couldNotLoadYourApprovals;

  /// No description provided for @approvalsUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Approvals unavailable'**
  String get approvalsUnavailable;

  /// No description provided for @pullDownToTryAgain.
  ///
  /// In en, this message translates to:
  /// **'{error} Pull down to try again.'**
  String pullDownToTryAgain(Object error);

  /// No description provided for @noActiveApprovals.
  ///
  /// In en, this message translates to:
  /// **'No active approvals'**
  String get noActiveApprovals;

  /// No description provided for @noContractOnThisNetwork.
  ///
  /// In en, this message translates to:
  /// **'No contract on this network is allowed to spend your tokens. A scam site that asked for approval would show up here.'**
  String get noContractOnThisNetwork;

  /// No description provided for @aWatchOnlyWalletCannot.
  ///
  /// In en, this message translates to:
  /// **'A watch-only wallet cannot revoke approvals.'**
  String get aWatchOnlyWalletCannot;

  /// No description provided for @revokeApproval.
  ///
  /// In en, this message translates to:
  /// **'Revoke {symbol} approval?'**
  String revokeApproval(Object symbol);

  /// No description provided for @thisSetsTheAllowanceFor.
  ///
  /// In en, this message translates to:
  /// **'This sets the allowance for {p0} to zero, so it can no longer move your {symbol}. Contracts that need the approval will stop working until you grant it again.'**
  String thisSetsTheAllowanceFor(Object p0, Object symbol);

  /// No description provided for @keepIt.
  ///
  /// In en, this message translates to:
  /// **'Keep it'**
  String get keepIt;

  /// No description provided for @revoke.
  ///
  /// In en, this message translates to:
  /// **'Revoke'**
  String get revoke;

  /// No description provided for @revokeApproval2.
  ///
  /// In en, this message translates to:
  /// **'Revoke approval'**
  String get revokeApproval2;

  /// No description provided for @confirmRevoke.
  ///
  /// In en, this message translates to:
  /// **'Confirm revoke'**
  String get confirmRevoke;

  /// No description provided for @couldNotReachToPrice.
  ///
  /// In en, this message translates to:
  /// **'Could not reach {name} to price the revoke.'**
  String couldNotReachToPrice(Object name);

  /// No description provided for @theRevokeCouldNotBe.
  ///
  /// In en, this message translates to:
  /// **'The revoke could not be sent. Nothing changed.'**
  String get theRevokeCouldNotBe;

  /// No description provided for @revokeSubmitted.
  ///
  /// In en, this message translates to:
  /// **'Revoke submitted.'**
  String get revokeSubmitted;

  /// No description provided for @approvedFor.
  ///
  /// In en, this message translates to:
  /// **'Approved for {p0}'**
  String approvedFor(Object p0);

  /// No description provided for @unlimitedThisContractCanMove.
  ///
  /// In en, this message translates to:
  /// **'Unlimited — this contract can move all of it at any time.'**
  String get unlimitedThisContractCanMove;

  /// No description provided for @undo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get undo;

  /// No description provided for @nothingFollowedHere.
  ///
  /// In en, this message translates to:
  /// **'Nothing followed here'**
  String get nothingFollowedHere;

  /// No description provided for @thisWatchOnlyWalletHas.
  ///
  /// In en, this message translates to:
  /// **'This watch-only wallet has no address on {name}. Pick another network, or follow an address of this kind from Settings → Wallets.'**
  String thisWatchOnlyWalletHas(Object name);

  /// No description provided for @tokens.
  ///
  /// In en, this message translates to:
  /// **'Tokens'**
  String get tokens;

  /// No description provided for @approvals.
  ///
  /// In en, this message translates to:
  /// **'Approvals'**
  String get approvals;

  /// No description provided for @hideTheHidden.
  ///
  /// In en, this message translates to:
  /// **'Hide the {hiddenCount} hidden'**
  String hideTheHidden(Object hiddenCount);

  /// No description provided for @showHidden.
  ///
  /// In en, this message translates to:
  /// **'Show {hiddenCount} hidden'**
  String showHidden(Object hiddenCount);

  /// No description provided for @recentActivity.
  ///
  /// In en, this message translates to:
  /// **'Recent activity'**
  String get recentActivity;

  /// No description provided for @seeAll.
  ///
  /// In en, this message translates to:
  /// **'See all'**
  String get seeAll;

  /// No description provided for @everyNetworkInOneList.
  ///
  /// In en, this message translates to:
  /// **'Every network in one list'**
  String get everyNetworkInOneList;

  /// No description provided for @noTransactionsOnThisNetwork.
  ///
  /// In en, this message translates to:
  /// **'No transactions on this network yet. Receive some funds to see them here.'**
  String get noTransactionsOnThisNetwork;

  /// No description provided for @youCanFollowThisAddress.
  ///
  /// In en, this message translates to:
  /// **'{name} — you can follow this address, but not send from it.'**
  String youCanFollowThisAddress(String name);

  /// No description provided for @showBalance.
  ///
  /// In en, this message translates to:
  /// **'Show balance'**
  String get showBalance;

  /// No description provided for @hideBalance.
  ///
  /// In en, this message translates to:
  /// **'Hide balance'**
  String get hideBalance;

  /// No description provided for @testnetNoMarketPrice.
  ///
  /// In en, this message translates to:
  /// **'Testnet — no market price'**
  String get testnetNoMarketPrice;

  /// No description provided for @priceTemporarilyUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Price temporarily unavailable'**
  String get priceTemporarilyUnavailable;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @yourAddress2.
  ///
  /// In en, this message translates to:
  /// **'Your address · {networkLabel}'**
  String yourAddress2(Object networkLabel);

  /// No description provided for @copy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copy;

  /// No description provided for @explorer.
  ///
  /// In en, this message translates to:
  /// **'Explorer'**
  String get explorer;

  /// No description provided for @loadingOnChainData.
  ///
  /// In en, this message translates to:
  /// **'Loading on-chain data…'**
  String get loadingOnChainData;

  /// No description provided for @couldNotLoadData.
  ///
  /// In en, this message translates to:
  /// **'Could not load data'**
  String get couldNotLoadData;

  /// No description provided for @tryAgain.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get tryAgain;

  /// No description provided for @scanQrCode.
  ///
  /// In en, this message translates to:
  /// **'Scan QR code'**
  String get scanQrCode;

  /// No description provided for @toggleFlashlight.
  ///
  /// In en, this message translates to:
  /// **'Toggle flashlight'**
  String get toggleFlashlight;

  /// No description provided for @switchCamera.
  ///
  /// In en, this message translates to:
  /// **'Switch camera'**
  String get switchCamera;

  /// No description provided for @pointTheCameraAtA.
  ///
  /// In en, this message translates to:
  /// **'Point the camera at a wallet QR code'**
  String get pointTheCameraAtA;

  /// No description provided for @yourRecoveryPhrase.
  ///
  /// In en, this message translates to:
  /// **'Your recovery phrase'**
  String get yourRecoveryPhrase;

  /// No description provided for @writeTheseWordsDown.
  ///
  /// In en, this message translates to:
  /// **'Write these {length} words down'**
  String writeTheseWordsDown(Object length);

  /// No description provided for @theyAreTheOnlyWay.
  ///
  /// In en, this message translates to:
  /// **'They are the only way to restore your wallet. Store them offline — anyone who reads them can take your funds.'**
  String get theyAreTheOnlyWay;

  /// No description provided for @copyPhrase.
  ///
  /// In en, this message translates to:
  /// **'Copy phrase'**
  String get copyPhrase;

  /// No description provided for @neverShareThisPhraseMaterial.
  ///
  /// In en, this message translates to:
  /// **'Never share this phrase. Material Wallet will never ask you for it.'**
  String get neverShareThisPhraseMaterial;

  /// No description provided for @iHaveWrittenDownMy.
  ///
  /// In en, this message translates to:
  /// **'I have written down my recovery phrase'**
  String get iHaveWrittenDownMy;

  /// No description provided for @continueLabel.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueLabel;

  /// No description provided for @recoveryPhraseCopiedClearedAutomatically.
  ///
  /// In en, this message translates to:
  /// **'Recovery phrase copied — cleared automatically'**
  String get recoveryPhraseCopiedClearedAutomatically;

  /// No description provided for @importWallet.
  ///
  /// In en, this message translates to:
  /// **'Import wallet'**
  String get importWallet;

  /// No description provided for @enterYourRecoveryPhrase.
  ///
  /// In en, this message translates to:
  /// **'Enter your recovery phrase'**
  String get enterYourRecoveryPhrase;

  /// No description provided for @typeOrPasteThe12.
  ///
  /// In en, this message translates to:
  /// **'Type or paste the 12 or 24 words separated by spaces. The checksum is verified locally before anything is stored.'**
  String get typeOrPasteThe12;

  /// No description provided for @wordOneWordTwoWord.
  ///
  /// In en, this message translates to:
  /// **'word one word two word three …'**
  String get wordOneWordTwoWord;

  /// No description provided for @passphrase25thWordOptional.
  ///
  /// In en, this message translates to:
  /// **'Passphrase (25th word) — optional'**
  String get passphrase25thWordOptional;

  /// No description provided for @leaveEmptyIfYouNever.
  ///
  /// In en, this message translates to:
  /// **'leave empty if you never set one'**
  String get leaveEmptyIfYouNever;

  /// No description provided for @waitingForYourPhrase.
  ///
  /// In en, this message translates to:
  /// **'Waiting for your phrase'**
  String get waitingForYourPhrase;

  /// No description provided for @validWordPhrase.
  ///
  /// In en, this message translates to:
  /// **'Valid {wordCount}-word phrase'**
  String validWordPhrase(Object wordCount);

  /// No description provided for @wordSChecksumNotValid.
  ///
  /// In en, this message translates to:
  /// **'{wordCount} word(s) — checksum not valid yet'**
  String wordSChecksumNotValid(Object wordCount);

  /// No description provided for @ifYourPhraseWasCreated.
  ///
  /// In en, this message translates to:
  /// **'If your phrase was created with a passphrase (a 25th word), enter it below — a missing or mistyped one derives different addresses and every balance would show as zero.'**
  String get ifYourPhraseWasCreated;

  /// No description provided for @aSelfCustodialWalletYour.
  ///
  /// In en, this message translates to:
  /// **'A self-custodial wallet. Your keys never leave this device — the recovery phrase is generated here and stored locally.'**
  String get aSelfCustodialWalletYour;

  /// No description provided for @iAlreadyHaveAWallet.
  ///
  /// In en, this message translates to:
  /// **'I already have a wallet'**
  String get iAlreadyHaveAWallet;

  /// No description provided for @justWatchAnAddress.
  ///
  /// In en, this message translates to:
  /// **'Just watch an address'**
  String get justWatchAnAddress;

  /// No description provided for @verifyBackup.
  ///
  /// In en, this message translates to:
  /// **'Verify backup'**
  String get verifyBackup;

  /// No description provided for @confirmYourRecoveryPhrase.
  ///
  /// In en, this message translates to:
  /// **'Confirm your recovery phrase'**
  String get confirmYourRecoveryPhrase;

  /// No description provided for @typeTheWordsBelowExactly.
  ///
  /// In en, this message translates to:
  /// **'Type the words below exactly as they appear in your backup. The positions are chosen at random every time, so you cannot predict which ones will be asked.'**
  String get typeTheWordsBelowExactly;

  /// No description provided for @word.
  ///
  /// In en, this message translates to:
  /// **'Word #{p0}'**
  String word(Object p0);

  /// No description provided for @typeTheWord.
  ///
  /// In en, this message translates to:
  /// **'Type the word'**
  String get typeTheWord;

  /// No description provided for @aWatchOnlyWalletCannot2.
  ///
  /// In en, this message translates to:
  /// **'A watch-only wallet cannot send or replace transfers.'**
  String get aWatchOnlyWalletCannot2;

  /// No description provided for @cancelThisTransfer.
  ///
  /// In en, this message translates to:
  /// **'Cancel this transfer?'**
  String get cancelThisTransfer;

  /// No description provided for @speedThisTransferUp.
  ///
  /// In en, this message translates to:
  /// **'Speed this transfer up?'**
  String get speedThisTransferUp;

  /// No description provided for @thisSends0ToYourself.
  ///
  /// In en, this message translates to:
  /// **'This sends 0 {symbol} to yourself and reuses the pending transaction\'s nonce, so it can never confirm. It only works while the transaction is still pending.'**
  String thisSends0ToYourself(Object symbol);

  /// No description provided for @thisReSendsTheIdentical.
  ///
  /// In en, this message translates to:
  /// **'This re-sends the identical token transfer to {counterparty} with a higher fee, reusing the pending transaction\'s nonce and calldata. Exactly one of the two will confirm.'**
  String thisReSendsTheIdentical(Object counterparty);

  /// No description provided for @thisSendsToAgainWith.
  ///
  /// In en, this message translates to:
  /// **'This sends {p0} to {counterparty} again with a higher fee, reusing the pending transaction\'s nonce. Exactly one of the two will confirm.'**
  String thisSendsToAgainWith(Object p0, Object counterparty);

  /// No description provided for @cancelTransfer.
  ///
  /// In en, this message translates to:
  /// **'Cancel transfer'**
  String get cancelTransfer;

  /// No description provided for @confirmCancel.
  ///
  /// In en, this message translates to:
  /// **'Confirm cancel'**
  String get confirmCancel;

  /// No description provided for @confirmSpeedUp.
  ///
  /// In en, this message translates to:
  /// **'Confirm speed up'**
  String get confirmSpeedUp;

  /// No description provided for @couldNotReachToPrice2.
  ///
  /// In en, this message translates to:
  /// **'Could not reach {name} to price the replacement.'**
  String couldNotReachToPrice2(Object name);

  /// No description provided for @replacementSubmittedTheOriginalCan.
  ///
  /// In en, this message translates to:
  /// **'Replacement submitted — the original can no longer confirm.'**
  String get replacementSubmittedTheOriginalCan;

  /// No description provided for @fasterReplacementSubmitted.
  ///
  /// In en, this message translates to:
  /// **'Faster replacement submitted.'**
  String get fasterReplacementSubmitted;

  /// No description provided for @theReplacementCouldNotBe.
  ///
  /// In en, this message translates to:
  /// **'The replacement could not be sent. Nothing changed.'**
  String get theReplacementCouldNotBe;

  /// No description provided for @thisTransferCannotBeSped.
  ///
  /// In en, this message translates to:
  /// **'This transfer cannot be sped up.'**
  String get thisTransferCannotBeSped;

  /// No description provided for @theSamePaymentIsSent.
  ///
  /// In en, this message translates to:
  /// **'The same payment is sent again with a higher fee, paid out of your change: {p0} → {p1} ({feeRate} sat/vB). The recipient still gets the same amount; exactly one of the two transfers will confirm.'**
  String theSamePaymentIsSent(Object p0, Object p1, Object feeRate);

  /// No description provided for @send.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get send;

  /// No description provided for @thisWalletFollowsAnAddress.
  ///
  /// In en, this message translates to:
  /// **'This wallet follows an address but holds no keys, so it cannot send. Switch to a wallet with a recovery phrase in Settings → Wallets.'**
  String get thisWalletFollowsAnAddress;

  /// No description provided for @accountDataUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Account data unavailable'**
  String get accountDataUnavailable;

  /// No description provided for @theBalanceIsStillLoading.
  ///
  /// In en, this message translates to:
  /// **'The balance is still loading. Go back and try again.'**
  String get theBalanceIsStillLoading;

  /// No description provided for @send2.
  ///
  /// In en, this message translates to:
  /// **'Send {symbol}'**
  String send2(Object symbol);

  /// No description provided for @available.
  ///
  /// In en, this message translates to:
  /// **'Available'**
  String get available;

  /// No description provided for @amountIn.
  ///
  /// In en, this message translates to:
  /// **'Amount in {code}'**
  String amountIn(Object code);

  /// No description provided for @amount.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get amount;

  /// No description provided for @notEnoughOrTooLittle.
  ///
  /// In en, this message translates to:
  /// **'Not enough {symbol}, or too little {p1} for the fee'**
  String notEnoughOrTooLittle(Object symbol, Object p1);

  /// No description provided for @notEnoughFundsForAmount.
  ///
  /// In en, this message translates to:
  /// **'Not enough funds for amount + fee'**
  String get notEnoughFundsForAmount;

  /// No description provided for @enterIn.
  ///
  /// In en, this message translates to:
  /// **'Enter in {symbol}'**
  String enterIn(Object symbol);

  /// No description provided for @enterIn2.
  ///
  /// In en, this message translates to:
  /// **'Enter in {code}'**
  String enterIn2(Object code);

  /// No description provided for @max.
  ///
  /// In en, this message translates to:
  /// **'MAX'**
  String get max;

  /// No description provided for @recipientAddress.
  ///
  /// In en, this message translates to:
  /// **'Recipient address'**
  String get recipientAddress;

  /// No description provided for @base58Address.
  ///
  /// In en, this message translates to:
  /// **'Base58 address'**
  String get base58Address;

  /// No description provided for @resolvingTheName.
  ///
  /// In en, this message translates to:
  /// **'Resolving the name…'**
  String get resolvingTheName;

  /// No description provided for @scanQrCode2.
  ///
  /// In en, this message translates to:
  /// **'Scan QR code'**
  String get scanQrCode2;

  /// No description provided for @gweiTipGweiCap.
  ///
  /// In en, this message translates to:
  /// **'{p0} gwei tip · {p1} gwei cap'**
  String gweiTipGweiCap(Object p0, Object p1);

  /// No description provided for @networkFee.
  ///
  /// In en, this message translates to:
  /// **'Network fee'**
  String get networkFee;

  /// No description provided for @maxNetworkFee.
  ///
  /// In en, this message translates to:
  /// **'Max network fee'**
  String get maxNetworkFee;

  /// No description provided for @reviewTransfer.
  ///
  /// In en, this message translates to:
  /// **'Review transfer'**
  String get reviewTransfer;

  /// No description provided for @thisIsWhatGetsSigned.
  ///
  /// In en, this message translates to:
  /// **'≈ {p0} (this is what gets signed)'**
  String thisIsWhatGetsSigned(Object p0);

  /// No description provided for @thisNameUsesCharactersThe.
  ///
  /// In en, this message translates to:
  /// **'This name uses characters the wallet cannot resolve safely.'**
  String get thisNameUsesCharactersThe;

  /// No description provided for @doesNotPointToAn.
  ///
  /// In en, this message translates to:
  /// **'{name} does not point to an address.'**
  String doesNotPointToAn(Object name);

  /// No description provided for @theResolverReturnedAnInvalid.
  ///
  /// In en, this message translates to:
  /// **'The resolver returned an invalid address.'**
  String get theResolverReturnedAnInvalid;

  /// No description provided for @couldNotLookUp.
  ///
  /// In en, this message translates to:
  /// **'Could not look up {name}: {message}'**
  String couldNotLookUp(Object name, Object message);

  /// No description provided for @clipboardIsEmpty.
  ///
  /// In en, this message translates to:
  /// **'Clipboard is empty.'**
  String get clipboardIsEmpty;

  /// No description provided for @thisPaymentLinkIsNot.
  ///
  /// In en, this message translates to:
  /// **'This payment link is not supported — nothing was filled in.'**
  String get thisPaymentLinkIsNot;

  /// No description provided for @differentNetwork.
  ///
  /// In en, this message translates to:
  /// **'Different network'**
  String get differentNetwork;

  /// No description provided for @thisLinkTargetsButThe.
  ///
  /// In en, this message translates to:
  /// **'This link targets {name}, but the send screen is set to {p1}. Switch?'**
  String thisLinkTargetsButThe(Object name, Object p1);

  /// No description provided for @switchLabel.
  ///
  /// In en, this message translates to:
  /// **'Switch'**
  String get switchLabel;

  /// No description provided for @thisLinkPaysWithA.
  ///
  /// In en, this message translates to:
  /// **'This link pays with a token that is not in your {name} balance. Open the network, let it sync and scan the code again.'**
  String thisLinkPaysWithA(Object name);

  /// No description provided for @couldNotReachToPrice3.
  ///
  /// In en, this message translates to:
  /// **'Could not reach {name} to price this transfer. Nothing was sent.'**
  String couldNotReachToPrice3(Object name);

  /// No description provided for @includesTheOneTimeDeposit.
  ///
  /// In en, this message translates to:
  /// **'Includes the one-time deposit that opens the recipient\'s {symbol} account. The recipient has no account for this token yet.'**
  String includesTheOneTimeDeposit(Object symbol);

  /// No description provided for @confirmTransfer.
  ///
  /// In en, this message translates to:
  /// **'Confirm transfer'**
  String get confirmTransfer;

  /// No description provided for @theTransferFailedNothingWas.
  ///
  /// In en, this message translates to:
  /// **'The transfer failed. Nothing was sent.'**
  String get theTransferFailedNothingWas;

  /// No description provided for @hasNoTransactionHistoryIn.
  ///
  /// In en, this message translates to:
  /// **'{name} has no transaction history in this wallet. You can send, but a stuck transfer cannot be sped up or cancelled here, you will not get a confirmation notification, and the recipient is not checked against your past payments or scam lists. Double-check the address.'**
  String hasNoTransactionHistoryIn(Object name);

  /// No description provided for @saveARecipientFromThe.
  ///
  /// In en, this message translates to:
  /// **'Save a recipient from the transfer summary and it will show up here.'**
  String get saveARecipientFromThe;

  /// No description provided for @eGExchange.
  ///
  /// In en, this message translates to:
  /// **'e.g. Exchange'**
  String get eGExchange;

  /// No description provided for @estimating.
  ///
  /// In en, this message translates to:
  /// **'Estimating…'**
  String get estimating;

  /// No description provided for @total.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get total;

  /// No description provided for @transferPrepared.
  ///
  /// In en, this message translates to:
  /// **'Transfer prepared'**
  String get transferPrepared;

  /// No description provided for @validatedAgainstTheLiveBalance.
  ///
  /// In en, this message translates to:
  /// **'Validated against the live balance on {name}.'**
  String validatedAgainstTheLiveBalance(Object name);

  /// No description provided for @ensName.
  ///
  /// In en, this message translates to:
  /// **'ENS name'**
  String get ensName;

  /// No description provided for @to.
  ///
  /// In en, this message translates to:
  /// **'To'**
  String get to;

  /// No description provided for @sendingIsBlockedUntilYou.
  ///
  /// In en, this message translates to:
  /// **'Sending is blocked until you fix the recipient above.'**
  String get sendingIsBlockedUntilYou;

  /// No description provided for @sendingIsNotSupportedOn.
  ///
  /// In en, this message translates to:
  /// **'Sending is not supported on {name} yet. Restore your recovery phrase in a signing wallet to move funds.'**
  String sendingIsNotSupportedOn(Object name);

  /// No description provided for @theTransferIsSignedOn.
  ///
  /// In en, this message translates to:
  /// **'The transfer is signed on this device and sent straight to {name}. It cannot be undone.'**
  String theTransferIsSignedOn(Object name);

  /// No description provided for @send3.
  ///
  /// In en, this message translates to:
  /// **'Send {amountSymbol}'**
  String send3(Object amountSymbol);

  /// No description provided for @copyDetails.
  ///
  /// In en, this message translates to:
  /// **'Copy details'**
  String get copyDetails;

  /// No description provided for @viewRecipientOnExplorer.
  ///
  /// In en, this message translates to:
  /// **'View recipient on explorer'**
  String get viewRecipientOnExplorer;

  /// No description provided for @to2.
  ///
  /// In en, this message translates to:
  /// **'To: {recipient}'**
  String to2(Object recipient);

  /// No description provided for @amount2.
  ///
  /// In en, this message translates to:
  /// **'Amount: {p0}'**
  String amount2(Object p0);

  /// No description provided for @fee.
  ///
  /// In en, this message translates to:
  /// **'Fee: {p0}'**
  String fee(Object p0);

  /// No description provided for @transferDetailsCopied.
  ///
  /// In en, this message translates to:
  /// **'Transfer details copied'**
  String get transferDetailsCopied;

  /// No description provided for @thisAddressLooksLikeAnother.
  ///
  /// In en, this message translates to:
  /// **'This address looks like another one you use'**
  String get thisAddressLooksLikeAnother;

  /// No description provided for @itStartsAndEndsLike.
  ///
  /// In en, this message translates to:
  /// **'It starts and ends like {p0}, which you have already sent to. Scammers copy the visible ends of a real address and wait for you to send funds to it. Check the middle of the address before continuing.'**
  String itStartsAndEndsLike(Object p0);

  /// No description provided for @enterAPriorityFeeAbove.
  ///
  /// In en, this message translates to:
  /// **'Enter a priority fee above 0.'**
  String get enterAPriorityFeeAbove;

  /// No description provided for @theFeeCapMustBe.
  ///
  /// In en, this message translates to:
  /// **'The fee cap must be at least the priority fee.'**
  String get theFeeCapMustBe;

  /// No description provided for @customNetworkFee.
  ///
  /// In en, this message translates to:
  /// **'Custom network fee'**
  String get customNetworkFee;

  /// No description provided for @currentBaseFeeGwei.
  ///
  /// In en, this message translates to:
  /// **'Current base fee: {p0} gwei.'**
  String currentBaseFeeGwei(Object p0);

  /// No description provided for @priorityFeeTip.
  ///
  /// In en, this message translates to:
  /// **'Priority fee (tip)'**
  String get priorityFeeTip;

  /// No description provided for @maxFeeCap.
  ///
  /// In en, this message translates to:
  /// **'Max fee (cap)'**
  String get maxFeeCap;

  /// No description provided for @apply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get apply;

  /// No description provided for @enterAFeeRateOf.
  ///
  /// In en, this message translates to:
  /// **'Enter a fee rate of at least 1 sat/vB.'**
  String get enterAFeeRateOf;

  /// No description provided for @thatFeeRateIsUnreasonably.
  ///
  /// In en, this message translates to:
  /// **'That fee rate is unreasonably high.'**
  String get thatFeeRateIsUnreasonably;

  /// No description provided for @customFeeRate.
  ///
  /// In en, this message translates to:
  /// **'Custom fee rate'**
  String get customFeeRate;

  /// No description provided for @theTransferPaysThisMany.
  ///
  /// In en, this message translates to:
  /// **'The transfer pays this many satoshis per virtual byte. A higher rate confirms sooner.'**
  String get theTransferPaysThisMany;

  /// No description provided for @feeRate.
  ///
  /// In en, this message translates to:
  /// **'Fee rate'**
  String get feeRate;

  /// No description provided for @transfer.
  ///
  /// In en, this message translates to:
  /// **'Transfer'**
  String get transfer;

  /// No description provided for @transferConfirmed.
  ///
  /// In en, this message translates to:
  /// **'Transfer confirmed'**
  String get transferConfirmed;

  /// No description provided for @transferSent.
  ///
  /// In en, this message translates to:
  /// **'Transfer sent'**
  String get transferSent;

  /// No description provided for @theFundsLeftYourWallet.
  ///
  /// In en, this message translates to:
  /// **'The funds left your wallet and the transaction is mined.'**
  String get theFundsLeftYourWallet;

  /// No description provided for @theTransactionWasAcceptedAnd.
  ///
  /// In en, this message translates to:
  /// **'The transaction was accepted and will confirm shortly. You can follow it on the explorer.'**
  String get theTransactionWasAcceptedAnd;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @transaction.
  ///
  /// In en, this message translates to:
  /// **'Transaction'**
  String get transaction;

  /// No description provided for @copyTransactionHash.
  ///
  /// In en, this message translates to:
  /// **'Copy transaction hash'**
  String get copyTransactionHash;

  /// No description provided for @transactionHashCopied.
  ///
  /// In en, this message translates to:
  /// **'Transaction hash copied'**
  String get transactionHashCopied;

  /// No description provided for @transferSubmitted.
  ///
  /// In en, this message translates to:
  /// **'Transfer submitted'**
  String get transferSubmitted;

  /// No description provided for @sending.
  ///
  /// In en, this message translates to:
  /// **'Sending…'**
  String get sending;

  /// No description provided for @signingOnThisDevice.
  ///
  /// In en, this message translates to:
  /// **'Signing on this device…'**
  String get signingOnThisDevice;

  /// No description provided for @waitingForToConfirm.
  ///
  /// In en, this message translates to:
  /// **'Waiting for {shortTo} to confirm…'**
  String waitingForToConfirm(Object shortTo);

  /// No description provided for @confirmedOnChain.
  ///
  /// In en, this message translates to:
  /// **'Confirmed on-chain.'**
  String get confirmedOnChain;

  /// No description provided for @broadcasting.
  ///
  /// In en, this message translates to:
  /// **'Broadcasting…'**
  String get broadcasting;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @weak.
  ///
  /// In en, this message translates to:
  /// **'Weak'**
  String get weak;

  /// No description provided for @fair.
  ///
  /// In en, this message translates to:
  /// **'Fair'**
  String get fair;

  /// No description provided for @good.
  ///
  /// In en, this message translates to:
  /// **'Good'**
  String get good;

  /// No description provided for @strong.
  ///
  /// In en, this message translates to:
  /// **'Strong'**
  String get strong;

  /// No description provided for @showLabel.
  ///
  /// In en, this message translates to:
  /// **'Show'**
  String get showLabel;

  /// No description provided for @hideLabel.
  ///
  /// In en, this message translates to:
  /// **'Hide'**
  String get hideLabel;

  /// No description provided for @couldNotOpenYourWallet.
  ///
  /// In en, this message translates to:
  /// **'Could not open your wallet'**
  String get couldNotOpenYourWallet;

  /// No description provided for @theSecureStorageOnThis.
  ///
  /// In en, this message translates to:
  /// **'The secure storage on this device did not respond. Your wallet is not lost — try again.'**
  String get theSecureStorageOnThis;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @chooseLanguage.
  ///
  /// In en, this message translates to:
  /// **'Choose language'**
  String get chooseLanguage;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'uk'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'uk':
      return AppLocalizationsUk();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
