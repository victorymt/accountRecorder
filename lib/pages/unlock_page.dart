import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_lock.dart';
import '../db/database_helper.dart';
import '../security/biometric_vault.dart';
import 'home_page.dart';

class UnlockPage extends StatefulWidget {
  const UnlockPage({super.key, this.onLock});

  final VoidCallback? onLock;

  @override
  State<UnlockPage> createState() => _UnlockPageState();
}

class _UnlockPageState extends State<UnlockPage> {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  bool _biometricLoading = false;
  bool _migrating = false;
  bool _automaticBiometricStarted = false;
  bool? _biometricConfigured;
  late Future<bool> _setupFuture;
  late Future<({bool isSetup, bool biometricEnabled})> _initialStateFuture;

  @override
  void initState() {
    super.initState();
    _setupFuture = DatabaseHelper.instance.isSetup();
    _initialStateFuture = _loadInitialState();
  }

  Future<({bool isSetup, bool biometricEnabled})> _loadInitialState() async {
    final isSetup = await _setupFuture;
    final biometricEnabled = isSetup && await BiometricVault.isEnabled();
    _biometricConfigured = biometricEnabled;
    return (isSetup: isSetup, biometricEnabled: biometricEnabled);
  }

  @override
  void dispose() {
    _passwordController.clear();
    _confirmController.clear();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading || _biometricLoading) return;
    final isSetup = await _setupFuture;
    final password = _passwordController.text;
    if (password.isEmpty) {
      _showError('请输入主密码');
      return;
    }
    if (isSetup) {
      final remaining = await DatabaseHelper.instance.remainingUnlockDelay();
      if (!mounted) return;
      if (remaining > Duration.zero) {
        _showError('请等待 ${_delaySeconds(remaining)} 秒后再试');
        return;
      }
      final migrationRequired = await DatabaseHelper.instance
          .needsVaultMigration();
      if (!mounted) return;
      setState(() {
        _loading = true;
        _migrating = migrationRequired;
      });
      Uint8List? key;
      try {
        key = await DatabaseHelper.instance.unlock(password);
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _migrating = false;
        });
        _showError('数据升级失败，原数据未更改');
        return;
      }
      final failureDelay = key == null
          ? await DatabaseHelper.instance.recordUnlockFailure()
          : Duration.zero;
      if (key != null) {
        await DatabaseHelper.instance.clearUnlockFailures();
      }
      if (!mounted) return;
      if (key != null) {
        await _completePasswordUnlock(key);
      } else {
        setState(() {
          _loading = false;
          _migrating = false;
        });
        _showError(
          failureDelay > Duration.zero
              ? '主密码错误，请等待 ${_delaySeconds(failureDelay)} 秒后再试'
              : '主密码错误',
        );
      }
    } else {
      if (password.length < 6) {
        _showError('主密码至少 6 位');
        return;
      }
      if (password != _confirmController.text) {
        _showError('两次输入的密码不一致');
        return;
      }
      setState(() => _loading = true);
      Uint8List key;
      try {
        key = await DatabaseHelper.instance.setupMasterPassword(password);
      } catch (_) {
        if (!mounted) return;
        setState(() => _loading = false);
        _showError('创建密码库失败，请重试');
        return;
      }
      if (!mounted) return;
      await _completePasswordUnlock(key);
    }
  }

  Future<void> _completePasswordUnlock(Uint8List key) async {
    try {
      await _offerBiometricSetup(key);
    } finally {
      key.fillRange(0, key.length, 0);
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      _migrating = false;
    });
    _enter();
  }

  Future<void> _offerBiometricSetup(Uint8List key) async {
    if (_biometricConfigured == true || !await BiometricVault.isAvailable()) {
      return;
    }
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('启用指纹解锁？'),
        content: const Text('以后可以使用本机指纹快速解锁账号本子。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('暂不启用'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.fingerprint),
            label: const Text('启用'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    AppLock.pickerActive = true;
    try {
      await BiometricVault.enable(key);
      _biometricConfigured = true;
    } on PlatformException catch (error) {
      if (error.code != 'auth_canceled') {
        _showError('指纹解锁启用失败，请稍后重试');
      }
    } finally {
      AppLock.pickerActive = false;
    }
  }

  Future<void> _unlockWithBiometric() async {
    if (_loading || _biometricLoading || _biometricConfigured != true) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _biometricLoading = true);
    Uint8List? key;
    AppLock.pickerActive = true;
    try {
      key = await BiometricVault.unlock();
      final unlocked = await DatabaseHelper.instance.unlockWithVaultKey(key);
      if (!unlocked) {
        await BiometricVault.disable();
        _biometricConfigured = false;
        _showError('指纹密钥已失效，请使用主密码重新启用');
        return;
      }
      await DatabaseHelper.instance.clearUnlockFailures();
      if (mounted) _enter();
    } on PlatformException catch (error) {
      if (error.code == 'key_invalidated' ||
          error.code == 'decryption_failed' ||
          error.code == 'not_configured') {
        await BiometricVault.disable();
        _biometricConfigured = false;
        _showError('指纹设置已变化，请使用主密码重新启用');
      } else if (error.code != 'auth_canceled') {
        _showError(
          error.code == 'auth_locked' ? '指纹尝试次数过多，请稍后再试' : '指纹识别失败，请重试',
        );
      }
    } catch (_) {
      _showError('指纹解锁失败，请使用主密码');
    } finally {
      AppLock.pickerActive = false;
      key?.fillRange(0, key.length, 0);
      if (mounted) setState(() => _biometricLoading = false);
    }
  }

  int _delaySeconds(Duration duration) {
    return (duration.inMilliseconds / Duration.millisecondsPerSecond).ceil();
  }

  void _enter() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => HomePage(onLock: widget.onLock)),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: FutureBuilder<({bool isSetup, bool biometricEnabled})>(
          future: _initialStateFuture,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const CircularProgressIndicator();
            }
            final isSetup = snapshot.data!.isSetup;
            final biometricEnabled =
                _biometricConfigured ?? snapshot.data!.biometricEnabled;
            if (isSetup && biometricEnabled && !_automaticBiometricStarted) {
              _automaticBiometricStarted = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _unlockWithBiometric();
              });
            }
            return SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(
                      Icons.lock_outline,
                      size: 72,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      isSetup ? '账号本子' : '设置主密码',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isSetup
                          ? '请输入主密码解锁'
                          : '首次使用，请设置一个主密码\n主密码用于加密所有账号数据，请务必牢记',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _passwordController,
                      autofocus: isSetup && !biometricEnabled,
                      obscureText: _obscure,
                      autocorrect: false,
                      enableSuggestions: false,
                      keyboardType: TextInputType.visiblePassword,
                      textInputAction: isSetup
                          ? TextInputAction.done
                          : TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: '主密码',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscure ? Icons.visibility_off : Icons.visibility,
                          ),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                      onSubmitted: (_) {
                        if (!isSetup) return;
                        _submit();
                      },
                    ),
                    if (!isSetup) ...[
                      const SizedBox(height: 16),
                      TextField(
                        controller: _confirmController,
                        obscureText: _obscure,
                        autocorrect: false,
                        enableSuggestions: false,
                        keyboardType: TextInputType.visiblePassword,
                        textInputAction: TextInputAction.done,
                        decoration: const InputDecoration(
                          labelText: '确认主密码',
                          border: OutlineInputBorder(),
                        ),
                        onSubmitted: (_) => _submit(),
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _loading || _biometricLoading ? null : _submit,
                      child: _loading
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  _migrating
                                      ? '正在升级…'
                                      : isSetup
                                      ? '正在解锁…'
                                      : '正在生成密钥…',
                                ),
                              ],
                            )
                          : Text(isSetup ? '解锁' : '创建'),
                    ),
                    if (isSetup && biometricEnabled) ...[
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _loading || _biometricLoading
                            ? null
                            : _unlockWithBiometric,
                        icon: _biometricLoading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.fingerprint),
                        label: Text(_biometricLoading ? '正在验证…' : '使用指纹解锁'),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
