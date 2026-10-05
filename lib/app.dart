import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme/app_theme.dart';
import 'data/wallet/wallet_storage.dart';
import 'features/lock/lock_screen.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/shell/app_shell.dart';
import 'state/settings_controller.dart';
import 'state/wallet_controller.dart';
import 'state/wallet_identity_controller.dart';

/// Root widget of the application.
///
/// Owns the shared application state via `provider`:
/// * [SettingsController] — theme, currency and the active network
/// * [WalletIdentityController] — the encrypted seed and derived addresses
/// * [WalletController] — live balance/history for the active network
class MaterialWalletApp extends StatelessWidget {
  const MaterialWalletApp({super.key, this.storage = const WalletStorage()});

  /// Where the encrypted seed lives. Injectable so tests can supply an
  /// in-memory stand-in instead of a platform keystore.
  final WalletStorage storage;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsController>(
          create: (_) => SettingsController()..load(),
        ),
        ChangeNotifierProvider<WalletIdentityController>(
          create: (_) => WalletIdentityController(storage: storage)..load(),
        ),
        ChangeNotifierProvider<WalletController>(
          create: (context) => WalletController(
            identity: context.read<WalletIdentityController>(),
            settings: context.read<SettingsController>(),
          ),
        ),
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _autoLockTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
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

    return MaterialApp(
      title: 'Material Wallet',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      home: const RootGate(),
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

    return switch (identity.status) {
      WalletStatus.loading => const _SplashScreen(),
      WalletStatus.empty => const OnboardingScreen(),
      WalletStatus.locked => const LockScreen(),
      WalletStatus.unlocked => const AppShell(),
    };
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
