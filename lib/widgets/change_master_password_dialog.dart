import 'package:flutter/material.dart';

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

class _ChangeMasterPasswordDialogState
    extends State<ChangeMasterPasswordDialog> {
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscure = true;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _currentController.clear();
    _newController.clear();
    _confirmController.clear();
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return;
    final currentPassword = _currentController.text;
    final newPassword = _newController.text;
    if (currentPassword.isEmpty) {
      setState(() => _error = '请输入当前主密码');
      return;
    }
    if (newPassword.length < 8) {
      setState(() => _error = '新主密码至少 8 位');
      return;
    }
    if (newPassword == currentPassword) {
      setState(() => _error = '新主密码不能与当前密码相同');
      return;
    }
    if (newPassword != _confirmController.text) {
      setState(() => _error = '两次输入的新主密码不一致');
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
        });
        return;
      }
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '主密码修改失败，请重试';
      });
    }
  }

  void _clearError(String _) {
    if (_error != null) setState(() => _error = null);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('修改主密码'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _currentController,
              autofocus: true,
              enabled: !_saving,
              obscureText: _obscure,
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: TextInputType.visiblePassword,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: '当前主密码',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: _obscure ? '显示密码' : '隐藏密码',
                  onPressed: _saving
                      ? null
                      : () => setState(() => _obscure = !_obscure),
                  icon: Icon(
                    _obscure ? Icons.visibility_off : Icons.visibility,
                  ),
                ),
              ),
              onChanged: _clearError,
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _newController,
              enabled: !_saving,
              obscureText: _obscure,
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: TextInputType.visiblePassword,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: '新主密码',
                border: OutlineInputBorder(),
              ),
              onChanged: _clearError,
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _confirmController,
              enabled: !_saving,
              obscureText: _obscure,
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: TextInputType.visiblePassword,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: '确认新主密码',
                border: OutlineInputBorder(),
              ),
              onChanged: _clearError,
              onSubmitted: (_) => _submit(),
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
        FilledButton.icon(
          onPressed: _saving ? null : _submit,
          icon: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.key),
          label: Text(_saving ? '正在修改…' : '修改'),
        ),
      ],
    );
  }
}
