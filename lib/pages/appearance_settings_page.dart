import 'package:flutter/material.dart';

import '../settings/app_settings.dart';

class AppearanceSettingsPage extends StatefulWidget {
  const AppearanceSettingsPage({super.key});

  @override
  State<AppearanceSettingsPage> createState() => _AppearanceSettingsPageState();
}

class _AppearanceSettingsPageState extends State<AppearanceSettingsPage> {
  late double _textScaleFactor;
  late String _fontFamilyKey;
  late AppThemeMode _themeMode;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final settings = AppSettings.instance;
    _textScaleFactor = settings.textScaleFactor;
    _fontFamilyKey = settings.fontFamily ?? '';
    _themeMode = settings.themeMode;
  }

  Future<void> _setTextScale(double? value) async {
    if (value == null || value == _textScaleFactor || _saving) return;
    final previous = _textScaleFactor;
    setState(() {
      _textScaleFactor = value;
      _saving = true;
    });
    try {
      await AppSettings.instance.setTextScaleFactor(value);
    } catch (_) {
      if (mounted) {
        setState(() => _textScaleFactor = previous);
        _showMessage('设置保存失败，请重试');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _setFontFamily(String? value) async {
    if (value == null || value == _fontFamilyKey || _saving) return;
    final previous = _fontFamilyKey;
    setState(() {
      _fontFamilyKey = value;
      _saving = true;
    });
    try {
      await AppSettings.instance.setFontFamily(value.isEmpty ? null : value);
    } catch (_) {
      if (mounted) {
        setState(() => _fontFamilyKey = previous);
        _showMessage('设置保存失败，请重试');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _setThemeMode(AppThemeMode? value) async {
    if (value == null || value == _themeMode || _saving) return;
    final previous = _themeMode;
    setState(() {
      _themeMode = value;
      _saving = true;
    });
    try {
      await AppSettings.instance.setThemeMode(value);
    } catch (_) {
      if (mounted) {
        setState(() => _themeMode = previous);
        _showMessage('设置保存失败，请重试');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('界面设置')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          const _SectionTitle('文字'),
          _SettingDropdownTile<double>(
            icon: Icons.format_size,
            title: '文字大小',
            value: _textScaleFactor,
            enabled: !_saving,
            labelBuilder: AppSettings.textScaleLabel,
            options: AppSettings.textScaleOptions,
            onChanged: _setTextScale,
          ),
          const Divider(height: 1, indent: 56),
          _SettingDropdownTile<String>(
            icon: Icons.font_download_outlined,
            title: '字体',
            value: _fontFamilyKey,
            enabled: !_saving,
            labelBuilder: (value) =>
                AppSettings.fontFamilyLabel(value.isEmpty ? null : value),
            options: [
              for (final option in AppSettings.fontFamilyOptions) option ?? '',
            ],
            onChanged: _setFontFamily,
          ),
          const _SectionTitle('主题'),
          _SettingDropdownTile<AppThemeMode>(
            icon: Icons.brightness_6_outlined,
            title: '界面主题',
            value: _themeMode,
            enabled: !_saving,
            labelBuilder: AppSettings.themeModeLabel,
            options: AppThemeMode.values,
            onChanged: _setThemeMode,
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
      child: Text(
        text,
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _SettingDropdownTile<T> extends StatelessWidget {
  const _SettingDropdownTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.enabled,
    required this.options,
    required this.labelBuilder,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final T value;
  final bool enabled;
  final List<T> options;
  final String Function(T) labelBuilder;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      trailing: DropdownButton<T>(
        value: value,
        underline: const SizedBox.shrink(),
        onChanged: enabled ? onChanged : null,
        items: [
          for (final option in options)
            DropdownMenuItem<T>(
              value: option,
              child: Text(labelBuilder(option)),
            ),
        ],
      ),
    );
  }
}
