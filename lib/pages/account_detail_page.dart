import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../db/database_helper.dart';
import '../security/sensitive_clipboard.dart';
import '../settings/app_settings.dart';
import '../totp/totp_service.dart';
import 'edit_page.dart';

typedef AccountPasswordCopier =
    Future<void> Function(String value, Duration clearAfter);

class AccountDetailPage extends StatefulWidget {
  const AccountDetailPage({
    super.key,
    required this.account,
    this.passwordCopier,
    this.totpCopier,
  });

  final Account account;
  final AccountPasswordCopier? passwordCopier;
  final AccountPasswordCopier? totpCopier;

  @override
  State<AccountDetailPage> createState() => _AccountDetailPageState();
}

class _AccountDetailPageState extends State<AccountDetailPage> {
  Timer? _totpTimer;
  DateTime _now = DateTime.now();
  bool _showPassword = false;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    if (widget.account.totp != null) {
      _totpTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _now = DateTime.now());
      });
    }
  }

  @override
  void dispose() {
    _totpTimer?.cancel();
    super.dispose();
  }

  Future<void> _copyUsername() async {
    if (widget.account.username.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: widget.account.username));
    _showMessage('账号已复制');
  }

  Future<void> _copyPassword() async {
    final clearAfter = AppSettings.instance.clipboardClearDelay;
    final copier = widget.passwordCopier;
    if (copier == null) {
      await SensitiveClipboard.copy(
        widget.account.password,
        clearAfter: clearAfter,
      );
    } else {
      await copier(widget.account.password, clearAfter);
    }
    _showMessage('密码已复制，${AppSettings.durationLabel(clearAfter)}后自动清除');
  }

  Future<void> _copyTotpCode() async {
    final totp = widget.account.totp;
    if (totp == null) return;
    final code = totp.codeAt(DateTime.now());
    final clearAfter = AppSettings.instance.clipboardClearDelay;
    final copier = widget.totpCopier;
    if (copier == null) {
      await SensitiveClipboard.copy(code, clearAfter: clearAfter);
    } else {
      await copier(code, clearAfter);
    }
    _showMessage('验证码已复制，${AppSettings.durationLabel(clearAfter)}后自动清除');
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _edit() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => EditPage(account: widget.account)),
    );
    if (changed == true && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('移至回收站？'),
        content: Text('「${widget.account.title}」可在 30 天内恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('移至回收站'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deleting = true);
    final id = widget.account.id;
    final deleted = id == null
        ? 0
        : await DatabaseHelper.instance.deleteAccount(id);
    if (!mounted) return;
    if (deleted > 0) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _deleting = false);
      _showMessage('操作失败，请重试');
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = widget.account;
    return Scaffold(
      appBar: AppBar(
        title: const Text('账号详情'),
        actions: [
          IconButton(
            tooltip: '编辑账号',
            onPressed: _deleting ? null : _edit,
            icon: const Icon(Icons.edit_outlined),
          ),
          PopupMenuButton<String>(
            tooltip: '更多操作',
            enabled: !_deleting,
            onSelected: (value) {
              if (value == 'delete') _delete();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'delete',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.delete_outline),
                  title: Text('删除账号'),
                ),
              ),
            ],
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
        children: [
          Text(
            account.title,
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w600),
          ),
          if (account.tags.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final tag in account.tags)
                  Chip(label: Text(tag), visualDensity: VisualDensity.compact),
              ],
            ),
          ],
          const SizedBox(height: 28),
          _DetailField(
            label: '账号',
            value: account.username.isEmpty ? '未填写' : account.username,
            muted: account.username.isEmpty,
            trailing: account.username.isEmpty
                ? null
                : IconButton(
                    tooltip: '复制账号',
                    onPressed: _copyUsername,
                    icon: const Icon(Icons.copy_outlined),
                  ),
          ),
          if (account.password.isNotEmpty) ...[
            const Divider(height: 1),
            _DetailField(
              label: '密码',
              value: _showPassword ? account.password : '************',
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: _showPassword ? '隐藏密码' : '显示密码',
                    onPressed: () =>
                        setState(() => _showPassword = !_showPassword),
                    icon: Icon(
                      _showPassword ? Icons.visibility_off : Icons.visibility,
                    ),
                  ),
                  IconButton(
                    tooltip: '复制密码',
                    onPressed: _copyPassword,
                    icon: const Icon(Icons.copy_outlined),
                  ),
                ],
              ),
            ),
          ],
          if (account.totp case final totp?) ...[
            const Divider(height: 1),
            _TotpDetailField(config: totp, now: _now, onCopy: _copyTotpCode),
          ],
          if (account.extra.isNotEmpty) ...[
            const Divider(height: 1),
            _DetailField(label: '备注', value: account.extra),
          ],
        ],
      ),
    );
  }
}

class _TotpDetailField extends StatelessWidget {
  const _TotpDetailField({
    required this.config,
    required this.now,
    required this.onCopy,
  });

  final TotpConfig config;
  final DateTime now;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final remaining = config.remainingSeconds(now);
    final code = formatTotpCode(config.codeAt(now));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 58,
            child: Text(
              '验证码',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  code,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 25,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  [
                    if (config.displayName.isNotEmpty) config.displayName,
                    '$remaining 秒',
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 7),
                LinearProgressIndicator(
                  value: remaining / config.period,
                  minHeight: 3,
                  borderRadius: BorderRadius.circular(2),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '复制验证码',
            onPressed: onCopy,
            icon: const Icon(Icons.copy_outlined),
          ),
        ],
      ),
    );
  }
}

class _DetailField extends StatelessWidget {
  const _DetailField({
    required this.label,
    required this.value,
    this.trailing,
    this.muted = false,
  });

  final String label;
  final String value;
  final Widget? trailing;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 58,
            child: Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: TextStyle(
                color: muted
                    ? Theme.of(context).colorScheme.onSurfaceVariant
                    : Theme.of(context).colorScheme.onSurface,
                fontSize: 17,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
