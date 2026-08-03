import 'package:flutter/material.dart';

import '../security/password_security.dart';
import 'password_strength_indicator.dart';

class PasswordGeneratorSheet extends StatefulWidget {
  const PasswordGeneratorSheet({super.key});

  static Future<String?> show(BuildContext context) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => const PasswordGeneratorSheet(),
    );
  }

  @override
  State<PasswordGeneratorSheet> createState() => _PasswordGeneratorSheetState();
}

class _PasswordGeneratorSheetState extends State<PasswordGeneratorSheet> {
  PasswordGeneratorOptions _options = const PasswordGeneratorOptions();
  late String _password;
  late PasswordStrength _strength;

  @override
  void initState() {
    super.initState();
    _regenerate(notify: false);
  }

  void _regenerate({bool notify = true}) {
    final password = generatePassword(_options);
    final strength = evaluatePasswordStrength(password);
    if (notify) {
      setState(() {
        _password = password;
        _strength = strength;
      });
    } else {
      _password = password;
      _strength = strength;
    }
  }

  void _updateOptions(PasswordGeneratorOptions options) {
    _options = options;
    _regenerate();
  }

  bool _canDisable(bool enabled) {
    return !enabled || _options.enabledPoolCount > 1;
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('生成密码', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          Container(
            constraints: const BoxConstraints(minHeight: 64),
            padding: const EdgeInsets.fromLTRB(16, 10, 4, 10),
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SelectableText(
                      _password,
                      key: const ValueKey('generated-password'),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 17,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '重新生成',
                  onPressed: _regenerate,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          PasswordStrengthIndicator(strength: _strength),
          const SizedBox(height: 20),
          Row(
            children: [
              const Text('长度'),
              const SizedBox(width: 12),
              Expanded(
                child: Slider(
                  value: _options.length.toDouble(),
                  min: 6,
                  max: 64,
                  divisions: 58,
                  label: '${_options.length}',
                  onChanged: (value) =>
                      _updateOptions(_options.copyWith(length: value.round())),
                ),
              ),
              SizedBox(
                width: 32,
                child: Text(
                  '${_options.length}',
                  textAlign: TextAlign.end,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth / 2;
              return Wrap(
                children: [
                  SizedBox(
                    width: width,
                    child: _CharacterSetOption(
                      label: '小写字母',
                      value: _options.useLowercase,
                      onChanged: _canDisable(_options.useLowercase)
                          ? (value) => _updateOptions(
                              _options.copyWith(useLowercase: value),
                            )
                          : null,
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: _CharacterSetOption(
                      label: '大写字母',
                      value: _options.useUppercase,
                      onChanged: _canDisable(_options.useUppercase)
                          ? (value) => _updateOptions(
                              _options.copyWith(useUppercase: value),
                            )
                          : null,
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: _CharacterSetOption(
                      label: '数字',
                      value: _options.useNumbers,
                      onChanged: _canDisable(_options.useNumbers)
                          ? (value) => _updateOptions(
                              _options.copyWith(useNumbers: value),
                            )
                          : null,
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: _CharacterSetOption(
                      label: '符号',
                      value: _options.useSymbols,
                      onChanged: _canDisable(_options.useSymbols)
                          ? (value) => _updateOptions(
                              _options.copyWith(useSymbols: value),
                            )
                          : null,
                    ),
                  ),
                ],
              );
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('排除易混淆字符'),
            value: _options.excludeAmbiguous,
            onChanged: (value) =>
                _updateOptions(_options.copyWith(excludeAmbiguous: value)),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(_password),
            icon: const Icon(Icons.check),
            label: const Text('使用此密码'),
          ),
        ],
      ),
    );
  }
}

class _CharacterSetOption extends StatelessWidget {
  const _CharacterSetOption({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      controlAffinity: ListTileControlAffinity.leading,
      title: Text(label),
      value: value,
      onChanged: onChanged == null
          ? null
          : (value) {
              if (value != null) onChanged!(value);
            },
    );
  }
}
