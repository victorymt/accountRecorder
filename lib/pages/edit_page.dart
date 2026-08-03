import 'package:flutter/material.dart';

import '../db/database_helper.dart';

typedef AccountSaver = Future<void> Function(Account account, bool isEdit);

class EditPage extends StatefulWidget {
  const EditPage({super.key, this.account, this.accountSaver});

  final Account? account;
  final AccountSaver? accountSaver;

  @override
  State<EditPage> createState() => _EditPageState();
}

class _EditPageState extends State<EditPage> {
  final _titleController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _extraController = TextEditingController();
  final _tagsController = TextEditingController();
  bool _obscure = true;
  bool _saving = false;

  bool get _isEdit => widget.account != null;

  @override
  void initState() {
    super.initState();
    final account = widget.account;
    if (account != null) {
      _titleController.text = account.title;
      _usernameController.text = account.username;
      _passwordController.text = account.password;
      _extraController.text = account.extra;
      _tagsController.text = account.tags.join('，');
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _extraController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final title = _titleController.text.trim();
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    final extra = _extraController.text.trim();
    final tags = _tagsController.text
        .split(RegExp(r'[,，]'))
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    if (title.isEmpty) {
      _showError('请输入名称');
      return;
    }
    if (password.isEmpty) {
      _showError('请输入密码');
      return;
    }
    setState(() => _saving = true);
    final account =
        widget.account ??
        Account(title: '', username: '', password: '', extra: '');
    account
      ..title = title
      ..username = username
      ..password = password
      ..extra = extra
      ..tags = tags;
    try {
      if (widget.accountSaver case final saver?) {
        await saver(account, _isEdit);
      } else if (_isEdit) {
        await DatabaseHelper.instance.updateAccount(account);
      } else {
        await DatabaseHelper.instance.insertAccount(account);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      _showError('保存失败，请重试');
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  void _dismissKeyboard(PointerDownEvent _) {
    FocusManager.instance.primaryFocus?.unfocus();
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? '编辑账号' : '添加账号'),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
            )
          else
            IconButton(
              tooltip: '保存',
              onPressed: _save,
              icon: const Icon(Icons.save_outlined),
            ),
          const SizedBox(width: 6),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _titleController,
              autofocus: !_isEdit,
              textInputAction: TextInputAction.next,
              onTapOutside: _dismissKeyboard,
              decoration: const InputDecoration(
                labelText: '名称',
                hintText: '例如：微信 / 邮箱 / 银行',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _usernameController,
              textInputAction: TextInputAction.next,
              onTapOutside: _dismissKeyboard,
              decoration: const InputDecoration(
                labelText: '账号',
                hintText: '用户名 / 邮箱 / 手机号',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              obscureText: _obscure,
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: TextInputType.visiblePassword,
              textInputAction: TextInputAction.next,
              onTapOutside: _dismissKeyboard,
              decoration: InputDecoration(
                labelText: '密码',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscure ? Icons.visibility_off : Icons.visibility,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _extraController,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              onTapOutside: _dismissKeyboard,
              decoration: const InputDecoration(
                labelText: '备注（可选）',
                hintText: '网址、安全问题等',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _tagsController,
              textInputAction: TextInputAction.done,
              onTapOutside: _dismissKeyboard,
              onSubmitted: (_) => _save(),
              decoration: const InputDecoration(
                labelText: '标签（可选）',
                hintText: '多个标签用逗号分隔，例如：网盘，学校',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }
}
