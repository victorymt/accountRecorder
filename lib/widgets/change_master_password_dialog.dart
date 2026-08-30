import 'package:flutter/material.dart';

import 'numeric_keypad.dart';

typedef MasterPasswordChanger =
    Future<bool> Function(String currentPassword, String newPassword);

class ChangeMasterPasswordDialog extends StatefulWidget {
  const ChangeMasterPasswordDialog({super.key, required this.onChangePassword});

  final MasterPasswordChanger onChangePassword;

  static Future<bool> show(
    BuildContext context, {
    required MasterPasswordChanger onChangePassword,
  }) async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) =>
              ChangeMasterPasswordDialog(onChangePassword: onChangePassword),
        ) ??
        false;
  }

  @override
  State<ChangeMasterPasswordDialog> createState() =>
      _ChangeMasterPasswordDialogState();
}

enum _MasterPasswordStep { current, newPassword, confirmation }

class _ChangeMasterPasswordDialogState
    extends State<ChangeMasterPasswordDialog> {
  static const _pinLength = 6;

  String _currentPin = '';
  String _newPin = '';
  String _confirmationPin = '';
  _MasterPasswordStep _step = _MasterPasswordStep.current;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _clearInput();
    super.dispose();
  }

  String get _activePin => switch (_step) {
    _MasterPasswordStep.current => _currentPin,
    _MasterPasswordStep.newPassword => _newPin,
    _MasterPasswordStep.confirmation => _confirmationPin,
  };

  String get _stepLabel => switch (_step) {
    _MasterPasswordStep.current => '输入当前 6 位数字 PIN',
    _MasterPasswordStep.newPassword => '设置新的 6 位数字 PIN',
    _MasterPasswordStep.confirmation => '再次输入新的 6 位数字 PIN',
  };

  void _clearInput() {
    _currentPin = '';
    _newPin = '';
    _confirmationPin = '';
    _step = _MasterPasswordStep.current;
  }

  void _handleDigit(String digit) {
    if (_saving || _activePin.length >= _pinLength) return;
    setState(() {
      switch (_step) {
        case _MasterPasswordStep.current:
          _currentPin += digit;
        case _MasterPasswordStep.newPassword:
          _newPin += digit;
        case _MasterPasswordStep.confirmation:
          _confirmationPin += digit;
      }
      _error = null;
    });
    if (_activePin.length != _pinLength) return;
    switch (_step) {
      case _MasterPasswordStep.current:
        setState(() => _step = _MasterPasswordStep.newPassword);
      case _MasterPasswordStep.newPassword:
        setState(() => _step = _MasterPasswordStep.confirmation);
      case _MasterPasswordStep.confirmation:
        _scheduleSubmit();
    }
  }

  void _scheduleSubmit() {
    final currentPin = _currentPin;
    final newPin = _newPin;
    final confirmationPin = _confirmationPin;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _currentPin != currentPin ||
          _newPin != newPin ||
          _confirmationPin != confirmationPin) {
        return;
      }
      _submit();
    });
  }

  void _handleBackspace() {
    if (_saving) return;
    setState(() {
      switch (_step) {
        case _MasterPasswordStep.current:
          _currentPin = _removeLast(_currentPin);
        case _MasterPasswordStep.newPassword:
          if (_newPin.isNotEmpty) {
            _newPin = _removeLast(_newPin);
          } else {
            _step = _MasterPasswordStep.current;
            _currentPin = _removeLast(_currentPin);
          }
        case _MasterPasswordStep.confirmation:
          if (_confirmationPin.isNotEmpty) {
            _confirmationPin = _removeLast(_confirmationPin);
          } else {
            _step = _MasterPasswordStep.newPassword;
            _newPin = _removeLast(_newPin);
          }
      }
      _error = null;
    });
  }

  String _removeLast(String value) {
    if (value.isEmpty) return value;
    return value.substring(0, value.length - 1);
  }

  void _handleClear() {
    if (_saving) return;
    setState(() {
      _clearInput();
      _error = null;
    });
  }

  Future<void> _submit() async {
    if (_saving) return;
    final currentPassword = _currentPin;
    final newPassword = _newPin;
    final confirmation = _confirmationPin;
    if (currentPassword.length != _pinLength) {
      setState(() => _error = '当前主密码必须为 6 位数字 PIN');
      return;
    }
    if (newPassword.length != _pinLength) {
      setState(() => _error = '新主密码必须为 6 位数字 PIN');
      return;
    }
    if (newPassword == currentPassword) {
      setState(() {
        _newPin = '';
        _confirmationPin = '';
        _step = _MasterPasswordStep.newPassword;
        _error = '新主密码不能与当前密码相同';
      });
      return;
    }
    if (newPassword != confirmation) {
      setState(() {
        _error = '两次输入的新 PIN 不一致';
        _clearInput();
      });
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final changed = await widget.onChangePassword(
        currentPassword,
        newPassword,
      );
      if (!mounted) return;
      if (!changed) {
        setState(() {
          _saving = false;
          _error = '当前主密码错误';
          _clearInput();
        });
        return;
      }
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '主密码修改失败，请重试';
        _clearInput();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('修改主密码'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PinDisplay(
              label: _stepLabel,
              value: _activePin,
              length: _pinLength,
            ),
            const SizedBox(height: 18),
            NumericKeypad(
              enabled: !_saving,
              onDigit: _handleDigit,
              onBackspace: _handleBackspace,
              onClear: _handleClear,
            ),
            if (_error case final error?) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  error,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
      ],
    );
  }
}
