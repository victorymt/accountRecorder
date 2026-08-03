import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_lock.dart';
import 'db/database_helper.dart';
import 'pages/unlock_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Color(0xFF00965E),
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarColor: Color(0xFFFAFAFA),
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );
  runApp(const AccountBookApp());
}

class AccountBookApp extends StatefulWidget {
  const AccountBookApp({super.key});

  @override
  State<AccountBookApp> createState() => _AccountBookAppState();
}

class _AccountBookAppState extends State<AccountBookApp>
    with WidgetsBindingObserver {
  static const _backgroundLockDelay = Duration(seconds: 30);

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
    _lockTimer = Timer(_backgroundLockDelay, () {
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
        DateTime.now().difference(backgroundedAt) >= _backgroundLockDelay &&
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
      _navigatorKey.currentState?.pushReplacement(
        MaterialPageRoute(builder: (_) => const UnlockPage()),
      );
    } finally {
      _locking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '账号本子',
      debugShowCheckedModeBanner: false,
      navigatorKey: _navigatorKey,
      theme: ThemeData(
        colorScheme:
            ColorScheme.fromSeed(
              seedColor: const Color(0xFF00965E),
              brightness: Brightness.light,
            ).copyWith(
              primary: const Color(0xFF00965E),
              secondary: const Color(0xFF00965E),
            ),
        scaffoldBackgroundColor: const Color(0xFFFAFAFA),
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
      ),
      home: UnlockPage(onLock: _lock),
    );
  }
}
