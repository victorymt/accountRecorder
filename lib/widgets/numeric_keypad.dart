import 'package:flutter/material.dart';

/// A compact, touch-friendly numeric keypad that never opens the system
/// keyboard.
class NumericKeypad extends StatelessWidget {
  const NumericKeypad({
    super.key,
    required this.onDigit,
    required this.onBackspace,
    required this.onClear,
    this.enabled = true,
  });

  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final VoidCallback onClear;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final keys = <Widget>[
      for (final digit in ['1', '2', '3', '4', '5', '6', '7', '8', '9'])
        _DigitButton(
          digit: digit,
          enabled: enabled,
          onPressed: () => onDigit(digit),
        ),
      _ActionButton(
        icon: Icons.clear_all,
        label: '清空',
        enabled: enabled,
        onPressed: onClear,
      ),
      _DigitButton(digit: '0', enabled: enabled, onPressed: () => onDigit('0')),
      _ActionButton(
        icon: Icons.backspace_outlined,
        label: '删除',
        enabled: enabled,
        onPressed: onBackspace,
      ),
    ];

    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final key in keys) SizedBox(width: 64, height: 60, child: key),
      ],
    );
  }
}

/// Displays the number of entered PIN digits without exposing the PIN value.
class PinDisplay extends StatelessWidget {
  const PinDisplay({
    super.key,
    required this.label,
    required this.value,
    this.length = 6,
  });

  final String label;
  final String value;
  final int length;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: '$label，已输入 ${value.length} 位，共 $length 位',
      child: Column(
        children: [
          Text(label, style: theme.textTheme.titleMedium),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              length,
              (index) => Container(
                width: 18,
                height: 18,
                margin: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: index < value.length
                      ? theme.colorScheme.primary
                      : theme.colorScheme.surfaceContainerHighest,
                  border: Border.all(
                    color: index < value.length
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outline,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DigitButton extends StatelessWidget {
  const _DigitButton({
    required this.digit,
    required this.enabled,
    required this.onPressed,
  });

  final String digit;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '数字 $digit',
      child: FilledButton.tonal(
        onPressed: enabled ? onPressed : null,
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 60),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: Theme.of(context).textTheme.headlineSmall,
        ),
        child: Text(digit),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Tooltip(
        message: label,
        child: FilledButton.tonal(
          onPressed: enabled ? onPressed : null,
          style: FilledButton.styleFrom(
            minimumSize: const Size(64, 60),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
          ),
          child: Icon(icon),
        ),
      ),
    );
  }
}
