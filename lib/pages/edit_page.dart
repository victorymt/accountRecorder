import 'dart:async';

import 'package:flutter/material.dart';

import '../db/database_helper.dart';
import '../security/password_security.dart';
import '../totp/totp_service.dart';
import '../widgets/password_generator_sheet.dart';
import '../widgets/password_strength_indicator.dart';
import 'totp_scanner_page.dart';

typedef AccountSaver = Future<void> Function(Account account, bool isEdit);
typedef TotpQrScanner = Future<String?> Function(BuildContext context);
typedef PasswordGeneratorPicker =
    Future<String?> Function(BuildContext context);

class EditPage extends StatefulWidget {
  const EditPage({
    super.key,
    this.account,
    this.accountSaver,
    this.totpQrScanner,
    this.passwordGeneratorPicker,
  });

  final Account? account;
  final AccountSaver? accountSaver;
  final TotpQrScanner? totpQrScanner;
  final PasswordGeneratorPicker? passwordGeneratorPicker;

  @override
  State<EditPage> createState() => _EditPageState();
}

class _EditPageState extends State<EditPage> {
  final _titleController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _extraController = TextEditingController();
  final _tagsController = TextEditingController();
  final _totpInputController = TextEditingController();
  Timer? _strengthDebounce;
  bool _obscure = true;
  bool _totpObscure = true;
  bool _totpEnabled = false;
  bool _saving = false;
  TotpAlgorithm _totpAlgorithm = TotpAlgorithm.sha1;
  int _totpDigits = 6;
  int _totpPeriod = 30;
  String _totpIssuer = '';
  String _totpAccountName = '';
  PasswordStrength? _passwordStrength;

  bool get _isEdit => widget.account != null;

  void _updateTotpInput(String value) {
    if (!value.trimLeft().toLowerCase().startsWith('otpauth:')) return;
    TotpConfig config;
    try {
      config = TotpConfig.fromUri(value);
    } on FormatException {
      return;
    }
    _applyTotpConfig(config);
  }

  void _applyTotpConfig(TotpConfig config) {
    if (_titleController.text.trim().isEmpty) {
      _titleController.text = config.issuer.isEmpty
          ? config.accountName
          : config.issuer;
    }
    if (_usernameController.text.trim().isEmpty) {
      _usernameController.text = config.accountName;
    }
    setState(() {
      _totpAlgorithm = config.algorithm;
      _totpDigits = config.digits;
      _totpPeriod = config.period;
      _totpIssuer = config.issuer;
      _totpAccountName = config.accountName;
    });
  }

  Future<void> _scanTotpQrCode() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final scanner = widget.totpQrScanner;
    final value = scanner != null
        ? await scanner(context)
        : await Navigator.of(context).push<String>(
            MaterialPageRoute(builder: (_) => const TotpScannerPage()),
          );
    if (!mounted || value == null) return;

    TotpConfig config;
    try {
      config = TotpConfig.fromUri(value);
    } on FormatException {
      _showError('未识别到有效的 TOTP 二维码');
      return;
    }
    _totpInputController.text = value;
    _applyTotpConfig(config);
  }

  void _scheduleStrengthEvaluation() {
    _strengthDebounce?.cancel();
    final password = _passwordController.text;
    if (password.isEmpty) {
      if (_passwordStrength != null && mounted) {
        setState(() => _passwordStrength = null);
      }
      return;
    }
    final inputs = [_titleController.text, _usernameController.text];
    _strengthDebounce = Timer(const Duration(milliseconds: 150), () {
      if (!mounted || _passwordController.text != password) return;
      final strength = evaluatePasswordStrength(password, userInputs: inputs);
      if (_passwordStrength?.score != strength.score) {
        setState(() => _passwordStrength = strength);
      }
    });
  }

  Future<void> _openPasswordGenerator() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final picker = widget.passwordGeneratorPicker;
    final password = picker != null
        ? await picker(context)
        : await PasswordGeneratorSheet.show(context);
    if (!mounted || password == null) return;
    _passwordController.value = TextEditingValue(
      text: password,
      selection: TextSelection.collapsed(offset: password.length),
    );
    setState(() => _obscure = false);
  }

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
      final totp = account.totp;
      if (totp != null) {
        _totpEnabled = true;
        _totpInputController.text = totp.secret;
        _totpAlgorithm = totp.algorithm;
        _totpDigits = totp.digits;
        _totpPeriod = totp.period;
        _totpIssuer = totp.issuer;
        _totpAccountName = totp.accountName;
      }
    }
    _titleController.addListener(_scheduleStrengthEvaluation);
    _usernameController.addListener(_scheduleStrengthEvaluation);
    _passwordController.addListener(_scheduleStrengthEvaluation);
    _scheduleStrengthEvaluation();
  }

  @override
  void dispose() {
    _strengthDebounce?.cancel();
    _titleController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _extraController.dispose();
    _tagsController.dispose();
    _totpInputController.clear();
    _totpInputController.dispose();
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
    TotpConfig? totp;
    if (_totpEnabled) {
      try {
        totp = TotpConfig.fromInput(
          _totpInputController.text,
          issuer: _totpIssuer.isEmpty ? title : _totpIssuer,
          accountName: _totpAccountName.isEmpty
              ? (username.isEmpty ? title : username)
              : _totpAccountName,
          algorithm: _totpAlgorithm,
          digits: _totpDigits,
          period: _totpPeriod,
        );
      } on FormatException {
        _showError('动态验证码配置无效');
        return;
      }
    }
    if (password.isEmpty && totp == null) {
      _showError('请输入密码');
      return;
    }
    setState(() => _saving = true);
    final account =
        widget.account ??
        Account(title: '', username: '', password: '', extra: '');
    final previousTotp = account.totp;
    account
      ..title = title
      ..username = username
      ..password = password
      ..extra = extra
      ..tags = tags
      ..totp = totp;
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
    if (previousTotp != null && !identical(previousTotp, totp)) {
      previousTotp.wipe();
    }
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
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: '生成密码',
                      onPressed: _saving ? null : _openPasswordGenerator,
                      icon: const Icon(Icons.password_outlined),
                    ),
                    IconButton(
                      tooltip: _obscure ? '显示密码' : '隐藏密码',
                      icon: Icon(
                        _obscure ? Icons.visibility_off : Icons.visibility,
                      ),
                      onPressed: _saving
                          ? null
                          : () => setState(() => _obscure = !_obscure),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(
              height: 34,
              child: _passwordStrength == null
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: PasswordStrengthIndicator(
                        strength: _passwordStrength!,
                      ),
                    ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.timer_outlined),
              title: const Text('动态验证码（TOTP）'),
              value: _totpEnabled,
              onChanged: _saving
                  ? null
                  : (value) => setState(() => _totpEnabled = value),
            ),
            if (_totpEnabled) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _totpInputController,
                obscureText: _totpObscure,
                autocorrect: false,
                enableSuggestions: false,
                keyboardType: TextInputType.visiblePassword,
                textInputAction: TextInputAction.next,
                onTapOutside: _dismissKeyboard,
                onChanged: _updateTotpInput,
                decoration: InputDecoration(
                  labelText: 'TOTP 密钥或地址',
                  hintText: 'Base32 / otpauth://',
                  border: const OutlineInputBorder(),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: '扫描二维码',
                        onPressed: _saving ? null : _scanTotpQrCode,
                        icon: const Icon(Icons.qr_code_scanner),
                      ),
                      IconButton(
                        tooltip: _totpObscure ? '显示密钥' : '隐藏密钥',
                        onPressed: _saving
                            ? null
                            : () =>
                                  setState(() => _totpObscure = !_totpObscure),
                        icon: Icon(
                          _totpObscure
                              ? Icons.visibility_off
                              : Icons.visibility,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<TotpAlgorithm>(
                      key: ValueKey(_totpAlgorithm),
                      initialValue: _totpAlgorithm,
                      decoration: const InputDecoration(
                        labelText: '算法',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final algorithm in TotpAlgorithm.values)
                          DropdownMenuItem(
                            value: algorithm,
                            child: Text(algorithm.wireName),
                          ),
                      ],
                      onChanged: _saving
                          ? null
                          : (value) {
                              if (value != null) {
                                setState(() => _totpAlgorithm = value);
                              }
                            },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      key: ValueKey(_totpDigits),
                      initialValue: _totpDigits,
                      decoration: const InputDecoration(
                        labelText: '位数',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 6, child: Text('6 位')),
                        DropdownMenuItem(value: 8, child: Text('8 位')),
                      ],
                      onChanged: _saving
                          ? null
                          : (value) {
                              if (value != null) {
                                setState(() => _totpDigits = value);
                              }
                            },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                key: ValueKey(_totpPeriod),
                initialValue: _totpPeriod,
                decoration: const InputDecoration(
                  labelText: '刷新周期',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 15, child: Text('15 秒')),
                  DropdownMenuItem(value: 30, child: Text('30 秒')),
                  DropdownMenuItem(value: 45, child: Text('45 秒')),
                  DropdownMenuItem(value: 60, child: Text('60 秒')),
                  DropdownMenuItem(value: 90, child: Text('90 秒')),
                  DropdownMenuItem(value: 120, child: Text('120 秒')),
                ],
                onChanged: _saving
                    ? null
                    : (value) {
                        if (value != null) {
                          setState(() => _totpPeriod = value);
                        }
                      },
              ),
            ],
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
