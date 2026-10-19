import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'core/theme/app_theme.dart';
import 'l10n/l10n.dart';
import 'l10n/messages.dart';
import 'core/utils/feedback.dart';
import 'core/utils/units.dart';
import 'data/deep_links/payment_link.dart';
import 'data/background/background_service.dart';
import 'data/notifications/notification_service.dart';
import 'data/networks/chain_api.dart';
import 'data/networks/chain_models.dart';
import 'data/networks/price_api.dart';
import 'data/wallet/wallet_storage.dart';
import 'features/lock/lock_screen.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/send/send_screen.dart';
import 'features/shell/app_shell.dart';
import 'state/background_targets_sync.dart';
import 'state/confirmation_watcher.dart';
import 'state/contacts_controller.dart';
import 'state/hidden_tokens_controller.dart';
import 'state/notes_controller.dart';
import 'state/settings_controller.dart';
import 'state/wallet_controller.dart';
import 'state/wallet_identity_controller.dart';

/// Lets the deep-link handler navigate without a `BuildContext`.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

/// Root widget of the application.
///
/// Owns the shared application state via `provider`:
/// * [SettingsController] — theme, currency and the active network
/// * [WalletIdentityController] — the encrypted seed and derived addresses
/// * [WalletController] — live balance/history for the active network
class MaterialWalletApp extends StatelessWidget {
  const MaterialWalletApp({
    super.key,
    this.storage = const WalletStorage(),
    this.chainApi,
    this.priceApi,
  });

  /// Where the encrypted seed lives. Injectable so tests can supply an
  /// in-memory stand-in instead of a platform keystore.
  final WalletStorage storage;

  /// Network APIs, injectable for golden tests and offline demos.
  final ChainApi? chainApi;
  final PriceApi? priceApi;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsController>(
          create: (_) => SettingsController()..load(),
        ),
        ChangeNotifierProvider<NotesController>(
          create: (_) => NotesController()..load(),
        ),
        ChangeNotifierProvider<HiddenTokensController>(
          create: (_) => HiddenTokensController()..load(),
        ),
        ChangeNotifierProvider<ContactsController>(
          create: (_) => ContactsController()..load(),
        ),
        ChangeNotifierProvider<WalletIdentityController>(
          create: (_) => WalletIdentityController(storage: storage)..load(),
        ),
        ChangeNotifierProvider<WalletController>(
          create: (context) => WalletController(
            identity: context.read<WalletIdentityController>(),
            settings: context.read<SettingsController>(),
            chainApi: chainApi,
            priceApi: priceApi,
            hiddenTokens: context.read<HiddenTokensController>(),
          ),
        ),
        Provider<NotificationService>(create: (_) => NotificationService()),
        Provider<BackgroundService>(create: (_) => const BackgroundService()),
      ],
      child: const _AppView(),
    );
  }
}

class _AppView extends StatefulWidget {
  const _AppView();

  @override
  State<_AppView> createState() => _AppViewState();
}

class _AppViewState extends State<_AppView> with WidgetsBindingObserver {
  Timer? _autoLockTimer;

  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSubscription;
  ConfirmationWatcher? _watcher;
  BackgroundTargetsSync? _backgroundTargets;
  late final SettingsController _settings;
  late final BackgroundService _background;
  late bool _backgroundApplied;
  late final WalletIdentityController _identity;

  /// A link that arrived before the wallet was unlocked, deferred until it is.
  Uri? _pendingLink;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    final SettingsController settings = context.read<SettingsController>();
    final WalletController wallet = context.read<WalletController>();
    final NotificationService notifications = context.read<NotificationService>();

    _watcher = ConfirmationWatcher(
      wallet: wallet,
      settings: settings,
      notifications: notifications,
    );
    if (settings.notificationsEnabled) {
      // Re-confirm the permission granted on a previous run.
      unawaited(notifications.initialize(request: true));
    }

    _identity = context.read<WalletIdentityController>();
    _identity.addListener(_flushPendingLink);

    // The background worker has no seed: hand it the public addresses while the
    // wallet is open, and keep its schedule in step with the setting.
    _backgroundTargets = BackgroundTargetsSync(identity: _identity);
    _settings = settings;
    _background = context.read<BackgroundService>();
    _backgroundApplied = settings.backgroundChecks;
    settings.addListener(_applyBackgroundSetting);
    unawaited(_initDeepLinks());
  }

  @override
  void dispose() {
    _autoLockTimer?.cancel();
    _linkSubscription?.cancel();
    _watcher?.dispose();
    _backgroundTargets?.dispose();
    _settings.removeListener(_applyBackgroundSetting);
    _identity.removeListener(_flushPendingLink);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Starts or cancels the WorkManager job when the setting changes — including
  /// the change from "default" to the stored value when the app starts.
  void _applyBackgroundSetting() {
    final bool wanted = _settings.backgroundChecks;
    if (wanted == _backgroundApplied) {
      return;
    }
    _backgroundApplied = wanted;
    unawaited(wanted ? _background.enable() : _background.disable());
  }

  /// Reads the launch link and subscribes to links that arrive while running.
  Future<void> _initDeepLinks() async {
    try {
      final Uri? initial = await _appLinks.getInitialLink();
      if (initial != null) {
        unawaited(_handleLink(initial));
      }
      _linkSubscription = _appLinks.uriLinkStream.listen(
        (Uri uri) => unawaited(_handleLink(uri)),
        onError: (_) {},
      );
    } catch (_) {
      // No deep-link support on this platform — ignore.
    }
  }

  Future<void> _handleLink(Uri uri) async {
    final PaymentLink? link = parsePaymentLink(uri);
    if (link == null) {
      return;
    }
    if (context.read<WalletIdentityController>().status !=
        WalletStatus.unlocked) {
      _pendingLink = uri; // deliver once the wallet is open
      return;
    }
    _pendingLink = null;

    // An EIP-681 token transfer pays with a token, not with the chain's coin:
    // opening a native send here would move ETH to the token contract and the
    // merchant would never see the payment.
    if (link.isTokenTransfer) {
      final TokenBalance? token = _linkToken(link);
      if (token == null) {
        final BuildContext? ui = appNavigatorKey.currentContext;
        if (ui != null) {
          showAppSnackBar(
            ui,
            context.l10n.thisLinkPaysWithA(link.network.name),
            icon: Icons.link_off_rounded,
          );
        }
        return;
      }
      context.read<SettingsController>().setNetwork(link.network);
      appNavigatorKey.currentState?.push(
        MaterialPageRoute<void>(
          builder: (_) => SendScreen(
            token: token,
            initialRecipient: link.recipient,
            initialAmount: Units.format(
              BigInt.parse(link.uint256!),
              token.decimals,
              maxDecimals: token.decimals,
              group: false,
            ),
          ),
        ),
      );
      return;
    }

    context.read<SettingsController>().setNetwork(link.network);
    appNavigatorKey.currentState?.push(
      MaterialPageRoute<void>(
        builder: (_) => SendScreen(
          initialRecipient: link.recipient,
          initialAmount: link.amount,
        ),
      ),
    );
  }

  /// The account's holding of the link's token on that network, when the
  /// snapshot is already loaded; `null` otherwise.
  TokenBalance? _linkToken(PaymentLink link) {
    final AccountSnapshot? snapshot = context.read<WalletController>().snapshot;
    if (snapshot == null || snapshot.network.id != link.network.id) {
      return null;
    }
    final String contract = link.tokenContract!.toLowerCase();
    for (final TokenBalance token in snapshot.tokens) {
      if (token.contractAddress.toLowerCase() == contract) {
        return token;
      }
    }
    return null;
  }

  void _flushPendingLink() {
    final Uri? pending = _pendingLink;
    if (pending != null &&
        context.read<WalletIdentityController>().status ==
            WalletStatus.unlocked) {
      unawaited(_handleLink(pending));
    }
  }

  /// Locks the wallet once the app has been in the background for the delay
  /// chosen in Settings.
  ///
  /// `paused` / `hidden` mean the app is really gone from the screen (unlike
  /// the transient `inactive` on iOS, which fires for a swipe-down notification
  /// and should not lock anything).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _scheduleAutoLock();
      case AppLifecycleState.resumed:
        _autoLockTimer?.cancel();
        _autoLockTimer = null;
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  void _scheduleAutoLock() {
    _autoLockTimer?.cancel();

    final SettingsController settings = context.read<SettingsController>();
    final WalletIdentityController identity =
        context.read<WalletIdentityController>();
    if (!settings.autoLockEnabled || !identity.unlocked) {
      return;
    }

    final int seconds = settings.autoLockSeconds ?? 0;
    if (seconds <= 0) {
      identity.lock();
      return;
    }
    _autoLockTimer = Timer(Duration(seconds: seconds), identity.lock);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeMode themeMode =
        context.select<SettingsController, ThemeMode>((s) => s.themeMode);
    final Locale? locale =
        context.select<SettingsController, Locale?>((s) => s.locale);

    // Colors come from the system (Material You, Android 12+) where it
    // provides them; elsewhere the brand seed is used.
    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        return MaterialApp(
          title: 'Material Wallet',
          debugShowCheckedModeBanner: false,
          navigatorKey: appNavigatorKey,
          themeMode: themeMode,
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: SettingsController.supportedLocales,
          theme: AppTheme.light(lightDynamic),
          darkTheme: AppTheme.dark(darkDynamic),
          home: const RootGate(),
        );
      },
    );
  }
}

/// Routes between onboarding, the lock screen and the main app shell depending
/// on the state of the on-device wallet.
class RootGate extends StatelessWidget {
  const RootGate({super.key});

  @override
  Widget build(BuildContext context) {
    final WalletIdentityController identity =
        context.watch<WalletIdentityController>();
    // Messages made outside widgets (errors, labels, dates) follow the language
    // in effect here; this build reruns when the language changes.
    final String language = Localizations.localeOf(context).languageCode;
    Messages.language = language;
    Intl.defaultLocale = language;

    return switch (identity.status) {
      WalletStatus.loading => const _SplashScreen(),
      WalletStatus.failed => const _LoadFailedScreen(),
      WalletStatus.empty => const OnboardingScreen(),
      WalletStatus.locked => const LockScreen(),
      WalletStatus.unlocked => const AppShell(),
    };
  }
}

/// Shown when the vault could not be read at start.
///
/// Onboarding is deliberately not shown here: if the keystore only failed
/// temporarily, letting the user "create a new wallet" would overwrite the
/// existing one.
class _LoadFailedScreen extends StatelessWidget {
  const _LoadFailedScreen();

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.error_outline_rounded, size: 44, color: scheme.error),
              const SizedBox(height: 16),
              Text(
                context.l10n.couldNotOpenYourWallet,
                textAlign: TextAlign.center,
                style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                context.l10n.theSecureStorageOnThis,
                textAlign: TextAlign.center,
                style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 22),
              FilledButton.icon(
                onPressed: () =>
                    context.read<WalletIdentityController>().load(),
                icon: const Icon(Icons.refresh_rounded),
                label: Text(context.l10n.tryAgain),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[scheme.primary, scheme.tertiary],
                ),
              ),
              child: const Icon(
                Icons.account_balance_wallet_rounded,
                color: Colors.white,
                size: 38,
              ),
            ),
            const SizedBox(height: 28),
            const SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          ],
        ),
      ),
    );
  }
}
