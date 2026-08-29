import 'package:flutter/material.dart';

import '../db/database_helper.dart';

typedef TrashAccountLoader = Future<List<Account>> Function();
typedef TrashAccountOperation = Future<int> Function(int id);
typedef TrashClearer = Future<int> Function();

class TrashPage extends StatefulWidget {
  const TrashPage({
    super.key,
    this.accountLoader,
    this.accountRestorer,
    this.accountDeleter,
    this.trashClearer,
    this.now,
  });

  final TrashAccountLoader? accountLoader;
  final TrashAccountOperation? accountRestorer;
  final TrashAccountOperation? accountDeleter;
  final TrashClearer? trashClearer;
  final DateTime? now;

  @override
  State<TrashPage> createState() => _TrashPageState();
}

class _TrashPageState extends State<TrashPage> {
  List<Account> _accounts = const [];
  final Set<int> _busyAccounts = {};
  bool _loading = true;
  bool _clearing = false;
  bool _loadFailed = false;
  bool _changed = false;

  TrashAccountLoader get _loadAccounts =>
      widget.accountLoader ?? DatabaseHelper.instance.listDeletedAccounts;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _loadFailed = false;
      });
    }
    try {
      final accounts = await _loadAccounts();
      if (!mounted) return;
      setState(() {
        _accounts = accounts;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  Future<void> _restore(Account account) async {
    final id = account.id;
    if (id == null || _busyAccounts.contains(id)) return;
    setState(() => _busyAccounts.add(id));
    try {
      final restore =
          widget.accountRestorer ??
          DatabaseHelper.instance.restoreDeletedAccount;
      final count = await restore(id);
      if (!mounted) return;
      if (count > 0) {
        setState(() {
          _accounts.removeWhere((item) => item.id == id);
          _changed = true;
        });
        _showMessage('账号已恢复');
      } else {
        _showMessage('恢复失败，请重试');
      }
    } catch (_) {
      _showMessage('恢复失败，请重试');
    } finally {
      if (mounted) setState(() => _busyAccounts.remove(id));
    }
  }

  Future<void> _deletePermanently(Account account) async {
    final id = account.id;
    if (id == null || _busyAccounts.contains(id)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('永久删除账号？'),
        content: Text('「${account.title}」将无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('永久删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busyAccounts.add(id));
    try {
      final delete =
          widget.accountDeleter ??
          DatabaseHelper.instance.deleteAccountPermanently;
      final count = await delete(id);
      if (!mounted) return;
      if (count > 0) {
        setState(() {
          _accounts.removeWhere((item) => item.id == id);
          _changed = true;
        });
        _showMessage('账号已永久删除');
      } else {
        _showMessage('删除失败，请重试');
      }
    } catch (_) {
      _showMessage('删除失败，请重试');
    } finally {
      if (mounted) setState(() => _busyAccounts.remove(id));
    }
  }

  Future<void> _clearTrash() async {
    if (_accounts.isEmpty || _clearing) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空回收站？'),
        content: Text('${_accounts.length} 个账号将被永久删除且无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _clearing = true);
    try {
      final clear = widget.trashClearer ?? DatabaseHelper.instance.clearTrash;
      final count = await clear();
      if (!mounted) return;
      if (count > 0) {
        setState(() {
          _accounts = const [];
          _changed = true;
        });
        _showMessage('回收站已清空');
      } else {
        _showMessage('清空失败，请重试');
      }
    } catch (_) {
      _showMessage('清空失败，请重试');
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  String _retentionLabel(Account account) {
    final deletedAt = account.deletedAt;
    if (deletedAt == null) return '';
    final nowMs = (widget.now ?? DateTime.now()).millisecondsSinceEpoch;
    final expiresAt = deletedAt + DatabaseHelper.trashRetention.inMilliseconds;
    final remainingMs = expiresAt - nowMs;
    if (remainingMs <= 0) return '即将永久删除';
    final dayMs = const Duration(days: 1).inMilliseconds;
    final days = (remainingMs + dayMs - 1) ~/ dayMs;
    return '还剩 $days 天';
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<bool>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && mounted) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('回收站'),
          actions: [
            if (_accounts.isNotEmpty)
              IconButton(
                tooltip: '清空回收站',
                onPressed: _clearing ? null : _clearTrash,
                icon: const Icon(Icons.delete_sweep_outlined),
              ),
            const SizedBox(width: 6),
          ],
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_loadFailed) {
      return Center(
        child: FilledButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.refresh),
          label: const Text('重新加载'),
        ),
      );
    }
    if (_accounts.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.delete_outline, size: 44, color: Colors.grey),
            SizedBox(height: 12),
            Text('回收站为空'),
          ],
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _accounts.length,
      separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
      itemBuilder: (context, index) {
        final account = _accounts[index];
        final id = account.id;
        final busy = _clearing || (id != null && _busyAccounts.contains(id));
        final details = [
          if (account.username.isNotEmpty) account.username,
          _retentionLabel(account),
        ];
        return ListTile(
          leading: const Icon(Icons.delete_outline),
          title: Text(account.title),
          subtitle: Text(details.join(' · ')),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: '恢复账号',
                onPressed: busy ? null : () => _restore(account),
                icon: const Icon(Icons.restore_from_trash_outlined),
              ),
              IconButton(
                tooltip: '永久删除',
                onPressed: busy ? null : () => _deletePermanently(account),
                icon: const Icon(Icons.delete_forever_outlined),
              ),
            ],
          ),
        );
      },
    );
  }
}
