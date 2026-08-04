import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_lock.dart';
import 'db/database_helper.dart';
import 'pages/unlock_page.dart';
import 'settings/app_settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppSettings.instance.load();
  runApp(const AccountBookApp());
}

TextScaler composeTextScaler(TextScaler systemScaler, double userScaleFactor) {
  if (userScaleFactor == 1) return systemScaler;
  return _MultipliedTextScaler(systemScaler, userScaleFactor);
}

SystemUiOverlayStyle systemOverlayStyleFor(ThemeData theme) {
  final isDark = theme.brightness == Brightness.dark;
  return SystemUiOverlayStyle(
    statusBarColor: const Color(0xFF00965E),
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: theme.scaffoldBackgroundColor,
    systemNavigationBarDividerColor: theme.dividerColor,
    systemNavigationBarIconBrightness: isDark
        ? Brightness.light
        : Brightness.dark,
  );
}

final class _MultipliedTextScaler extends TextScaler {
  const _MultipliedTextScaler(this.systemScaler, this.userScaleFactor)
    : assert(userScaleFactor > 0);

  final TextScaler systemScaler;
  final double userScaleFactor;

  @override
  double scale(double fontSize) {
    return systemScaler.scale(fontSize) * userScaleFactor;
  }

  @override
  double get textScaleFactor => scale(14) / 14;

  @override
  bool operator ==(Object other) {
    return other is _MultipliedTextScaler &&
        other.systemScaler == systemScaler &&
        other.userScaleFactor == userScaleFactor;
  }

  @override
  int get hashCode => Object.hash(systemScaler, userScaleFactor);
}

class AccountBookApp extends StatefulWidget {
  const AccountBookApp({super.key});

  @override
  State<AccountBookApp> createState() => _AccountBookAppState();
}

class _AccountBookAppState extends State<AccountBookApp>
    with WidgetsBindingObserver {
  final _navigatorKey = GlobalKey<NavigatorState>();
  Timer? _lockTimer;
  DateTime? _backgroundedAt;
  bool _locking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _lockTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _handleResume();
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _scheduleBackgroundLock();
        break;
      case AppLifecycleState.detached:
        _lock();
        break;
      case AppLifecycleState.inactive:
        break;
    }
  }

  void _scheduleBackgroundLock() {
    if (_locking || AppLock.pickerActive || _backgroundedAt != null) return;
    _backgroundedAt = DateTime.now();
    _lockTimer?.cancel();
    _lockTimer = Timer(AppSettings.instance.backgroundLockDelay, () {
      if (_backgroundedAt != null && !AppLock.pickerActive) {
        _lock();
      }
    });
  }

  void _handleResume() {
    final backgroundedAt = _backgroundedAt;
    _lockTimer?.cancel();
    _lockTimer = null;
    _backgroundedAt = null;
    if (backgroundedAt != null &&
        DateTime.now().difference(backgroundedAt) >=
            AppSettings.instance.backgroundLockDelay &&
        !AppLock.pickerActive) {
      _lock();
    }
  }

  Future<void> _lock() async {
    if (_locking || AppLock.pickerActive) return;
    _lockTimer?.cancel();
    _lockTimer = null;
    _backgroundedAt = null;
    _locking = true;
    try {
      await DatabaseHelper.instance.close();
      if (!mounted) return;
      _navigatorKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => UnlockPage(onLock: _lock)),
        (_) => false,
      );
    } finally {
      _locking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppSettings.instance,
      builder: (context, _) {
        final settings = AppSettings.instance;
        return MaterialApp(
          title: '账号本子',
          debugShowCheckedModeBanner: false,
          navigatorKey: _navigatorKey,
          theme: _buildTheme(Brightness.light, settings.fontFamily),
          darkTheme: _buildTheme(Brightness.dark, settings.fontFamily),
          themeMode: switch (settings.themeMode) {
            AppThemeMode.system => ThemeMode.system,
            AppThemeMode.light => ThemeMode.light,
            AppThemeMode.dark => ThemeMode.dark,
          },
          builder: (context, child) {
            final mediaQuery = MediaQuery.of(context);
            return AnnotatedRegion<SystemUiOverlayStyle>(
              value: systemOverlayStyleFor(Theme.of(context)),
              child: MediaQuery(
                data: mediaQuery.copyWith(
                  textScaler: composeTextScaler(
                    mediaQuery.textScaler,
                    settings.textScaleFactor,
                  ),
                ),
                child: child ?? const SizedBox.shrink(),
              ),
            );
          },
          home: UnlockPage(onLock: _lock),
        );
      },
    );
  }

  ThemeData _buildTheme(Brightness brightness, String? fontFamily) {
    final primary = brightness == Brightness.light
        ? const Color(0xFF00965E)
        : const Color(0xFF55D9A3);
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF00965E),
      brightness: brightness,
    ).copyWith(primary: primary, secondary: primary);
    return ThemeData(
      colorScheme: colorScheme,
      fontFamily: fontFamily,
      scaffoldBackgroundColor: brightness == Brightness.light
          ? const Color(0xFFFAFAFA)
          : colorScheme.surface,
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF00965E),
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Color(0xFF00965E),
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
      useMaterial3: true,
    );
  }
}
