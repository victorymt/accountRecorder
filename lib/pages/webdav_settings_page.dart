import 'package:flutter/material.dart';

import '../backup/webdav_backup.dart';
import '../settings/app_settings.dart';

class WebDavSettingsPage extends StatefulWidget {
  const WebDavSettingsPage({super.key, this.settings});

  final AppSettings? settings;

  @override
  State<WebDavSettingsPage> createState() => _WebDavSettingsPageState();
}

class _WebDavSettingsPageState extends State<WebDavSettingsPage> {
  late final TextEditingController _urlController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late final TextEditingController _pathController;
  bool _saving = false;
  bool _testing = false;
  bool _obscurePassword = true;
  String? _urlError;
  String? _pathError;

  AppSettings get _settings => widget.settings ?? AppSettings.instance;

  @override
  void initState() {
    super.initState();
    final settings = _settings;
    _urlController = TextEditingController(text: settings.webDavUrl);
    _usernameController = TextEditingController(text: settings.webDavUsername);
    _passwordController = TextEditingController(text: settings.webDavPassword);
    _pathController = TextEditingController(text: settings.webDavPath);
  }

  @override
  void dispose() {
    _urlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _pathController.dispose();
    super.dispose();
  }

  WebDavConfig _config() {
    return WebDavConfig(
      endpoint: _urlController.text,
      username: _usernameController.text,
      password: _passwordController.text,
      remotePath: _pathController.text,
    );
  }

  Future<bool> _save() async {
    if (_saving) return false;
    if (!_validate()) return false;
    setState(() => _saving = true);
    try {
      await _settings.setWebDavConfig(
        url: _urlController.text,
        username: _usernameController.text,
        password: _passwordController.text,
        path: _pathController.text,
      );
      return true;
    } on ArgumentError {
      _showMessage('WebDAV 设置无效，请检查输入');
      return false;
    } catch (_) {
      _showMessage('设置保存失败，请重试');
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveAndClose() async {
    if (await _save() && mounted) Navigator.of(context).pop(true);
  }

  Future<void> _testConnection() async {
    if (_testing || _saving) return;
    if (!_validate(requireEndpoint: true)) return;
    setState(() => _testing = true);
    final client = WebDavClient(_config());
    try {
      await client.testConnection();
      _showMessage('WebDAV 连接成功');
    } on WebDavException catch (error) {
      _showMessage(error.message);
    } catch (_) {
      _showMessage('WebDAV 连接失败');
    } finally {
      client.close();
      if (mounted) setState(() => _testing = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }

  bool _validate({bool requireEndpoint = false}) {
    final endpoint = _urlController.text.trim();
    final path = _pathController.text.trim().replaceAll('\\', '/');
    final parsed = Uri.tryParse(endpoint);
    final invalidEndpoint =
        (requireEndpoint && endpoint.isEmpty) ||
        (endpoint.isNotEmpty &&
            (parsed == null ||
                (parsed.scheme != 'http' && parsed.scheme != 'https') ||
                parsed.host.isEmpty ||
                parsed.userInfo.isNotEmpty ||
                parsed.hasQuery ||
                parsed.hasFragment));
    final segments = path.split('/').where((segment) => segment.isNotEmpty);
    final invalidPath =
        path.isEmpty ||
        segments.any((segment) => segment == '.' || segment == '..');
    setState(() {
      _urlError = invalidEndpoint
          ? endpoint.isEmpty
                ? '请输入 WebDAV 地址'
                : '请输入有效的 HTTP(S) 地址'
          : null;
      _pathError = invalidPath ? '请输入有效的远端文件路径' : null;
    });
    return !invalidEndpoint && !invalidPath;
  }

  @override
  Widget build(BuildContext context) {
    final busy = _saving || _testing;
    return Scaffold(
      appBar: AppBar(
        title: const Text('WebDAV 设置'),
        actions: [
          IconButton(
            tooltip: '保存',
            onPressed: busy ? null : _saveAndClose,
            icon: const Icon(Icons.save_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          TextField(
            controller: _urlController,
            keyboardType: TextInputType.url,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: 'WebDAV 地址',
              hintText: 'https://dav.example.com/remote.php/dav/files/me',
              prefixIcon: const Icon(Icons.cloud_outlined),
              errorText: _urlError,
            ),
            onChanged: (_) {
              if (_urlError != null) setState(() => _urlError = null);
            },
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _pathController,
            keyboardType: TextInputType.url,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: '远端文件路径',
              hintText: 'account-book-backup.abvault',
              prefixIcon: const Icon(Icons.insert_drive_file_outlined),
              errorText: _pathError,
            ),
            onChanged: (_) {
              if (_pathError != null) setState(() => _pathError = null);
            },
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _usernameController,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              labelText: '用户名',
              prefixIcon: Icon(Icons.person_outline),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: '密码',
              prefixIcon: const Icon(Icons.password_outlined),
              suffixIcon: IconButton(
                tooltip: _obscurePassword ? '显示密码' : '隐藏密码',
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            '同步状态：${_syncStatusLabel()}',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: busy ? null : _testConnection,
            icon: _testing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.network_check_outlined),
            label: Text(_testing ? '正在测试…' : '测试连接'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: busy ? null : _saveAndClose,
            icon: const Icon(Icons.save_outlined),
            label: const Text('保存设置'),
          ),
        ],
      ),
    );
  }

  String _syncStatusLabel() {
    final upload = _formatTime(_settings.lastWebDavUploadAt);
    final download = _formatTime(_settings.lastWebDavDownloadAt);
    if (upload == null && download == null) return '尚未同步';
    return '上传 ${upload ?? '未同步'} · 下载 ${download ?? '未同步'}';
  }

  String? _formatTime(DateTime? value) {
    if (value == null) return null;
    final local = value.toLocal();
    String twoDigits(int number) => number.toString().padLeft(2, '0');
    return '${local.month}/${local.day} ${twoDigits(local.hour)}:${twoDigits(local.minute)}';
  }
}
