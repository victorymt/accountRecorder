import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_lock.dart';
import '../db/database_helper.dart';
import '../security/biometric_vault.dart';
import '../settings/app_settings.dart';
import '../widgets/change_master_password_dialog.dart';

class SecuritySettingsPage extends StatefulWidget {
  const SecuritySettingsPage({super.key});

  @override
  State<SecuritySettingsPage> createState() => _SecuritySettingsPageState();
}

class _SecuritySettingsPageState extends State<SecuritySettingsPage> {
  late Duration _backgroundLockDelay;
  late Duration _clipboardClearDelay;
  bool _biometricAvailable = false;
  bool _biometricEnabled = false;
  bool _biometricLoading = true;
  bool _settingsSaving = false;

  @override
  void initState() {
    super.initState();
    _backgroundLockDelay = AppSettings.instance.backgroundLockDelay;
    _clipboardClearDelay = AppSettings.instance.clipboardClearDelay;
    _loadBiometricState();
  }

  Future<void> _loadBiometricState() async {
    final states = await Future.wait([
      BiometricVault.isAvailable(),
      BiometricVault.isEnabled(),
    ]);
    if (!mounted) return;
    setState(() {
      _biometricAvailable = states[0];
      _biometricEnabled = states[1];
      _biometricLoading = false;
    });
  }

  Future<void> _changeMasterPassword() async {
    final biometricWasEnabled = _biometricEnabled;
    final changed = await ChangeMasterPasswordDialog.show(
      context,
      onChangePassword: DatabaseHelper.instance.changeMasterPassword,
    );
    if (!changed || !mounted) return;

    if (!biometricWasEnabled) {
      _showMessage('主密码已修改');
      return;
    }
    try {
      await BiometricVault.disable();
      if (await BiometricVault.isEnabled()) {
        throw StateError('Biometric binding is still enabled');
      }
      if (mounted) setState(() => _biometricEnabled = false);
    } catch (_) {
      _showMessage('主密码已修改，但旧指纹绑定移除失败');
      return;
    }
    if (!mounted) return;
    final rebind = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重新启用指纹解锁？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('稍后设置'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.fingerprint),
            label: const Text('重新启用'),
          ),
        ],
      ),
    );
    if (rebind == true) {
      await _enableBiometric();
    } else {
      _showMessage('主密码已修改，指纹解锁已关闭');
    }
  }

  Future<void> _setBiometric(bool enabled) async {
    if (_biometricLoading) return;
    if (enabled) {
      await _enableBiometric();
    } else {
      setState(() => _biometricLoading = true);
      try {
        await BiometricVault.disable();
        if (mounted) setState(() => _biometricEnabled = false);
      } catch (_) {
        _showMessage('指纹解锁关闭失败，请重试');
      } finally {
        if (mounted) setState(() => _biometricLoading = false);
      }
    }
  }

  Future<void> _enableBiometric() async {
    if (!mounted) return;
    if (!_biometricAvailable) {
      _showMessage('请先在系统设置中录入可用指纹');
      return;
    }
    final key = DatabaseHelper.instance.copyVaultKey();
    if (key == null) {
      _showMessage('密码库已锁定，请重新解锁后设置');
      return;
    }
    setState(() => _biometricLoading = true);
    AppLock.pickerActive = true;
    try {
      await BiometricVault.enable(key);
      if (mounted) {
        setState(() => _biometricEnabled = true);
        _showMessage('指纹解锁已启用');
      }
    } on PlatformException catch (error) {
      if (error.code != 'auth_canceled') {
        _showMessage('指纹解锁启用失败，请重试');
      }
    } catch (_) {
      _showMessage('指纹解锁启用失败，请重试');
    } finally {
      AppLock.pickerActive = false;
      key.fillRange(0, key.length, 0);
      if (mounted) setState(() => _biometricLoading = false);
    }
  }

  Future<void> _setBackgroundLockDelay(Duration? value) async {
    if (value == null || value == _backgroundLockDelay || _settingsSaving) {
      return;
    }
    final previous = _backgroundLockDelay;
    setState(() {
      _backgroundLockDelay = value;
      _settingsSaving = true;
    });
    try {
      await AppSettings.instance.setBackgroundLockDelay(value);
    } catch (_) {
      if (mounted) {
        setState(() => _backgroundLockDelay = previous);
        _showMessage('设置保存失败，请重试');
      }
    } finally {
      if (mounted) setState(() => _settingsSaving = false);
    }
  }

  Future<void> _setClipboardClearDelay(Duration? value) async {
    if (value == null || value == _clipboardClearDelay || _settingsSaving) {
      return;
    }
    final previous = _clipboardClearDelay;
    setState(() {
      _clipboardClearDelay = value;
      _settingsSaving = true;
    });
    try {
      await AppSettings.instance.setClipboardClearDelay(value);
    } catch (_) {
      if (mounted) {
        setState(() => _clipboardClearDelay = previous);
        _showMessage('设置保存失败，请重试');
      }
    } finally {
      if (mounted) setState(() => _settingsSaving = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('安全设置')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          const _SectionTitle('密码库'),
          ListTile(
            leading: const Icon(Icons.key_outlined),
            title: const Text('修改主密码'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _biometricLoading ? null : _changeMasterPassword,
          ),
          const Divider(height: 1, indent: 56),
          SwitchListTile(
            secondary: const Icon(Icons.fingerprint),
            title: const Text('指纹解锁'),
            value: _biometricEnabled,
            onChanged:
                _biometricLoading ||
                    (!_biometricAvailable && !_biometricEnabled)
                ? null
                : _setBiometric,
          ),
          const _SectionTitle('自动保护'),
          _DurationSettingTile(
            icon: Icons.lock_clock_outlined,
            title: '后台自动锁定',
            value: _backgroundLockDelay,
            options: AppSettings.backgroundLockOptions,
            enabled: !_settingsSaving,
            labelBuilder: AppSettings.durationLabel,
            onChanged: _setBackgroundLockDelay,
          ),
          const Divider(height: 1, indent: 56),
          _DurationSettingTile(
            icon: Icons.content_paste_off_outlined,
            title: '剪贴板自动清除',
            value: _clipboardClearDelay,
            options: AppSettings.clipboardClearOptions,
            enabled: !_settingsSaving,
            labelBuilder: AppSettings.durationLabel,
            onChanged: _setClipboardClearDelay,
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
      child: Text(
        text,
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _DurationSettingTile extends StatelessWidget {
  const _DurationSettingTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.options,
    required this.enabled,
    required this.labelBuilder,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final Duration value;
  final List<Duration> options;
  final bool enabled;
  final String Function(Duration) labelBuilder;
  final ValueChanged<Duration?> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      trailing: DropdownButton<Duration>(
        value: value,
        underline: const SizedBox.shrink(),
        onChanged: enabled ? onChanged : null,
        items: [
          for (final option in options)
            DropdownMenuItem(value: option, child: Text(labelBuilder(option))),
        ],
      ),
    );
  }
}
