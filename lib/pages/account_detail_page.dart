import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../db/database_helper.dart';
import '../security/sensitive_clipboard.dart';
import 'edit_page.dart';

class AccountDetailPage extends StatefulWidget {
  const AccountDetailPage({super.key, required this.account});

  final Account account;

  @override
  State<AccountDetailPage> createState() => _AccountDetailPageState();
}

class _AccountDetailPageState extends State<AccountDetailPage> {
  bool _showPassword = false;
  bool _deleting = false;

  Future<void> _copyUsername() async {
    if (widget.account.username.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: widget.account.username));
    _showMessage('账号已复制');
  }

  Future<void> _copyPassword() async {
    await SensitiveClipboard.copy(widget.account.password);
    _showMessage('密码已复制，30 秒后自动清除');
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
        title: const Text('删除账号'),
        content: Text('确定删除「${widget.account.title}」吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
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
      _showMessage('删除失败，请重试');
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
          if (account.extra.isNotEmpty) ...[
            const Divider(height: 1),
            _DetailField(label: '备注', value: account.extra),
          ],
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
              style: const TextStyle(color: Color(0xFF777777), fontSize: 14),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: TextStyle(
                color: muted
                    ? const Color(0xFF999999)
                    : const Color(0xFF222222),
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
