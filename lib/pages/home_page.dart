import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart' show SystemUiOverlayStyle;

import '../app_lock.dart';
import '../backup/encrypted_vault_backup.dart';
import '../db/database_helper.dart';
import '../import/accountbox_importer.dart';
import '../security/sensitive_clipboard.dart';
import '../settings/app_settings.dart';
import '../totp/totp_service.dart';
import '../widgets/backup_password_dialog.dart';
import 'account_detail_page.dart';
import 'edit_page.dart';
import 'security_settings_page.dart';

typedef AccountLoader =
    Future<List<Account>> Function(String query, {String? tag});

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.onLock, this.accountLoader});

  final VoidCallback? onLock;
  final AccountLoader? accountLoader;

  @override
  State<HomePage> createState() => _HomePageState();
}

enum _HomeAction { import, exportBackup, restoreBackup, security, lock }

enum _AccountAction { copyPassword, copyTotp, edit, delete }

class _HomePageState extends State<HomePage> {
  static const _brandGreen = Color(0xFF00965E);
  static const _allAccounts = '';
  static const _dynamicPasswords = '__dynamic_passwords__';
  static const _favorites = '__favorites__';
  static const _permanentCategories = [
    (_dynamicPasswords, '动态密码'),
    (_allAccounts, '全部账号'),
    (_favorites, '我的收藏'),
  ];
  static const _alphabet = <String>[
    '☆',
    'A',
    'B',
    'C',
    'D',
    'E',
    'F',
    'G',
    'H',
    'I',
    'J',
    'K',
    'L',
    'M',
    'N',
    'O',
    'P',
    'Q',
    'R',
    'S',
    'T',
    'U',
    'V',
    'W',
    'X',
    'Y',
    'Z',
    '#',
  ];

  final _searchController = TextEditingController();
  final _accountScrollController = ScrollController();
  final _totpClock = ValueNotifier<DateTime>(DateTime.now());
  Timer? _searchDebounce;
  Timer? _totpTimer;
  String _query = '';
  String _selectedCategory = _allAccounts;
  List<String> _allTags = const [];
  List<Account> _allAccountsData = const [];
  List<Account> _accounts = const [];
  bool _loading = true;
  bool _searching = false;
  String? _loadError;
  int _reloadSeq = 0;

  AccountLoader get _loadAccounts =>
      widget.accountLoader ?? DatabaseHelper.instance.listAccounts;

  @override
  void initState() {
    super.initState();
    _totpTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _totpClock.value = DateTime.now();
    });
    _reload();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _totpTimer?.cancel();
    _totpClock.dispose();
    _searchController.dispose();
    _accountScrollController.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final seq = ++_reloadSeq;
    if (_accounts.isEmpty) {
      setState(() => _loading = true);
    }

    late final List<Account> allAccounts;
    try {
      allAccounts = await _loadAccounts('', tag: '');
    } catch (_) {
      if (!mounted || seq != _reloadSeq) return;
      setState(() {
        _loading = false;
        _loadError = '账号数据无法解密';
      });
      return;
    }
    if (!mounted || seq != _reloadSeq) return;

    final tags =
        allAccounts
            .expand((account) => account.tags)
            .where((tag) => tag != '动态密码' && tag != '我的收藏')
            .toSet()
            .toList()
          ..sort();
    setState(() {
      _allAccountsData = allAccounts;
      _accounts = _filterAccounts(
        allAccounts,
        query: _query,
        category: _selectedCategory,
      );
      _allTags = tags;
      _loading = false;
      _loadError = null;
    });
  }

  String _tagForCategory(String category) {
    return switch (category) {
      _dynamicPasswords => '',
      _favorites => '我的收藏',
      _ => category,
    };
  }

  List<Account> _filterAccounts(
    List<Account> source, {
    required String query,
    required String category,
  }) {
    final normalizedQuery = query.toLowerCase();
    final tag = _tagForCategory(category);
    final result = source
        .where(
          (account) =>
              (normalizedQuery.isEmpty ||
                  account.title.toLowerCase().contains(normalizedQuery) ||
                  account.username.toLowerCase().contains(normalizedQuery)) &&
              (category != _dynamicPasswords || account.totp != null) &&
              (tag.isEmpty || account.tags.contains(tag)),
        )
        .toList();
    result.sort(_compareAccounts);
    return result;
  }

  int _compareAccounts(Account left, Account right) {
    final groupComparison = _alphabetGroup(
      left.title,
    ).compareTo(_alphabetGroup(right.title));
    if (groupComparison != 0) return groupComparison;
    final titleComparison = left.title.toLowerCase().compareTo(
      right.title.toLowerCase(),
    );
    if (titleComparison != 0) return titleComparison;
    return left.username.toLowerCase().compareTo(right.username.toLowerCase());
  }

  int _alphabetGroup(String title) {
    final normalized = title.trimLeft().toUpperCase();
    if (normalized.isEmpty) return 26;
    final code = normalized.codeUnitAt(0);
    return code >= 65 && code <= 90 ? code - 65 : 26;
  }

  void _selectCategory(String category) {
    if (_selectedCategory == category) return;
    setState(() {
      _selectedCategory = category;
      _accounts = _filterAccounts(
        _allAccountsData,
        query: _query,
        category: category,
      );
    });
  }

  void _startSearch() {
    setState(() => _searching = true);
  }

  void _closeSearch() {
    _searchDebounce?.cancel();
    _searchController.clear();
    setState(() {
      _searching = false;
      _query = '';
      _accounts = _filterAccounts(
        _allAccountsData,
        query: '',
        category: _selectedCategory,
      );
    });
  }

  void _updateSearch(String value) {
    final query = value.trim();
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 180), () {
      if (!mounted) return;
      setState(() {
        _query = query;
        _accounts = _filterAccounts(
          _allAccountsData,
          query: query,
          category: _selectedCategory,
        );
      });
    });
  }

  Future<void> _openDetails(Account account) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => AccountDetailPage(account: account)),
    );
    if (changed == true) _reload();
  }

  Future<void> _openEdit([Account? account]) async {
    if (account != null) {
      await DatabaseHelper.instance.decryptSecret(account);
    }
    if (!mounted) return;
    final changed = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => EditPage(account: account)));
    if (changed == true) _reload();
  }

  Future<void> _delete(Account account) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除账号'),
        content: Text('确定删除「${account.title}」吗？'),
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
    if (confirmed != true) return;
    await DatabaseHelper.instance.deleteAccount(account.id!);
    _reload();
  }

  Future<void> _copyPassword(Account account) async {
    if (account.password.isEmpty) return;
    await DatabaseHelper.instance.decryptSecret(account);
    await SensitiveClipboard.copy(account.password);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('密码已复制'), duration: Duration(seconds: 1)),
    );
  }

  Future<void> _copyTotp(Account account) async {
    final totp = account.totp;
    if (totp == null) return;
    final clearAfter = AppSettings.instance.clipboardClearDelay;
    await SensitiveClipboard.copy(
      totp.codeAt(DateTime.now()),
      clearAfter: clearAfter,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('验证码已复制'), duration: Duration(seconds: 1)),
    );
  }

  Future<void> _showAccountActions(Account account) async {
    final action = await showModalBottomSheet<_AccountAction>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (account.password.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.content_copy_outlined),
                title: const Text('复制密码'),
                onTap: () =>
                    Navigator.of(context).pop(_AccountAction.copyPassword),
              ),
            if (account.totp != null)
              ListTile(
                leading: const Icon(Icons.timer_outlined),
                title: const Text('复制验证码'),
                onTap: () => Navigator.of(context).pop(_AccountAction.copyTotp),
              ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('编辑账号'),
              onTap: () => Navigator.of(context).pop(_AccountAction.edit),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('删除账号'),
              onTap: () => Navigator.of(context).pop(_AccountAction.delete),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (action) {
      case _AccountAction.copyPassword:
        await _copyPassword(account);
        break;
      case _AccountAction.copyTotp:
        await _copyTotp(account);
        break;
      case _AccountAction.edit:
        await _openEdit(account);
        break;
      case _AccountAction.delete:
        await _delete(account);
        break;
      case null:
        break;
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }

  Future<T> _runWithProgress<T>(
    String message,
    Future<T> Function() action,
  ) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    final route = DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              const SizedBox(width: 18),
              Expanded(child: Text(message)),
            ],
          ),
        ),
      ),
    );
    navigator.push<void>(route);
    await WidgetsBinding.instance.endOfFrame;
    try {
      return await action();
    } finally {
      if (route.isActive) navigator.removeRoute(route);
    }
  }

  Future<void> _exportEncryptedBackup() async {
    final password = await BackupPasswordDialog.show(
      context,
      mode: BackupPasswordMode.create,
    );
    if (password == null || !mounted) return;

    late final String content;
    try {
      content = await _runWithProgress('正在加密备份…', () async {
        final accounts = await DatabaseHelper.instance.listAccounts('');
        return EncryptedVaultBackup.create(accounts, password);
      });
    } catch (_) {
      _showMessage('备份创建失败，请重试');
      return;
    }
    if (!mounted) return;

    final bytes = Uint8List.fromList(utf8.encode(content));
    String? savedPath;
    AppLock.pickerActive = true;
    try {
      final mobile = Platform.isAndroid || Platform.isIOS;
      savedPath = await FilePicker.platform.saveFile(
        dialogTitle: '保存加密备份',
        fileName: _backupFileName(DateTime.now()),
        type: FileType.any,
        bytes: mobile ? bytes : null,
      );
      if (savedPath != null && !mobile) {
        await File(savedPath).writeAsBytes(bytes, flush: true);
      }
    } catch (_) {
      _showMessage('备份保存失败，请重试');
      return;
    } finally {
      AppLock.pickerActive = false;
      bytes.fillRange(0, bytes.length, 0);
    }
    if (savedPath != null) _showMessage('加密备份已保存');
  }

  Future<void> _restoreEncryptedBackup() async {
    FilePickerResult? picked;
    AppLock.pickerActive = true;
    try {
      picked = await FilePicker.platform.pickFiles(type: FileType.any);
    } finally {
      AppLock.pickerActive = false;
    }
    if (picked == null || picked.files.isEmpty || !mounted) return;
    final file = picked.files.single;
    if (file.size > EncryptedVaultBackup.maxFileBytes) {
      _showMessage('备份文件过大');
      return;
    }
    final path = file.path;
    if (path == null) {
      _showMessage('无法读取所选备份');
      return;
    }

    late final String content;
    try {
      content = await File(path).readAsString();
    } catch (_) {
      _showMessage('无法读取所选备份');
      return;
    }
    if (!mounted) return;
    final password = await BackupPasswordDialog.show(
      context,
      mode: BackupPasswordMode.unlock,
    );
    if (password == null || !mounted) return;

    VaultBackupData? backup;
    try {
      try {
        backup = await _runWithProgress(
          '正在验证备份…',
          () => EncryptedVaultBackup.open(content, password),
        );
      } on BackupFormatException {
        _showMessage('不是有效的账号本子备份');
        return;
      } on BackupDecryptException {
        _showMessage('备份密码错误或文件已损坏');
        return;
      } catch (_) {
        _showMessage('备份验证失败');
        return;
      }
      if (!mounted) return;

      final restoreCount = backup!.accounts.length;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('恢复加密备份？'),
          content: Text(
            '将用备份中的 $restoreCount 条账号替换当前 ${_allAccountsData.length} 条账号。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(true),
              icon: const Icon(Icons.restore),
              label: const Text('恢复'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;

      try {
        await _runWithProgress(
          '正在恢复账号…',
          () => DatabaseHelper.instance.restoreAccountsAtomically(
            backup!.accounts,
          ),
        );
      } catch (_) {
        _showMessage('恢复失败，当前账号未更改');
        return;
      }
      _selectedCategory = _allAccounts;
      await _reload();
      _showMessage('已恢复 $restoreCount 条账号');
    } finally {
      backup?.wipe();
    }
  }

  String _backupFileName(DateTime dateTime) {
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    final date =
        '${dateTime.year}${twoDigits(dateTime.month)}'
        '${twoDigits(dateTime.day)}';
    final time = '${twoDigits(dateTime.hour)}${twoDigits(dateTime.minute)}';
    return 'account-book-backup-$date-$time.abvault';
  }

  Future<void> _import() async {
    FilePickerResult? picked;
    AppLock.pickerActive = true;
    try {
      picked = await FilePicker.platform.pickFiles(type: FileType.any);
    } finally {
      AppLock.pickerActive = false;
    }
    if (picked == null || picked.files.isEmpty) return;
    final path = picked.files.single.path;
    if (path == null) return;

    try {
      final content = await File(path).readAsString();
      final parsed = AccountBoxImporter.parse(content);
      if (parsed.isEmpty) {
        _showMessage('文件中没有解析到账号');
        return;
      }
      final accounts = parsed
          .map(
            (item) => Account(
              title: item.title,
              username: item.username,
              password: item.password,
              extra: item.extra,
              tags: item.tags,
            ),
          )
          .toList();
      final preview = await DatabaseHelper.instance.previewImportAccounts(
        accounts,
      );
      if (!mounted) return;
      final conflictPolicy = await _chooseImportPolicy(preview);
      if (conflictPolicy == null) return;
      final result = await DatabaseHelper.instance.importAccounts(
        accounts,
        conflictPolicy: conflictPolicy,
      );
      _reload();
      final counts = [
        '导入 ${result.imported} 条',
        if (result.updated > 0) '更新 ${result.updated} 条',
        if (result.skipped > 0) '跳过 ${result.skipped} 条',
      ];
      _showMessage(counts.join('，'));
    } catch (_) {
      _showMessage('导入失败，请检查文件后重试');
    }
  }

  Future<ImportConflictPolicy?> _chooseImportPolicy(ImportPreview preview) {
    if (preview.conflicts == 0) {
      return showDialog<ImportConflictPolicy>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('导入账号'),
          content: Text('共读取 ${preview.total} 条账号'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(ImportConflictPolicy.skip),
              child: const Text('导入'),
            ),
          ],
        ),
      );
    }

    return showDialog<ImportConflictPolicy>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('发现 ${preview.conflicts} 条重复账号'),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
            child: Text('共读取 ${preview.total} 条账号'),
          ),
          SimpleDialogOption(
            onPressed: () =>
                Navigator.of(context).pop(ImportConflictPolicy.skip),
            child: const Row(
              children: [
                Icon(Icons.skip_next_outlined),
                SizedBox(width: 16),
                Text('跳过重复项'),
              ],
            ),
          ),
          SimpleDialogOption(
            onPressed: () =>
                Navigator.of(context).pop(ImportConflictPolicy.overwrite),
            child: const Row(
              children: [
                Icon(Icons.sync_outlined),
                SizedBox(width: 16),
                Text('覆盖已有账号'),
              ],
            ),
          ),
          SimpleDialogOption(
            onPressed: () =>
                Navigator.of(context).pop(ImportConflictPolicy.keepBoth),
            child: const Row(
              children: [
                Icon(Icons.copy_all_outlined),
                SizedBox(width: 16),
                Text('保留为副本'),
              ],
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(),
            child: const Row(
              children: [Icon(Icons.close), SizedBox(width: 16), Text('取消')],
            ),
          ),
        ],
      ),
    );
  }

  void _handleHomeAction(_HomeAction action) {
    switch (action) {
      case _HomeAction.import:
        _import();
        break;
      case _HomeAction.exportBackup:
        _exportEncryptedBackup();
        break;
      case _HomeAction.restoreBackup:
        _restoreEncryptedBackup();
        break;
      case _HomeAction.security:
        Navigator.of(context).push<void>(
          MaterialPageRoute(builder: (_) => const SecuritySettingsPage()),
        );
        break;
      case _HomeAction.lock:
        widget.onLock?.call();
        break;
    }
  }

  Future<void> _showTools() async {
    final action = await showModalBottomSheet<_HomeAction>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.file_download_outlined),
              title: const Text('导出加密备份'),
              onTap: () => Navigator.of(context).pop(_HomeAction.exportBackup),
            ),
            ListTile(
              leading: const Icon(Icons.restore_page_outlined),
              title: const Text('恢复加密备份'),
              onTap: () => Navigator.of(context).pop(_HomeAction.restoreBackup),
            ),
            ListTile(
              leading: const Icon(Icons.upload_file_outlined),
              title: const Text('导入账号'),
              onTap: () => Navigator.of(context).pop(_HomeAction.import),
            ),
            ListTile(
              leading: const Icon(Icons.security_outlined),
              title: const Text('安全设置'),
              onTap: () => Navigator.of(context).pop(_HomeAction.security),
            ),
            ListTile(
              leading: const Icon(Icons.lock_outline),
              title: const Text('锁定账号本子'),
              onTap: () => Navigator.of(context).pop(_HomeAction.lock),
            ),
          ],
        ),
      ),
    );
    if (action != null) _handleHomeAction(action);
  }

  Future<void> _showCategories() async {
    final categories = [
      ..._permanentCategories,
      for (final tag in _allTags) (tag, tag),
    ];
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.72,
        child: SafeArea(
          top: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(24, 4, 24, 12),
                child: Text(
                  '选择分类',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: categories.length,
                  itemBuilder: (context, index) {
                    final category = categories[index];
                    final selected = category.$1 == _selectedCategory;
                    return ListTile(
                      selected: selected,
                      leading: Icon(
                        selected ? Icons.check_circle : Icons.circle_outlined,
                      ),
                      title: Text(category.$2),
                      onTap: () => Navigator.of(context).pop(category.$1),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (selected != null) _selectCategory(selected);
  }

  String get _selectedCategoryLabel {
    for (final category in _permanentCategories) {
      if (category.$1 == _selectedCategory) return category.$2;
    }
    return _selectedCategory;
  }

  void _scrollToLetter(String letter) {
    if (_accounts.isEmpty || !_accountScrollController.hasClients) return;
    var index = 0;
    if (letter != '☆' && letter != '#') {
      final match = _accounts.indexWhere((account) {
        final title = account.title.trim();
        return title.isNotEmpty && title[0].toUpperCase() == letter;
      });
      if (match == -1) return;
      index = match;
    } else if (letter == '#') {
      final match = _accounts.indexWhere((account) {
        final title = account.title.trim();
        return title.isNotEmpty &&
            !RegExp(r'^[A-Za-z]').hasMatch(title.substring(0, 1));
      });
      if (match == -1) return;
      index = match;
    }
    _accountScrollController.animateTo(
      (index * 82.0)
          .clamp(0.0, _accountScrollController.position.maxScrollExtent)
          .toDouble(),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final compactLayout = MediaQuery.sizeOf(context).width < 600;
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        toolbarHeight: 60,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: _brandGreen,
        foregroundColor: Colors.white,
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: _brandGreen,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
        ),
        titleSpacing: 26,
        title: _searching
            ? TextField(
                key: const ValueKey('account-search-field'),
                controller: _searchController,
                autofocus: true,
                cursorColor: Colors.white,
                style: const TextStyle(color: Colors.white, fontSize: 19),
                decoration: const InputDecoration(
                  hintText: '搜索账号',
                  hintStyle: TextStyle(color: Color(0xBFFFFFFF)),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
                onChanged: _updateSearch,
              )
            : const Text(
                '账号本子',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 25,
                  fontWeight: FontWeight.w400,
                ),
              ),
        actions: _searching
            ? [
                IconButton(
                  tooltip: '关闭搜索',
                  onPressed: _closeSearch,
                  icon: const Icon(Icons.close, size: 28),
                ),
                const SizedBox(width: 8),
              ]
            : [
                IconButton(
                  tooltip: '添加账号',
                  onPressed: () => _openEdit(),
                  icon: const Icon(Icons.add, size: 34),
                ),
                IconButton(
                  tooltip: '搜索账号',
                  onPressed: _startSearch,
                  icon: const Icon(Icons.search, size: 31),
                ),
                PopupMenuButton<_HomeAction>(
                  tooltip: '更多',
                  onSelected: _handleHomeAction,
                  icon: const Icon(Icons.more_vert, size: 29),
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: _HomeAction.exportBackup,
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.file_download_outlined),
                        title: Text('导出加密备份'),
                      ),
                    ),
                    PopupMenuItem(
                      value: _HomeAction.restoreBackup,
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.restore_page_outlined),
                        title: Text('恢复加密备份'),
                      ),
                    ),
                    PopupMenuItem(
                      value: _HomeAction.import,
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.upload_file_outlined),
                        title: Text('导入账号'),
                      ),
                    ),
                    PopupMenuItem(
                      value: _HomeAction.security,
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.security_outlined),
                        title: Text('安全设置'),
                      ),
                    ),
                    PopupMenuItem(
                      value: _HomeAction.lock,
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.lock_outline),
                        title: Text('锁定'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 10),
              ],
      ),
      body: compactLayout
          ? Column(
              children: [
                _CompactCategoryBar(
                  label: _selectedCategoryLabel,
                  count: _accounts.length,
                  onTap: _showCategories,
                ),
                Expanded(child: _buildAccountList()),
              ],
            )
          : LayoutBuilder(
              builder: (context, constraints) => Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 170,
                    child: _CategorySidebar(
                      selectedCategory: _selectedCategory,
                      tags: _allTags,
                      onSelected: _selectCategory,
                      onSettings: _showTools,
                    ),
                  ),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: _buildAccountList()),
                        _AlphabetRail(
                          alphabet: _alphabet,
                          onSelected: _scrollToLetter,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildAccountList() {
    if (_loading && _accounts.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: _brandGreen));
    }
    if (_loadError case final message?) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Color(0xFF9E9E9E), size: 32),
            const SizedBox(height: 10),
            Text(
              message,
              style: const TextStyle(color: Color(0xFF777777), fontSize: 15),
            ),
            const SizedBox(height: 6),
            IconButton(
              tooltip: '重试',
              onPressed: _reload,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
      );
    }
    if (_accounts.isEmpty) {
      final noFilters = _query.isEmpty && _selectedCategory == _allAccounts;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            noFilters ? '还没有账号，点击右上角 + 添加' : '没有匹配的结果',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF9E9E9E), fontSize: 15),
          ),
        ),
      );
    }

    return ListView.builder(
      controller: _accountScrollController,
      itemExtent: 82,
      scrollCacheExtent: const ScrollCacheExtent.viewport(1.2),
      addAutomaticKeepAlives: false,
      padding: const EdgeInsets.only(top: 0, bottom: 24),
      itemCount: _accounts.length,
      itemBuilder: (context, index) {
        final account = _accounts[index];
        if (_selectedCategory == _dynamicPasswords && account.totp != null) {
          return ValueListenableBuilder<DateTime>(
            valueListenable: _totpClock,
            builder: (context, now, _) {
              final totp = account.totp!;
              final code = formatTotpCode(totp.codeAt(now));
              final remaining = totp.remainingSeconds(now);
              return ListTile(
                contentPadding: const EdgeInsets.only(left: 18, right: 4),
                title: Text(
                  account.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF282828),
                    fontSize: 20,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Text(
                    '$code · $remaining 秒',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _brandGreen,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                trailing: IconButton(
                  tooltip: '复制验证码',
                  onPressed: () => _copyTotp(account),
                  icon: const Icon(Icons.copy_outlined, color: _brandGreen),
                ),
                onTap: () => _openDetails(account),
                onLongPress: () => _showAccountActions(account),
              );
            },
          );
        }
        return ListTile(
          contentPadding: const EdgeInsets.only(left: 18, right: 4),
          title: Text(
            account.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF282828),
              fontSize: 20,
              fontWeight: FontWeight.w400,
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Text(
              account.username.isEmpty ? '*' : account.username,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFB4B4B4),
                fontSize: 17,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
          trailing: account.password.isNotEmpty
              ? IconButton(
                  tooltip: '复制密码',
                  onPressed: () => _copyPassword(account),
                  icon: const Icon(Icons.copy_outlined, color: _brandGreen),
                )
              : account.totp != null
              ? IconButton(
                  tooltip: '复制验证码',
                  onPressed: () => _copyTotp(account),
                  icon: const Icon(Icons.timer_outlined, color: _brandGreen),
                )
              : null,
          onTap: () => _openDetails(account),
          onLongPress: () => _showAccountActions(account),
        );
      },
    );
  }
}

class _CategorySidebar extends StatelessWidget {
  const _CategorySidebar({
    required this.selectedCategory,
    required this.tags,
    required this.onSelected,
    required this.onSettings,
  });

  static const _brandGreen = Color(0xFF00965E);

  final String selectedCategory;
  final List<String> tags;
  final ValueChanged<String> onSelected;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFFAFAFA),
      child: ListView(
        padding: const EdgeInsets.only(top: 25, bottom: 12),
        children: [
          for (final category in _HomePageState._permanentCategories)
            _CategoryButton(
              label: category.$2,
              selected: selectedCategory == category.$1,
              onTap: () => onSelected(category.$1),
            ),
          const SizedBox(height: 8),
          for (final tag in tags)
            _CategoryButton(
              label: tag,
              selected: selectedCategory == tag,
              onTap: () => onSelected(tag),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              tooltip: '设置与工具',
              onPressed: onSettings,
              padding: const EdgeInsets.all(20),
              icon: const Icon(
                Icons.settings_outlined,
                size: 24,
                color: Color(0xFFAAAAAA),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactCategoryBar extends StatelessWidget {
  const _CompactCategoryBar({
    required this.label,
    required this.count,
    required this.onTap,
  });

  final String label;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF4F5F5),
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 48,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Icon(
                  Icons.filter_list,
                  size: 20,
                  color: Color(0xFF666666),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF333333),
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  '$count 项',
                  style: const TextStyle(
                    color: Color(0xFF888888),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.expand_more, color: Color(0xFF777777)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CategoryButton extends StatelessWidget {
  const _CategoryButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected
                    ? _CategorySidebar._brandGreen
                    : const Color(0xFF2C2C2C),
                fontSize: 18,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AlphabetRail extends StatelessWidget {
  const _AlphabetRail({required this.alphabet, required this.onSelected});

  final List<String> alphabet;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 25,
      child: SafeArea(
        top: false,
        left: false,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            for (final letter in alphabet)
              Expanded(
                child: InkWell(
                  onTap: () => onSelected(letter),
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        letter,
                        style: const TextStyle(
                          color: Color(0xFFD0D0D0),
                          fontSize: 13,
                          height: 1,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
