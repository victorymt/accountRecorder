import 'package:flutter/material.dart';

enum BackupPasswordMode { create, unlock }

class BackupPasswordDialog extends StatefulWidget {
  const BackupPasswordDialog({super.key, required this.mode});

  final BackupPasswordMode mode;

  static Future<String?> show(
    BuildContext context, {
    required BackupPasswordMode mode,
  }) {
    return showDialog<String>(
      context: context,
      builder: (_) => BackupPasswordDialog(mode: mode),
    );
  }

  @override
  State<BackupPasswordDialog> createState() => _BackupPasswordDialogState();
}

class _BackupPasswordDialogState extends State<BackupPasswordDialog> {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscure = true;
  String? _error;

  bool get _creating => widget.mode == BackupPasswordMode.create;

  @override
  void dispose() {
    _passwordController.clear();
    _confirmController.clear();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _submit() {
    final password = _passwordController.text;
    if (password.isEmpty) {
      setState(() => _error = '请输入备份密码');
      return;
    }
    if (_creating && password.length < 8) {
      setState(() => _error = '备份密码至少 8 位');
      return;
    }
    if (_creating && password != _confirmController.text) {
      setState(() => _error = '两次输入的密码不一致');
      return;
    }
    Navigator.of(context).pop(password);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_creating ? '设置备份密码' : '输入备份密码'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _passwordController,
            autofocus: true,
            obscureText: _obscure,
            autocorrect: false,
            enableSuggestions: false,
            keyboardType: TextInputType.visiblePassword,
            textInputAction: _creating
                ? TextInputAction.next
                : TextInputAction.done,
            decoration: InputDecoration(
              labelText: '备份密码',
              errorText: _error,
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                tooltip: _obscure ? '显示密码' : '隐藏密码',
                onPressed: () => setState(() => _obscure = !_obscure),
                icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
              ),
            ),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            onSubmitted: (_) {
              if (!_creating) _submit();
            },
          ),
          if (_creating) ...[
            const SizedBox(height: 16),
            TextField(
              controller: _confirmController,
              obscureText: _obscure,
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: TextInputType.visiblePassword,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: '确认备份密码',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              onSubmitted: (_) => _submit(),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton.icon(
          onPressed: _submit,
          icon: Icon(_creating ? Icons.enhanced_encryption : Icons.lock_open),
          label: Text(_creating ? '创建备份' : '解密'),
        ),
      ],
    );
  }
}
