import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../db/database_helper.dart';
import '../security/password_audit.dart';
import 'edit_page.dart';

typedef AuditAccountEditor =
    Future<bool?> Function(BuildContext context, Account account);
typedef PasswordAuditAnalyzer =
    Future<PasswordAuditResult> Function(PasswordAuditRequest request);

class SecurityAuditPage extends StatefulWidget {
  const SecurityAuditPage({
    super.key,
    required this.accounts,
    this.accountEditor,
    this.auditAnalyzer,
    this.now,
  });

  final List<Account> accounts;
  final AuditAccountEditor? accountEditor;
  final PasswordAuditAnalyzer? auditAnalyzer;
  final DateTime? now;

  @override
  State<SecurityAuditPage> createState() => _SecurityAuditPageState();
}

class _SecurityAuditPageState extends State<SecurityAuditPage> {
  late Future<PasswordAuditResult> _audit;

  @override
  void initState() {
    super.initState();
    _audit = _analyze();
  }

  Future<PasswordAuditResult> _analyze() {
    final request = PasswordAuditRequest(
      entries: [
        for (final account in widget.accounts)
          PasswordAuditEntry(
            title: account.title,
            username: account.username,
            password: account.password,
            hasTotp: account.totp != null,
            updatedAt: account.updatedAt,
          ),
      ],
      nowMs: (widget.now ?? DateTime.now()).millisecondsSinceEpoch,
    );
    final analyzer = widget.auditAnalyzer;
    return analyzer == null
        ? compute(analyzePasswordAudit, request)
        : analyzer(request);
  }

  void _reanalyze() {
    setState(() => _audit = _analyze());
  }

  Future<void> _editAccount(int index) async {
    final account = widget.accounts[index];
    final editor = widget.accountEditor;
    final changed = editor != null
        ? await editor(context, account)
        : await Navigator.of(context).push<bool>(
            MaterialPageRoute(builder: (_) => EditPage(account: account)),
          );
    if (changed == true && mounted) _reanalyze();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('安全检查'),
        actions: [
          IconButton(
            tooltip: '重新检查',
            onPressed: _reanalyze,
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: FutureBuilder<PasswordAuditResult>(
        future: _audit,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return _AuditError(onRetry: _reanalyze);
          }
          return _buildResult(context, snapshot.data!);
        },
      ),
    );
  }

  Widget _buildResult(BuildContext context, PasswordAuditResult result) {
    final attentionColor = result.attentionCount == 0
        ? const Color(0xFF2E7D32)
        : const Color(0xFFC62828);
    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        Container(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
          child: Row(
            children: [
              Icon(
                result.attentionCount == 0
                    ? Icons.verified_user_outlined
                    : Icons.gpp_maybe_outlined,
                size: 36,
                color: attentionColor,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      result.attentionCount == 0
                          ? '未发现明显的密码风险'
                          : '${result.attentionCount} 个账号需要处理',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text('已检查 ${result.totalAccounts} 个账号'),
                  ],
                ),
              ),
            ],
          ),
        ),
        const _SectionLabel('优先处理'),
        _AuditSection(
          icon: Icons.no_encryption_gmailerrorred_outlined,
          title: '缺少登录凭据',
          color: const Color(0xFFC62828),
          accountIndexes: result.unprotectedAccounts,
          accounts: widget.accounts,
          onAccountTap: _editAccount,
        ),
        const Divider(height: 1, indent: 56),
        _AuditSection(
          icon: Icons.copy_all_outlined,
          title: '重复使用的密码',
          color: const Color(0xFFC62828),
          accountIndexes: result.reusedAccounts,
          accounts: widget.accounts,
          onAccountTap: _editAccount,
        ),
        const Divider(height: 1, indent: 56),
        _AuditSection(
          icon: Icons.password_outlined,
          title: '容易猜到的密码',
          color: const Color(0xFFE65100),
          accountIndexes: result.weakAccounts,
          accounts: widget.accounts,
          onAccountTap: _editAccount,
        ),
        const _SectionLabel('维护建议'),
        _AuditSection(
          icon: Icons.update_outlined,
          title: '一年以上未更新',
          color: const Color(0xFFF57F17),
          accountIndexes: result.staleAccounts,
          accounts: widget.accounts,
          onAccountTap: _editAccount,
        ),
        const Divider(height: 1, indent: 56),
        _AuditSection(
          icon: Icons.timer_outlined,
          title: '尚未配置动态验证码',
          color: const Color(0xFF1565C0),
          accountIndexes: result.withoutTotpAccounts,
          accounts: widget.accounts,
          onAccountTap: _editAccount,
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

class _AuditSection extends StatelessWidget {
  const _AuditSection({
    required this.icon,
    required this.title,
    required this.color,
    required this.accountIndexes,
    required this.accounts,
    required this.onAccountTap,
  });

  final IconData icon;
  final String title;
  final Color color;
  final List<int> accountIndexes;
  final List<Account> accounts;
  final ValueChanged<int> onAccountTap;

  @override
  Widget build(BuildContext context) {
    if (accountIndexes.isEmpty) {
      return ListTile(
        leading: const Icon(
          Icons.check_circle_outline,
          color: Color(0xFF2E7D32),
        ),
        title: Text(title),
        trailing: const Text('0'),
      );
    }

    return ExpansionTile(
      leading: Icon(icon, color: color),
      title: Text(title),
      subtitle: Text('${accountIndexes.length} 个账号'),
      children: [
        for (final index in accountIndexes)
          ListTile(
            contentPadding: const EdgeInsets.only(left: 72, right: 16),
            title: Text(accounts[index].title),
            subtitle: accounts[index].username.isEmpty
                ? null
                : Text(accounts[index].username),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => onAccountTap(index),
          ),
      ],
    );
  }
}

class _AuditError extends StatelessWidget {
  const _AuditError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 40),
          const SizedBox(height: 12),
          const Text('安全检查失败'),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('重试'),
          ),
        ],
      ),
    );
  }
}
